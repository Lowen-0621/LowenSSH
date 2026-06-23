package com.lowenssh.agent;

import com.lowenssh.persistence.entity.SessionEntity;
import com.lowenssh.persistence.mapper.SessionMapper;
import com.lowenssh.ssh.SshClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantLock;

/**
 * 会话管理器 —— 支撑多轮对话的「连接常驻」：
 * 进主机时连一次 SSH，把连接挂成「预连接」常驻，首条任务到来才落库建会话行（lazy create），
 * 后续轮复用同一连接（保留 cd 等上下文），会话结束或超时无活动才关闭。
 *
 * 为什么 lazy create：进主机就建会话行会堆出一堆没消息、没标题的空会话。改成
 * 「进主机只连不落库，首条任务才落库（title=任务）」，标题和消息天然落在同一个 sessionId 上。
 *
 * 两张表：
 *   byHost   —— 进主机建的预连接（hostId→连接），还没发首条任务，sessionId 仍为 null。
 *   bySession —— 首条任务 attach 后的正式会话（sessionId→连接），续聊按它查。
 * 一条预连接首条任务后从 byHost 移出、登记进 bySession，不会同时在两张表里。
 *
 * 并发：SshClient 非线程安全。每个 LiveSession 自带一把锁，同一会话的多个请求串行执行。
 * 连接泄漏防护：@Scheduled 定时扫两张表，关掉超时无活动的连接。
 */
@Component
public class SessionManager {

    private static final Logger log = LoggerFactory.getLogger(SessionManager.class);

    private final SessionMapper sessionMapper;

    /** 会话空闲超时（分钟）：超过这么久没活动的连接会被定时任务回收 */
    private final long idleTimeoutMinutes;

    /** hostId -> 进主机时建的预连接（已连 SSH、未发首条任务）。首条任务 attach 后移出。 */
    private final Map<Long, LiveSession> byHost = new ConcurrentHashMap<>();

    /** sessionId -> 已绑定会话的活连接，续聊按它查。 */
    private final Map<Long, LiveSession> bySession = new ConcurrentHashMap<>();

    public SessionManager(SessionMapper sessionMapper,
                          @Value("${xwssh.agent.session-idle-timeout-minutes:30}") long idleTimeoutMinutes) {
        this.sessionMapper = sessionMapper;
        this.idleTimeoutMinutes = idleTimeoutMinutes;
    }

    /**
     * 一个活跃连接：SSH 连接 + 锁 + 最后活跃时间 + 建连时的连接信息（attach 落库要用）。
     * sessionId 未绑定会话前为 null（进主机已连，但还没发首条任务）。
     * lock 保证同一会话的请求串行（SshClient 非线程安全）。
     */
    public static class LiveSession {
        volatile Long sessionId;   // 首条任务 attach 后回填
        final Long hostId;         // 所属主机，进主机按它复用预连接
        final String host;
        final int port;
        final String user;
        final SshClient ssh;
        final ReentrantLock lock = new ReentrantLock();
        volatile Instant lastActiveAt = Instant.now();

        LiveSession(Long hostId, String host, int port, String user, SshClient ssh) {
            this.hostId = hostId;
            this.host = host;
            this.port = port;
            this.user = user;
            this.ssh = ssh;
        }

        public Long sessionId() {
            return sessionId;
        }

        public Long hostId() {
            return hostId;
        }

        public SshClient ssh() {
            return ssh;
        }

        public ReentrantLock lock() {
            return lock;
        }

        void touch() {
            this.lastActiveAt = Instant.now();
        }
    }

    /**
     * 进主机：复用该主机的预连接（若仍连通），否则连一次 SSH 建预连接。不落库。
     * 真正的会话行延迟到首条任务 attachSession 时才插，避免堆空会话。
     * hostId 为 null（curl 直连调试）时不进 byHost，连完直接返回。
     * 连接失败抛异常，调用方转成 error 事件。
     */
    public LiveSession connectHost(Long hostId, String host, int port, String user, String password) throws Exception {
        if (hostId != null) {
            LiveSession existing = byHost.get(hostId);
            if (existing != null && existing.ssh.isConnected()) {
                existing.touch();
                return existing;  // 复用该主机现有预连接
            }
        }
        SshClient ssh = new SshClient();
        try {
            ssh.connect(host, port, user, password);
        } catch (Exception e) {
            ssh.close();
            throw e;
        }
        LiveSession live = new LiveSession(hostId, host, port, user, ssh);
        if (hostId != null) {
            byHost.put(hostId, live);
        }
        log.info("预连接已建立 hostId={} host={}", hostId, host);
        return live;
    }

