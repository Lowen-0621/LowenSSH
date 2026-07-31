package com.lowenssh.ssh;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.ChannelSftp;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;
import com.jcraft.jsch.SftpException;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.Vector;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * SSH 客户端 —— 简化版方案 B：一个实例持有一个长连接，多条命令复用同一会话。
 *
 * 为什么是长连接复用：这是个 agentic 运维 agent，loop 里会连续执行多条命令，
 * 每次重连既慢、又丢上下文。MVP 阶段先不上连接池，够用。
 *
 * 注意：非线程安全，一个 SshClient 实例对应一台机器的一个会话，由上层串行使用。
 */
public class SshClient implements AutoCloseable {

    public static final Duration DEFAULT_CONNECT_TIMEOUT = Duration.ofSeconds(10);
    public static final Duration DEFAULT_COMMAND_TIMEOUT = Duration.ofSeconds(30);
    public static final int DEFAULT_MAX_OUTPUT_BYTES = 1024 * 1024;

    private final JSch jsch = new JSch();
    private final Duration connectTimeout;
    private final Duration commandTimeout;
    private final int maxOutputBytes;
    private final boolean strictHostKeyChecking;
    private final Path knownHostsPath;
    private final SshExecutionObserver executionObserver;
    private final AtomicReference<ActiveCommand> activeCommand = new AtomicReference<>();
    private Session session;
    // SFTP 通道：懒开 + 保持复用（同一 Session 上长期有效），随 close 一并释放。
    // 上层用 LiveSession.lock() 串行化，这里不另加锁。
    private ChannelSftp sftp;

    public SshClient() {
        this(DEFAULT_CONNECT_TIMEOUT, DEFAULT_COMMAND_TIMEOUT, DEFAULT_MAX_OUTPUT_BYTES,
                false, null, SshExecutionObserver.NOOP);
    }

    public SshClient(Duration connectTimeout, Duration commandTimeout, int maxOutputBytes) {
        this(connectTimeout, commandTimeout, maxOutputBytes, false, null,
                SshExecutionObserver.NOOP);
    }

    public SshClient(Duration connectTimeout,
                     Duration commandTimeout,
                     int maxOutputBytes,
                     boolean strictHostKeyChecking,
                     Path knownHostsPath) {
        this(connectTimeout, commandTimeout, maxOutputBytes,
                strictHostKeyChecking, knownHostsPath, SshExecutionObserver.NOOP);
    }

    public SshClient(Duration connectTimeout,
                     Duration commandTimeout,
                     int maxOutputBytes,
                     boolean strictHostKeyChecking,
                     Path knownHostsPath,
                     SshExecutionObserver executionObserver) {
        this.connectTimeout = requirePositive(connectTimeout, "SSH 连接超时");
        this.commandTimeout = requirePositive(commandTimeout, "SSH 命令超时");
        if (maxOutputBytes <= 0) {
            throw new IllegalArgumentException("SSH 最大输出字节数必须大于 0");
        }
        this.maxOutputBytes = maxOutputBytes;
        this.strictHostKeyChecking = strictHostKeyChecking;
        this.knownHostsPath = knownHostsPath;
        this.executionObserver = executionObserver == null
                ? SshExecutionObserver.NOOP : executionObserver;
    }

    /**
     * 建立连接。密码认证（MVP 够用，后续可加密钥）。
     */
    public void connect(String host, int port, String username, String password) throws Exception {
        connect(host, port, username, new SshAuth.Password(password));
    }

    public void connect(String host, int port, String username, SshAuth auth) throws Exception {
        if (auth == null) {
            throw new IllegalArgumentException("SSH 认证方式不能为空");
        }
        configureIdentity(auth);
        session = jsch.getSession(username, host, port);
        if (auth instanceof SshAuth.Password password) {
            session.setPassword(password.value());
        }

        Properties config = new Properties();
        if (strictHostKeyChecking) {
            prepareKnownHosts();
            config.put("StrictHostKeyChecking", "yes");
        } else {
            config.put("StrictHostKeyChecking", "no");
        }
        config.put("PreferredAuthentications",
                auth instanceof SshAuth.Password
                        ? "password,keyboard-interactive"
                        : "publickey");
        session.setConfig(config);

        session.connect(toMillisInt(connectTimeout));
    }

