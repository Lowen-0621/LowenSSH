package com.lowenssh.agent.task;

/** 非法任务状态迁移。 */
public class IllegalTaskTransitionException extends RuntimeException {

    private final TaskStatus from;
    private final TaskStatus to;

    public IllegalTaskTransitionException(TaskStatus from, TaskStatus to) {
        super("不允许任务状态从 %s 迁移到 %s".formatted(from, to));
        this.from = from;
        this.to = to;
    }

    public TaskStatus from() {
        return from;
    }

    public TaskStatus to() {
        return to;
    }
}
