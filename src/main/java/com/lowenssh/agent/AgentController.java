package com.lowenssh.agent;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.lowenssh.agent.guard.AutoConfirmationHandler;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.persistence.AuditService;
import com.lowenssh.persistence.MessageService;
import com.lowenssh.persistence.entity.SessionEntity;
import com.lowenssh.persistence.mapper.SessionMapper;
import com.lowenssh.ssh.SshClient;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Agent 接口。
 *
 * 流式端点支持多轮对话：
 *  - 首轮：sessionId 为空，带 host/port/user/password，SessionManager 建会话 + 连一次 SSH，
 *    把连接常驻；先回 session_ready 事件把 sessionId 给前端。
 *  - 续聊：sessionId 非空，复用该会话的常驻连接（保留 cd 等上下文），历史从库里回灌给模型。
 *
 * 连接生命周期归 SessionManager 管（超时回收 / 显式关闭），不再随单次请求开关。
 */
@RestController
public class AgentController {

    private final AgentService agentService;
    private final SessionManager sessionManager;
    private final SessionMapper sessionMapper;
    private final AuditService auditService;
    private final MessageService messageService;
    private final CommandGuard guard;

    public AgentController(AgentService agentService, SessionManager sessionManager,
                           SessionMapper sessionMapper, AuditService auditService,
                           MessageService messageService, CommandGuard guard) {
        this.agentService = agentService;
        this.sessionManager = sessionManager;
        this.sessionMapper = sessionMapper;
        this.auditService = auditService;
        this.messageService = messageService;
        this.guard = guard;
    }

    private static final DateTimeFormatter TS_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    /**
     * 列出会话，按更新时间倒序（左侧历史栏用）。
     * 带 hostId 则只列该主机的会话（历史按主机隔离）；不带则列全部（兼容旧调用）。
     * 只读查库，不碰 SSH。
     */
    @GetMapping("/api/agent/sessions")
    public List<SessionDto.SessionItem> sessions(
            @org.springframework.web.bind.annotation.RequestParam(value = "hostId", required = false) Long hostId) {
        LambdaQueryWrapper<SessionEntity> wrapper = new LambdaQueryWrapper<SessionEntity>()
                .eq(hostId != null, SessionEntity::getHostId, hostId)
                .orderByDesc(SessionEntity::getUpdatedAt)
                .orderByDesc(SessionEntity::getId);  // updatedAt 为空时退而按 id 排
        return sessionMapper.selectList(wrapper).stream()
                .map(s -> new SessionDto.SessionItem(
                        s.getId(), s.getTitle(), s.getSshHost(), s.getSshUser(), s.getSshPort(),
                        s.getUpdatedAt() == null ? null : s.getUpdatedAt().format(TS_FMT)))
                .toList();
    }

    /**
     * 拉某会话的历史消息 + 连接信息 + 常驻连接是否存活（左栏点开旧会话回看用）。
     * live=true 表示常驻连接还在，可直接续聊；false 则前端提示需重连。
     * 只读查库 + 查内存连接状态，不碰 SSH 执行。
     */
    @GetMapping("/api/agent/sessions/{id}/messages")
    public SessionDto.SessionDetail sessionMessages(@PathVariable("id") Long id) {
        SessionEntity s = sessionMapper.selectById(id);
        if (s == null) {
            return new SessionDto.SessionDetail(id, null, null, null, false, List.of());
        }
        boolean live = sessionManager.get(id) != null;
        return new SessionDto.SessionDetail(
                id, s.getSshHost(), s.getSshPort(), s.getSshUser(), live,
                messageService.loadHistoryForView(id));
    }

