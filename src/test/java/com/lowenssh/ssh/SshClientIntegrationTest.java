package com.lowenssh.ssh;

import org.apache.sshd.server.Environment;
import org.apache.sshd.server.ExitCallback;
import org.apache.sshd.server.SshServer;
import org.apache.sshd.server.channel.ChannelSession;
import org.apache.sshd.server.command.Command;
import org.apache.sshd.server.keyprovider.SimpleGeneratorHostKeyProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;

/** 通过真实 SSH 协议验证超时关闭 Channel 后的 Session 复用和输出硬上限。 */
class SshClientIntegrationTest {

    @TempDir
    Path tempDir;

    private SshServer server;

    @BeforeEach
    void startServer() throws IOException {
        server = SshServer.setUpDefaultServer();
        server.setHost("127.0.0.1");
        server.setPort(0);
        server.setKeyPairProvider(
                new SimpleGeneratorHostKeyProvider(tempDir.resolve("host-key")));
        server.setPasswordAuthenticator((username, password, session) ->
                "tester".equals(username) && "secret".equals(password));
        server.setCommandFactory((channel, command) -> new TestCommand(command));
        server.start();
    }

    @AfterEach
    void stopServer() throws IOException {
        server.stop(true);
    }

    @Test
    void 阻塞命令超时后同一Session仍可执行下一条命令() throws Exception {
        try (SshClient client = new SshClient(
                Duration.ofSeconds(2), Duration.ofMillis(200), 1024)) {
            client.connect("127.0.0.1", server.getPort(), "tester", "secret");

            ExecResult timedOut = client.exec("block");
            ExecResult next = client.exec("ok");

            assertThat(timedOut.timedOut()).isTrue();
            assertThat(timedOut.cancelled()).isFalse();
            assertThat(timedOut.exitCode()).isEqualTo(-1);
            assertThat(client.isConnected()).isTrue();
            assertThat(next.isSuccess()).isTrue();
            assertThat(next.stdout()).isEqualTo("ready");
        }
    }

    @Test
    void 真实Channel输出超过预算会截断但命令仍正常收尾() throws Exception {
        try (SshClient client = new SshClient(
                Duration.ofSeconds(2), Duration.ofSeconds(2), 32)) {
            client.connect("127.0.0.1", server.getPort(), "tester", "secret");

            ExecResult result = client.exec("large");

            assertThat(result.exitCode()).isZero();
            assertThat(result.truncated()).isTrue();
            assertThat(result.stdout().getBytes(StandardCharsets.UTF_8)).hasSize(32);
        }
    }

    @Test
    void 主动取消会关闭真实Channel并保留可复用Session() throws Exception {
        try (SshClient client = new SshClient(
                Duration.ofSeconds(2), Duration.ofSeconds(30), 1024)) {
            client.connect("127.0.0.1", server.getPort(), "tester", "secret");
            CompletableFuture<ExecResult> running =
                    CompletableFuture.supplyAsync(() -> execUnchecked(client, "block"));

            awaitActiveCommand(client);
            assertThat(client.cancelActiveCommand()).isTrue();
            ExecResult cancelled = running.get(3, TimeUnit.SECONDS);
            ExecResult next = client.exec("ok");

            assertThat(cancelled.cancelled()).isTrue();
            assertThat(cancelled.timedOut()).isFalse();
            assertThat(next.isSuccess()).isTrue();
            assertThat(next.stdout()).isEqualTo("ready");
        }
    }

    @Test
    void 严格模式拒绝knownHosts中不存在的主机() {
        SshClient client = new SshClient(
                Duration.ofSeconds(2), Duration.ofSeconds(2), 1024,
                true, tempDir.resolve("known_hosts"));
        try (client) {
            org.assertj.core.api.Assertions.assertThatThrownBy(() ->
                    client.connect(
                            "127.0.0.1", server.getPort(), "tester", "secret"))
                    .isInstanceOf(com.jcraft.jsch.JSchException.class)
                    .hasMessageContaining("reject HostKey");
        }
    }

    @Test
    void 未安装Agent连接器时明确拒绝而不是降级认证() {
        try (SshClient client = new SshClient()) {
            org.assertj.core.api.Assertions.assertThatThrownBy(() ->
                    client.connect(
                            "127.0.0.1", server.getPort(), "tester",
                            new SshAuth.Agent()))
                    .isInstanceOf(UnsupportedOperationException.class)
                    .hasMessageContaining("SSH Agent");
        }
    }

    private void awaitActiveCommand(SshClient client) throws InterruptedException {
        // 等待客户端登记 Channel；最多 1 秒，避免依赖固定长 sleep。
        for (int i = 0; i < 100; i++) {
            if (client.hasActiveCommand()) {
                return;
            }
            Thread.sleep(10);
        }
        throw new IllegalStateException("测试 SSH Session 未建立");
    }

    private ExecResult execUnchecked(SshClient client, String command) {
        try {
            return client.exec(command);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static final class TestCommand implements Command, Runnable {
        private final String command;
        private OutputStream stdout;
        private ExitCallback exitCallback;
        private Thread thread;

        private TestCommand(String command) {
            this.command = command;
        }

        @Override
        public void setInputStream(InputStream inputStream) {
        }

        @Override
        public void setOutputStream(OutputStream outputStream) {
            this.stdout = outputStream;
        }

        @Override
        public void setErrorStream(OutputStream errorStream) {
        }

        @Override
        public void setExitCallback(ExitCallback exitCallback) {
            this.exitCallback = exitCallback;
        }

        @Override
        public void start(ChannelSession channel, Environment environment) {
            thread = new Thread(this, "test-sshd-command");
            thread.start();
        }

        @Override
        public void destroy(ChannelSession channel) {
            if (thread != null) {
                thread.interrupt();
            }
        }

        @Override
        public void run() {
            try {
                if ("block".equals(command)) {
                    Thread.sleep(30_000);
                } else if ("large".equals(command)) {
                    stdout.write("x".repeat(2048).getBytes(StandardCharsets.UTF_8));
                    stdout.flush();
                } else {
                    stdout.write("ready".getBytes(StandardCharsets.UTF_8));
                    stdout.flush();
                }
                exitCallback.onExit(0);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } catch (IOException e) {
                exitCallback.onExit(1, e.getMessage());
            }
        }
    }
}
