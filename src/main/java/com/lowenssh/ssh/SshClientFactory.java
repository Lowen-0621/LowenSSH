package com.lowenssh.ssh;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.nio.file.Path;
import com.lowenssh.observability.AgentMetrics;

/** 统一应用配置创建 SSH 客户端，避免不同入口使用不同的超时和输出上限。 */
@Component
public class SshClientFactory {

    private final Duration connectTimeout;
    private final Duration commandTimeout;
    private final int maxOutputBytes;
    private final boolean strictHostKeyChecking;
    private final Path knownHostsPath;
    private final SshExecutionObserver executionObserver;

    @Autowired
    public SshClientFactory(
            @Value("${xwssh.ssh.connect-timeout:10s}") Duration connectTimeout,
            @Value("${xwssh.ssh.command-timeout:30s}") Duration commandTimeout,
            @Value("${xwssh.ssh.max-output-bytes:1048576}") int maxOutputBytes,
            @Value("${xwssh.ssh.strict-host-key-checking:true}") boolean strictHostKeyChecking,
            @Value("${xwssh.ssh.known-hosts-path:${user.home}/.lowenssh/known_hosts}")
            String knownHostsPath,
            AgentMetrics metrics) {
        this.connectTimeout = connectTimeout;
        this.commandTimeout = commandTimeout;
        this.maxOutputBytes = maxOutputBytes;
        this.strictHostKeyChecking = strictHostKeyChecking;
        this.knownHostsPath = Path.of(knownHostsPath);
        this.executionObserver = metrics::ssh;
    }

    /** 单元测试兼容构造器。 */
    public SshClientFactory(
            Duration connectTimeout, Duration commandTimeout, int maxOutputBytes) {
        this.connectTimeout = connectTimeout;
        this.commandTimeout = commandTimeout;
        this.maxOutputBytes = maxOutputBytes;
        this.strictHostKeyChecking = false;
        this.knownHostsPath = Path.of(
                System.getProperty("java.io.tmpdir"), "lowenssh-test-known-hosts");
        this.executionObserver = SshExecutionObserver.NOOP;
    }

    public SshClient create() {
        return new SshClient(
                connectTimeout, commandTimeout, maxOutputBytes,
                strictHostKeyChecking, knownHostsPath, executionObserver);
    }
}
