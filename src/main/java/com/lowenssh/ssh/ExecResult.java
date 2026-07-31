package com.lowenssh.ssh;

/** 命令执行结果，同时明确正常、超时、取消和输出截断。 */
public record ExecResult(
        String stdout,
        String stderr,
        int exitCode,
        boolean timedOut,
        boolean cancelled,
        boolean truncated
) {

    /** 兼容 SFTP 和既有测试中构造的普通结果。 */
    public ExecResult(String stdout, String stderr, int exitCode) {
        this(stdout, stderr, exitCode, false, false, false);
    }

    /** 只有正常结束且 exitCode 为 0 才算成功。 */
    public boolean isSuccess() {
        return exitCode == 0 && !timedOut && !cancelled;
    }
}