    private void configureIdentity(SshAuth auth) throws Exception {
        if (auth instanceof SshAuth.PrivateKey privateKey) {
            if (privateKey.path() == null || !Files.isRegularFile(privateKey.path())) {
                throw new IllegalArgumentException("SSH 私钥文件不存在");
            }
            if (privateKey.passphrase() == null || privateKey.passphrase().isEmpty()) {
                jsch.addIdentity(privateKey.path().toString());
            } else {
                jsch.addIdentity(privateKey.path().toString(), privateKey.passphrase());
            }
        } else if (auth instanceof SshAuth.Agent) {
            throw new UnsupportedOperationException(
                    "当前 JSch 未安装 SSH Agent 连接器；请使用密码或私钥认证");
        }
    }

    private void prepareKnownHosts() throws Exception {
        if (knownHostsPath == null) {
            throw new IllegalStateException("严格主机校验已启用，但未配置 known_hosts 路径");
        }
        Path absolute = knownHostsPath.toAbsolutePath().normalize();
        Path parent = absolute.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        if (Files.notExists(absolute)) {
            Files.createFile(absolute);
        }
        jsch.setKnownHosts(absolute.toString());
    }

    /**
     * 执行一条命令，同时收集 stdout、stderr、exitCode。
     *
     * JSch 的坑：stdout 走 channel 的 InputStream，stderr 要单独用 setErrStream 接，
     * exitCode 必须等 channel 真正关闭后才能拿到，所以这里要轮询 isClosed。
     */
    public ExecResult exec(String command) throws Exception {
        long started = System.nanoTime();
        try {
            ExecResult result = doExec(command);
            executionObserver.completed(
                    result, null, Duration.ofNanos(System.nanoTime() - started));
            return result;
        } catch (Exception e) {
            executionObserver.completed(
                    null, e, Duration.ofNanos(System.nanoTime() - started));
            throw e;
        }
    }

    private ExecResult doExec(String command) throws Exception {
        if (session == null || !session.isConnected()) {
            throw new IllegalStateException("SSH 未连接，先调用 connect()");
        }

        ChannelExec channel = (ChannelExec) session.openChannel("exec");
        channel.setCommand(command);

        OutputBudget outputBudget = new OutputBudget(maxOutputBytes);
        BoundedOutputStream stdout = new BoundedOutputStream(outputBudget);
        BoundedOutputStream stderr = new BoundedOutputStream(outputBudget);
        channel.setErrStream(stderr);          // stderr 直接重定向到内存流
        InputStream in = channel.getInputStream(); // stdout 手动读

        ActiveCommand execution = new ActiveCommand(channel);
        if (!activeCommand.compareAndSet(null, execution)) {
            channel.disconnect();
            throw new IllegalStateException("同一 SSH 连接不能并发执行多条命令");
        }

        boolean timedOut = false;
        boolean cancelled = false;
        int exitCode = -1;
        try {
            channel.connect(toMillisInt(connectTimeout));
            long deadline = System.nanoTime() + commandTimeout.toNanos();

            // 即使超过输出上限也继续排空远端输出，只丢弃多余字节，避免远端因管道写满而卡死。
            byte[] buf = new byte[4096];
            while (true) {
                while (in.available() > 0) {
                    int n = in.read(buf, 0, buf.length);
                    if (n < 0) break;
                    stdout.write(buf, 0, n);
                }
                if (execution.cancelRequested.get()) {
                    cancelled = true;
                    break;
                }
                if (channel.isClosed()) {
                    if (in.available() > 0) continue;
                    exitCode = channel.getExitStatus();
                    break;
                }
                if (System.nanoTime() >= deadline) {
                    timedOut = true;
                    break;
                }
                try {
                    Thread.sleep(50);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    execution.cancelRequested.set(true);
                    cancelled = true;
                    break;
                }
            }
        } catch (Exception e) {
            // 取消可能与 Channel.connect() 竞态；此时 JSch 会报 channel is not opened，
            // 但业务语义仍是用户取消，不应伪装成普通 SSH 故障。
            if (execution.cancelRequested.get()) {
                cancelled = true;
            } else {
                throw e;
            }
        } finally {
            channel.disconnect();
            activeCommand.compareAndSet(execution, null);
        }

        if (timedOut || cancelled) {
            verifySessionAfterForcedChannelClose();
        }

        return new ExecResult(
                stdout.asString(),
                stderr.asString(),
                exitCode,
                timedOut,
                cancelled,
                outputBudget.truncated()
        );
    }

