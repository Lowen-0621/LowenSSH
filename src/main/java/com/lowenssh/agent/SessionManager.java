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
 * 首轮建会话时连一次 SSH，把连接挂在会话上常驻，后续轮复用同一连接（保留 cd 等上下文），
 * 会话结束或超时无活动才关闭。
 *
 * 为什么要它：原设计是「一个 task = 连一次 SSH 跑完即关」，无法多轮。把 SSH 连接的
 * 生命周期从「单次请求」提升到「整个会话」，多轮对话才能复用连接、接续上下文。
 *
 * 并发：SshClient 非线程安全。每个 LiveSession 自带一把锁，同一会话的多个请求串行执行，
 * 避免命令在同一 channel 上交叉。
 *
 * 连接泄漏防护：常驻连接若只开不关会越积越多。@Scheduled 定时扫描，关掉超时无活动的会话。
 */
@Component
public class SessionManager {

    private static final Logger log = LoggerFactory.getLogger(SessionManager.class);

    private final SessionMapper sessionMapper;

    /** 会话空闲超时（分钟）：超过这么久没活动的连接会被定时任务回收 */
    private final long idleTimeoutMinutes;

    /** sessionId -> 活跃会话（含常驻 SSH 连接） */
    private final Map<Long, LiveSession> sessions = new ConcurrentHashMap<>();

    public SessionManager(SessionMapper sessionMapper,
                          @Value("${xwssh.agent.session-idle-timeout-minutes:30}") long idleTimeoutMinutes) {
        this.sessionMapper = sessionMapper;
        this.idleTimeoutMinutes = idleTimeoutMinutes;
    }

    /**
     * 一个活跃会话：常驻 SSH 连接 + 锁 + 最后活跃时间。
     * lock 保证同一会话的请求串行（SshClient 非线程安全）。
     */
    public static class LiveSession {
        final Long sessionId;
        final Long hostId;       // 所属主机，connect 时按它复用活会话
        final SshClient ssh;
        final ReentrantLock lock = new ReentrantLock();
        volatile Instant lastActiveAt = Instant.now();

        LiveSession(Long sessionId, Long hostId, SshClient ssh) {
            this.sessionId = sessionId;
            this.hostId = hostId;
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
     * 首轮：建会话（落库拿 id）+ 连一次 SSH + 挂进常驻表。
     * 连接失败会抛异常，调用方负责转成 error 事件。
     */
    public LiveSession open(Long hostId, String host, int port, String user, String password, String task) throws Exception {
        // 先落库拿 sessionId（审计/历史都按它关联）
        SessionEntity session = new SessionEntity();
        session.setHostId(hostId);
        session.setTitle(task);
        session.setSshHost(host);
        session.setSshPort(port);
        session.setSshUser(user);
        sessionMapper.insert(session);
        Long sessionId = session.getId();

        SshClient ssh = new SshClient();
        try {
            ssh.connect(host, port, user, password);
        } catch (Exception e) {
            ssh.close();
            throw e;
        }

        LiveSession live = new LiveSession(sessionId, hostId, ssh);
        sessions.put(sessionId, live);
        log.info("会话已建立 sessionId={} hostId={} host={} 当前活跃会话数={}", sessionId, hostId, host, sessions.size());
        return live;
    }

    /**
     * 进入主机时调用：若该主机已有活着的会话直接复用（不堆空会话），否则建一个新空会话并连接。
     * task 传 null —— connect 阶段只建立连接，标题等首条任务到来时再补。
     */
    public LiveSession openForHost(Long hostId, String host, int port, String user, String password) throws Exception {
        LiveSession existing = findLiveByHost(hostId);
        if (existing != null) {
            return existing;  // 复用该主机现有活连接
        }
        return open(hostId, host, port, user, password, null);
    }

    /** 找某主机下当前活着的会话（连接仍连通），没有返回 null */
    public LiveSession findLiveByHost(Long hostId) {
        for (LiveSession live : sessions.values()) {
            if (hostId.equals(live.hostId) && live.ssh.isConnected()) {
                live.touch();
                return live;
            }
        }
        return null;
    }

    /**
     * 续聊：取已有会话的常驻连接。
     * 返回 null 表示会话不存在或已过期（前端据此提示重新连接）。
     */
    public LiveSession get(Long sessionId) {
        LiveSession live = sessions.get(sessionId);
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
        LiveSession live = sessions.remove(sessionId);
        if (live != null) {
            live.ssh.close();
            log.info("会话已关闭 sessionId={} 剩余活跃会话数={}", sessionId, sessions.size());
        }
    }

    /** 定时回收超时无活动的会话，防连接泄漏。每 5 分钟扫一次。 */
    @Scheduled(fixedDelay = 5 * 60 * 1000)
    public void reapIdleSessions() {
        Instant deadline = Instant.now().minus(Duration.ofMinutes(idleTimeoutMinutes));
        Iterator<Map.Entry<Long, LiveSession>> it = sessions.entrySet().iterator();
        int reaped = 0;
        while (it.hasNext()) {
            Map.Entry<Long, LiveSession> entry = it.next();
            LiveSession live = entry.getValue();
            if (live.lastActiveAt.isBefore(deadline) || !live.ssh.isConnected()) {
                live.ssh.close();
                it.remove();
                reaped++;
            }
        }
        if (reaped > 0) {
            log.info("回收超时会话 {} 个，剩余活跃 {} 个", reaped, sessions.size());
        }
    }

    /** 当前活跃会话数（监控/测试用） */
    public int activeCount() {
        return sessions.size();
    }
}
