package com.lowenssh.agent;

import com.lowenssh.persistence.mapper.SessionMapper;
import com.lowenssh.ssh.SshClient;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * SessionManager 单测 —— open() 要连真 SSH，这里不测；聚焦不依赖真连接的逻辑：
 * get（命中/不存在/连接已断）、close（关连接 + 幂等）、reap（回收超时/断开会话）。
 *
 * 用反射把 mock 的 LiveSession 塞进内部 map，绕开 open() 的真实 SSH 连接。
 */
class SessionManagerTest {

    private final SessionMapper sessionMapper = mock(SessionMapper.class);

    /** 反射取出内部 bySession map（已绑定会话的活连接） */
    @SuppressWarnings("unchecked")
    private Map<Long, SessionManager.LiveSession> sessionsOf(SessionManager mgr) throws Exception {
        Field f = SessionManager.class.getDeclaredField("bySession");
        f.setAccessible(true);
        return (Map<Long, SessionManager.LiveSession>) f.get(mgr);
    }

    /** 造一个挂了 mock SshClient 的 LiveSession（回填 sessionId）并塞进 manager */
    private SshClient injectSession(SessionManager mgr, Long id, boolean connected) throws Exception {
        SshClient ssh = mock(SshClient.class);
        when(ssh.isConnected()).thenReturn(connected);
        SessionManager.LiveSession live = new SessionManager.LiveSession(1L, "h", 22, "root", ssh);
        live.sessionId = id;
        sessionsOf(mgr).put(id, live);
        return ssh;
    }

    @Test
    void get命中活跃会话() throws Exception {
        SessionManager mgr = new SessionManager(sessionMapper, 30);
        injectSession(mgr, 1L, true);

        SessionManager.LiveSession live = mgr.get(1L);

        assertThat(live).isNotNull();
        assertThat(live.sessionId()).isEqualTo(1L);
    }

    @Test
    void get不存在的会话返回null() {
        SessionManager mgr = new SessionManager(sessionMapper, 30);
        assertThat(mgr.get(999L)).isNull();
    }

    @Test
    void get发现连接已断则移除并返回null() throws Exception {
        SessionManager mgr = new SessionManager(sessionMapper, 30);
        SshClient ssh = injectSession(mgr, 2L, false);  // 连接已断

        assertThat(mgr.get(2L)).isNull();
        assertThat(mgr.activeCount()).isZero();
        verify(ssh).close();  // 顺手关掉
    }

    @Test
    void close关连接并移除且幂等() throws Exception {
        SessionManager mgr = new SessionManager(sessionMapper, 30);
        SshClient ssh = injectSession(mgr, 3L, true);

        mgr.close(3L);
        assertThat(mgr.activeCount()).isZero();
        verify(ssh, times(1)).close();

        // 再关一次不报错、不重复关
        mgr.close(3L);
        verify(ssh, times(1)).close();
    }

    @Test
    void reap回收超时会话保留活跃会话() throws Exception {
        SessionManager mgr = new SessionManager(sessionMapper, 30);
        // 活跃会话：刚活动过
        SshClient fresh = injectSession(mgr, 10L, true);
        // 超时会话：lastActiveAt 拨到 31 分钟前
        SshClient stale = injectSession(mgr, 11L, true);
        SessionManager.LiveSession staleLive = sessionsOf(mgr).get(11L);
        Field lastActive = SessionManager.LiveSession.class.getDeclaredField("lastActiveAt");
        lastActive.setAccessible(true);
        lastActive.set(staleLive, Instant.now().minusSeconds(31 * 60));

        mgr.reapIdleSessions();

        assertThat(mgr.activeCount()).isEqualTo(1);
        verify(stale).close();      // 超时的被回收
        verify(fresh, never()).close();  // 活跃的保留
    }
}