    /** 取该主机进主机时建的预连接（尚未发首条任务）；无或已断返回 null。 */
    public LiveSession getByHost(Long hostId) {
        if (hostId == null) {
            return null;
        }
        LiveSession live = byHost.get(hostId);
        if (live != null && live.ssh.isConnected()) {
            live.touch();
            return live;
        }
        return null;
    }

    /**
     * 首条任务：把预连接升级为正式会话 —— 落库拿 sessionId（title=首条任务），
     * 回填到 live、移出 byHost、登记进 bySession。返回 sessionId。
     */
    public Long attachSession(LiveSession live, String task) {
        SessionEntity session = new SessionEntity();
        session.setHostId(live.hostId);
        session.setTitle(toTitle(task));  // 标题是会话名摘要，截断防超列长（title VARCHAR(255)）
        session.setSshHost(live.host);
        session.setSshPort(live.port);
        session.setSshUser(live.user);
        sessionMapper.insert(session);
        Long sessionId = session.getId();

        live.sessionId = sessionId;
        if (live.hostId != null) {
            byHost.remove(live.hostId, live);  // 出预连接槽（仅当仍是当前预连接）
        }
        bySession.put(sessionId, live);
        log.info("会话已绑定 sessionId={} hostId={} 当前活跃会话数={}", sessionId, live.hostId, bySession.size());
        return sessionId;
    }

    /** 任务文本压成会话标题：取首行、超 40 字截断加省略号，远小于 title 列上限避免落库截断报错 */
    public static String toTitle(String task) {
        if (task == null) return "新会话";
        String t = task.strip();
        int nl = t.indexOf('\n');
        if (nl >= 0) t = t.substring(0, nl).strip();
        if (t.isEmpty()) return "新会话";
        return t.length() > 40 ? t.substring(0, 40) + "…" : t;
    }

    /**
     * 续聊：取已绑定会话的常驻连接。
     * 返回 null 表示会话不存在或已过期（前端据此提示重新连接）。
     */
    public LiveSession get(Long sessionId) {
        LiveSession live = bySession.get(sessionId);
        if (live == null) {
            return null;
        }
        // 连接可能已被对端断开，校验一下
        if (!live.ssh.isConnected()) {
            log.warn("会话连接已断开 sessionId={}，移除", sessionId);
            close(sessionId);
            return null;
        }
        live.touch();
        return live;
    }

    /** 关闭并移除一个会话（显式结束 / 连接失效时调用） */
    public void close(Long sessionId) {
        LiveSession live = bySession.remove(sessionId);
        if (live != null) {
            live.ssh.close();
            if (live.hostId != null) {
                byHost.remove(live.hostId, live);
            }
            log.info("会话已关闭 sessionId={} 剩余活跃会话数={}", sessionId, bySession.size());
        }
    }

    /** 定时回收超时无活动的连接（含从未发任务的预连接），防连接泄漏。每 5 分钟扫一次。 */
    @Scheduled(fixedDelay = 5 * 60 * 1000)
    public void reapIdleSessions() {
        Instant deadline = Instant.now().minus(Duration.ofMinutes(idleTimeoutMinutes));
        int reaped = reap(byHost, deadline) + reap(bySession, deadline);
        if (reaped > 0) {
            log.info("回收超时连接 {} 个，剩余活跃会话 {} 个", reaped, bySession.size());
        }
    }

    /** 扫一张表，关掉超时或已断开的连接 */
    private int reap(Map<Long, LiveSession> map, Instant deadline) {
        Iterator<Map.Entry<Long, LiveSession>> it = map.entrySet().iterator();
        int reaped = 0;
        while (it.hasNext()) {
            LiveSession live = it.next().getValue();
            if (live.lastActiveAt.isBefore(deadline) || !live.ssh.isConnected()) {
                live.ssh.close();
                it.remove();
                reaped++;
            }
        }
        return reaped;
    }

    /** 当前活跃会话数（监控/测试用） */
    public int activeCount() {
        return bySession.size();
    }
}
