package com.lowenssh.ssh;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class SshClientOutputLimitTest {

    @Test
    void stdout和stderr共用总字节上限且超限后标记截断() throws Exception {
        SshClient.OutputBudget budget = new SshClient.OutputBudget(8);
        SshClient.BoundedOutputStream stdout = new SshClient.BoundedOutputStream(budget);
        SshClient.BoundedOutputStream stderr = new SshClient.BoundedOutputStream(budget);

        stdout.write("12345".getBytes(StandardCharsets.UTF_8));
        stderr.write("abcdef".getBytes(StandardCharsets.UTF_8));

        assertThat(stdout.asString()).isEqualTo("12345");
        assertThat(stderr.asString()).isEqualTo("abc");
        assertThat(budget.truncated()).isTrue();
    }

    @Test
    void 超时和取消结果不能因退出码零被误判成功() {
        assertThat(new ExecResult("", "", 0).isSuccess()).isTrue();
        assertThat(new ExecResult("", "", 0, true, false, false).isSuccess()).isFalse();
        assertThat(new ExecResult("", "", 0, false, true, false).isSuccess()).isFalse();
    }
}
