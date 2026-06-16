package com.xiaowenssh.ssh;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.Properties;

/**
 * SSH 客户端 —— 简化版方案 B：一个实例持有一个长连接，多条命令复用同一会话。
 *
 * 为什么是长连接复用：这是个 agentic 运维 agent，loop 里会连续执行多条命令，
 * 每次重连既慢、又丢上下文。MVP 阶段先不上连接池，够用。
 *
 * 注意：非线程安全，一个 SshClient 实例对应一台机器的一个会话，由上层串行使用。
 */
public class SshClient implements AutoCloseable {

    private final JSch jsch = new JSch();
    private Session session;

    /**
     * 建立连接。密码认证（MVP 够用，后续可加密钥）。
     */
    public void connect(String host, int port, String username, String password) throws Exception {
        session = jsch.getSession(username, host, port);
        session.setPassword(password);

        // demo 方便：跳过 host key 校验。生产环境要换成 known_hosts 校验，否则有中间人风险
        Properties config = new Properties();
        config.put("StrictHostKeyChecking", "no");
        session.setConfig(config);

        // 连接超时 10s
        session.connect(10_000);
    }

    /**
     * 执行一条命令，同时收集 stdout、stderr、exitCode。
     *
     * JSch 的坑：stdout 走 channel 的 InputStream，stderr 要单独用 setErrStream 接，
     * exitCode 必须等 channel 真正关闭后才能拿到，所以这里要轮询 isClosed。
     */
    public ExecResult exec(String command) throws Exception {
        if (session == null || !session.isConnected()) {
            throw new IllegalStateException("SSH 未连接，先调用 connect()");
        }

        ChannelExec channel = (ChannelExec) session.openChannel("exec");
        channel.setCommand(command);

        ByteArrayOutputStream stdout = new ByteArrayOutputStream();
        ByteArrayOutputStream stderr = new ByteArrayOutputStream();
        channel.setErrStream(stderr);          // stderr 直接重定向到内存流
        InputStream in = channel.getInputStream(); // stdout 手动读

        channel.connect();

        // 边读 stdout 边等命令结束
        byte[] buf = new byte[4096];
        while (true) {
            while (in.available() > 0) {
                int n = in.read(buf, 0, buf.length);
                if (n < 0) break;
                stdout.write(buf, 0, n);
            }
            // channel 关闭代表命令执行完毕
            if (channel.isClosed()) {
                if (in.available() > 0) continue; // 还有残留数据，再读一轮
                break;
            }
            Thread.sleep(50); // 没数据也没关闭，稍等避免空转
        }

        int exitCode = channel.getExitStatus();
        channel.disconnect();

        return new ExecResult(
                stdout.toString(java.nio.charset.StandardCharsets.UTF_8),
                stderr.toString(java.nio.charset.StandardCharsets.UTF_8),
                exitCode
        );
    }

    /** 当前是否连接中 */
    public boolean isConnected() {
        return session != null && session.isConnected();
    }

    /** 关闭会话，释放连接 */
    @Override
    public void close() {
        if (session != null && session.isConnected()) {
            session.disconnect();
        }
    }
}