    /**
     * 取消当前命令，只关闭 exec Channel，不主动关闭可复用 Session。
     * 返回 false 表示当前没有命令在执行。
     */
    public boolean cancelActiveCommand() {
        ActiveCommand execution = activeCommand.get();
        if (execution == null) {
            return false;
        }
        execution.cancelRequested.set(true);
        execution.channel.disconnect();
        return true;
    }

    boolean hasActiveCommand() {
        return activeCommand.get() != null;
    }

    /** 当前是否连接中 */
    public boolean isConnected() {
        return session != null && session.isConnected();
    }

    // ===================== SFTP 文件操作 =====================
    // 复用同一条 SSH Session 开 sftp 通道，不重连。非线程安全，由上层串行调用。

    /** 懒开并复用 sftp 通道；断了就重开 */
    private ChannelSftp sftp() throws Exception {
        if (session == null || !session.isConnected()) {
            throw new IllegalStateException("SSH 未连接，先调用 connect()");
        }
        if (sftp == null || !sftp.isConnected()) {
            sftp = (ChannelSftp) session.openChannel("sftp");
            sftp.connect(toMillisInt(connectTimeout));
        }
        return sftp;
    }

    /** 列目录。过滤掉 . 和 ..，按「目录在前、名称升序」排列 */
    @SuppressWarnings("unchecked")
    public List<RemoteFile> listDir(String path) throws Exception {
        Vector<ChannelSftp.LsEntry> entries = sftp().ls(path);
        String base = path.endsWith("/") ? path : path + "/";
        List<RemoteFile> result = new ArrayList<>();
        for (ChannelSftp.LsEntry e : entries) {
            String name = e.getFilename();
            if (name.equals(".") || name.equals("..")) continue;
            var attrs = e.getAttrs();
            result.add(new RemoteFile(
                    name,
                    base + name,
                    attrs.getSize(),
                    attrs.isDir(),
                    attrs.getPermissionsString(),  // 形如 "drwxr-xr-x"
                    attrs.getMTime()
            ));
        }
        result.sort((a, b) -> {
            if (a.isDir() != b.isDir()) return a.isDir() ? -1 : 1;
            return a.name().compareToIgnoreCase(b.name());
        });
        return result;
    }

    /** 上传：从输入流写到远端路径（覆盖） */
    public void upload(InputStream in, String remotePath) throws Exception {
        sftp().put(in, remotePath, ChannelSftp.OVERWRITE);
    }

    /** 下载：把远端文件写到输出流 */
    public void download(String remotePath, OutputStream out) throws Exception {
        sftp().get(remotePath, out);
    }

    /** 通过 SFTP 读取文本，不拼接 Shell；超过输出上限只保留前部。 */
    public String readTextFile(String remotePath) throws Exception {
        try (InputStream input = sftp().get(remotePath)) {
            OutputBudget budget = new OutputBudget(maxOutputBytes);
            BoundedOutputStream output = new BoundedOutputStream(budget);
            input.transferTo(output);
            String text = output.asString();
            return budget.truncated()
                    ? text + "\n…（文件内容超过 SSH 输出上限，已截断）"
                    : text;
        }
    }

