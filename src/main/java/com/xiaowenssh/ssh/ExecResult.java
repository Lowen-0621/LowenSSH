package com.xiaowenssh.ssh;

/**
 * 命令执行结果 —— stdout / stderr / exitCode 三件套
 * 用 record（Java 17）：不可变、自带 equals/toString，正好装这种纯数据
 */
public record ExecResult(String stdout, String stderr, int exitCode) {

    /** exitCode 为 0 视为成功 */
    public boolean isSuccess() {
        return exitCode == 0;
    }
}
