package com.xiaowenssh.agent;

import com.xiaowenssh.agent.guard.AutoConfirmationHandler;
import com.xiaowenssh.agent.guard.CommandGuard;
import com.xiaowenssh.persistence.AuditService;
import com.xiaowenssh.persistence.entity.SessionEntity;
import com.xiaowenssh.persistence.mapper.SessionMapper;
import com.xiaowenssh.ssh.SshClient;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

/**
 * Agent 测试接口 —— M2 验证 agentic loop 用，验证完会删/改。
 *
 * 用法（POST application/json）：
 *   curl -X POST http://localhost:8081/api/agent/run \
 *     -H 'Content-Type: application/json' \
 *     -d '{"host":"1.2.3.4","user":"root","password":"xxx","task":"看下根分区还剩多少空间"}'
 *
 * 会话级固定一台目标机：进来先建一条 session（拿 id 给审计用），连一次 SSH，
 * 整轮 loop 复用同一连接，结束即释放。
 */
@RestController
public class AgentController {

    private final AgentService agentService;
    private final SessionMapper sessionMapper;
    private final AuditService auditService;
    private final CommandGuard guard;

    public AgentController(AgentService agentService, SessionMapper sessionMapper,
                           AuditService auditService, CommandGuard guard) {
        this.agentService = agentService;
        this.sessionMapper = sessionMapper;
        this.auditService = auditService;
        this.guard = guard;
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

        // try-with-resources：loop 跑完自动关连接
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
     * 流式版本：用 SSE 把 agent 执行过程逐事件吐出来。
     *   curl -N -X POST http://localhost:8081/api/agent/stream \
     *     -H 'Content-Type: application/json' \
     *     -d '{"host":"1.2.3.4","user":"root","password":"xxx","task":"看下根分区还剩多少空间"}'
     *
     * 注意：loop 在独立线程异步跑，方法会先返回 Flux，所以 SSH 连接不能 try-with-resources，
     * 必须在 Flux.doFinally 里关——无论正常结束还是客户端断开，都释放连接。
     */
    @PostMapping(value = "/api/agent/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<AgentEvent>> stream(@RequestBody RunRequest req) {
        int port = req.port() == 0 ? 22 : req.port();

        SessionEntity session = new SessionEntity();
        session.setTitle(req.task());
        session.setSshHost(req.host());
        session.setSshPort(port);
        session.setSshUser(req.user());
        sessionMapper.insert(session);
        Long sessionId = session.getId();

        SshClient ssh = new SshClient();
        try {
            ssh.connect(req.host(), port, req.user(), req.password());
        } catch (Exception e) {
            ssh.close();
            // 连接阶段就失败：直接吐一个 error 事件，不进 loop
            return Flux.just(sse(new AgentEvent.Error("SSH 连接失败: " + e.getMessage())));
        }

        SshTools tools = new SshTools(ssh, sessionId, auditService, guard);
        return agentService.runStream(sessionId, req.task(), tools, new AutoConfirmationHandler())
                .map(this::sse)
                .doFinally(signal -> ssh.close());
    }

    /** 把领域事件包成 SSE：event 名取事件 type，方便前端按类型分发 */
    private ServerSentEvent<AgentEvent> sse(AgentEvent event) {
        return ServerSentEvent.<AgentEvent>builder()
                .event(event.type())
                .data(event)
                .build();
    }

    /** 请求体 */
    public record RunRequest(String host, int port, String user, String password, String task) {
    }
}