    @PostMapping("/api/agent/run")
    public String run(@RequestBody RunRequest req) {
        int port = req.port() == 0 ? 22 : req.port();

        // 先建会话拿 id：审计要 session_id 关联
        SessionEntity session = new SessionEntity();
        session.setTitle(req.task());
        session.setSshHost(req.host());
        session.setSshPort(port);
        session.setSshUser(req.user());
        sessionMapper.insert(session);
        Long sessionId = session.getId();

        // try-with-resources：loop 跑完自动关连接（同步接口是一次性测试用，不参与多轮常驻）
        try (SshClient ssh = new SshClient()) {
            ssh.connect(req.host(), port, req.user(), req.password());
            SshTools tools = new SshTools(ssh, sessionId, auditService, guard);
            // REST 场景用自动确认：deny 已被门禁拦死，ask 态自动放行以便自动化测试
            return agentService.run(sessionId, req.task(), tools, new AutoConfirmationHandler());
        } catch (Exception e) {
            return "任务执行失败: " + e.getMessage();
        }
    }

    /**
     * 流式 + 多轮：用 SSE 把 agent 执行过程逐事件吐出来。
     *
     * 首轮（curl 示例，sessionId 不传）：
     *   curl -N -X POST http://localhost:8081/api/agent/stream \
     *     -H 'Content-Type: application/json' \
     *     -d '{"host":"1.2.3.4","user":"root","password":"xxx","task":"看下根分区还剩多少空间"}'
     * 续聊：带上首轮拿到的 sessionId，连接信息可省：
     *     -d '{"sessionId":1,"task":"那内存呢"}'
     *
     * 连接由 SessionManager 常驻，这里不再 doFinally 关连接。
     */
    @PostMapping(value = "/api/agent/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<AgentEvent>> stream(@RequestBody RunRequest req) {
        SessionManager.LiveSession live;
        boolean firstTurn = req.sessionId() == null;

        if (firstTurn) {
            // 首轮：复用进主机时建好的预连接；没有（curl 直连）则现连一次。再落库建会话行（title=任务）。
            int port = req.port() == 0 ? 22 : req.port();
            try {
                live = sessionManager.getByHost(req.hostId());
                if (live == null) {
                    live = sessionManager.connectHost(req.hostId(), req.host(), port, req.user(), req.password());
                }
                sessionManager.attachSession(live, req.task());
            } catch (Exception e) {
                return Flux.just(sse(new AgentEvent.Error("SSH 连接失败: " + e.getMessage())));
            }
        } else {
            // 续聊：取常驻连接；不存在/已过期则提示前端重连
            live = sessionManager.get(req.sessionId());
            if (live == null) {
                return Flux.just(sse(new AgentEvent.SessionExpired(req.sessionId(),
                        "常驻连接已断开（空闲超时回收），请在右侧开新会话重连")));
            }
        }

        Long sessionId = live.sessionId();
        // 每轮新建 SshTools，但底层复用 manager 里同一个常驻 SshClient（保留 cd 等上下文）
        SshTools tools = new SshTools(live.ssh(), sessionId, auditService, guard);

        Flux<ServerSentEvent<AgentEvent>> events = agentService
                .runStream(sessionId, req.task(), tools, new AutoConfirmationHandler())
                .map(this::sse);

        // 首轮在事件流最前面插一个 session_ready，把 sessionId 交给前端用于后续续聊
        if (firstTurn) {
            events = Flux.concat(Flux.just(sse(new AgentEvent.SessionReady(sessionId))), events);
        }
        return events;
    }

    /** 把领域事件包成 SSE：event 名取事件 type，方便前端按类型分发 */
    private ServerSentEvent<AgentEvent> sse(AgentEvent event) {
        return ServerSentEvent.<AgentEvent>builder()
                .event(event.type())
                .data(event)
                .build();
    }

    /** 请求体。sessionId 为空=首轮（带 hostId/host/port/user/password 新建会话+连 SSH）；
     *  非空=续聊（复用该会话的常驻连接，连接信息可不传） */
    public record RunRequest(Long sessionId, Long hostId, String host, int port, String user, String password, String task) {
    }
}
