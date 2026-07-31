package com.lowenssh.agent.task;

/** 持久化执行预算耗尽，编排器应停止继续调用工具并进入 Summary。 */
public class TaskLimitExceededException extends RuntimeException {

    private final String code;

    public TaskLimitExceededException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