    /**
     * 通过 SFTP 读取日志尾部。使用固定大小环形缓冲，文件再大也不会无界占内存。
     */
    public String tailTextFile(String remotePath, int lines) throws Exception {
        if (lines <= 0 || lines > 10_000) {
            throw new IllegalArgumentException("日志行数必须在 1 到 10000 之间");
        }
        byte[] ring = new byte[maxOutputBytes];
        long total = 0;
        try (InputStream input = sftp().get(remotePath)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                for (int i = 0; i < read; i++) {
                    ring[(int) (total % ring.length)] = buffer[i];
                    total++;
                }
            }
        }
        int retained = (int) Math.min(total, ring.length);
        byte[] ordered = new byte[retained];
        long start = Math.max(0, total - retained);
        for (int i = 0; i < retained; i++) {
            ordered[i] = ring[(int) ((start + i) % ring.length)];
        }
        String text = new String(ordered, StandardCharsets.UTF_8);
        String[] split = text.split("\\R", -1);
        int from = Math.max(0, split.length - lines - 1);
        String result = String.join(System.lineSeparator(),
                java.util.Arrays.copyOfRange(split, from, split.length));
        return total > retained
                ? "…（仅保留文件尾部 " + retained + " 字节）\n" + result
                : result;
    }

    /** 删除文件 */
    public void deleteFile(String path) throws Exception {
        sftp().rm(path);
    }

    /** 新建目录 */
    public void mkdir(String path) throws Exception {
        sftp().mkdir(path);
    }

    /** 重命名/移动 */
    public void rename(String from, String to) throws Exception {
        sftp().rename(from, to);
    }

    /** 远端路径是否为目录（不存在也返回 false） */
    public boolean isDir(String path) {
        try {
            return sftp().stat(path).isDir();
        } catch (SftpException e) {
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    /** 关闭会话，释放 sftp 通道和连接 */
    @Override
    public void close() {
        cancelActiveCommand();
        if (sftp != null && sftp.isConnected()) {
            sftp.disconnect();
        }
        if (session != null && session.isConnected()) {
            session.disconnect();
        }
    }

    /**
     * 强制关闭 Channel 后探测 Session。探测失败说明连接不可安全复用，直接关闭。
     * Channel 超时本身不等于 Session 已损坏，因此不无条件断开长连接。
     */
    private void verifySessionAfterForcedChannelClose() {
        if (session == null || !session.isConnected()) {
            return;
        }
        try {
            session.sendKeepAliveMsg();
        } catch (Exception e) {
            session.disconnect();
        }
    }

    private static Duration requirePositive(Duration value, String name) {
        if (value == null || value.isZero() || value.isNegative()) {
            throw new IllegalArgumentException(name + "必须大于 0");
        }
        return value;
    }

    private static int toMillisInt(Duration duration) {
        long millis = duration.toMillis();
        if (millis > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("SSH 超时不能超过 " + Integer.MAX_VALUE + "ms");
        }
        return Math.toIntExact(millis);
    }

    private record ActiveCommand(ChannelExec channel, AtomicBoolean cancelRequested) {
        private ActiveCommand(ChannelExec channel) {
            this(channel, new AtomicBoolean(false));
        }
    }

    /** stdout/stderr 共用一个总预算，避免两路输出各自占满上限。 */
    static final class OutputBudget {
        private int remaining;
        private boolean truncated;

        OutputBudget(int maxBytes) {
            this.remaining = maxBytes;
        }

        synchronized int claim(int requested) {
            int accepted = Math.min(requested, remaining);
            remaining -= accepted;
            if (accepted < requested) {
                truncated = true;
            }
            return accepted;
        }

        synchronized boolean truncated() {
            return truncated;
        }
    }

    static final class BoundedOutputStream extends OutputStream {
        private final OutputBudget budget;
        private final ByteArrayOutputStream delegate = new ByteArrayOutputStream();

        BoundedOutputStream(OutputBudget budget) {
            this.budget = budget;
        }

        @Override
        public synchronized void write(int value) {
            if (budget.claim(1) == 1) {
                delegate.write(value);
            }
        }

        @Override
        public synchronized void write(byte[] bytes, int offset, int length) {
            int accepted = budget.claim(length);
            if (accepted > 0) {
                delegate.write(bytes, offset, accepted);
            }
        }

        synchronized String asString() {
            return delegate.toString(StandardCharsets.UTF_8);
        }
    }
}
