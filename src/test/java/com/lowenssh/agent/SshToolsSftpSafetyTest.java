package com.lowenssh.agent;

import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.persistence.AuditService;
import com.lowenssh.ssh.SshClient;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SshToolsSftpSafetyTest {

    @Test
    void 恶意文件路径直接交给Sftp绝不拼成Shell命令() throws Exception {
        SshClient ssh = mock(SshClient.class);
        AuditService audit = mock(AuditService.class);
        SshTools tools = new SshTools(ssh, 1L, audit, new CommandGuard());
        String path = "/tmp/a'; rm -rf /; echo '";
        when(ssh.readTextFile(path)).thenReturn("safe-content");

        String result = tools.readRemoteFile(path);

        assertThat(result).isEqualTo("safe-content");
        verify(ssh).readTextFile(path);
        verify(ssh, never()).exec(org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void Tail行数和路径也走Sftp协议() throws Exception {
        SshClient ssh = mock(SshClient.class);
        AuditService audit = mock(AuditService.class);
        SshTools tools = new SshTools(ssh, 1L, audit, new CommandGuard());
        String path = "/var/log/a b.log";
        when(ssh.tailTextFile(path, 100)).thenReturn("last-line");

        assertThat(tools.tailLog(path, 100)).isEqualTo("last-line");
        verify(ssh).tailTextFile(path, 100);
        verify(ssh, never()).exec(org.mockito.ArgumentMatchers.anyString());
    }
}
