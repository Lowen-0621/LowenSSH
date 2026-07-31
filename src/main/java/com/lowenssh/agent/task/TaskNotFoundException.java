package com.lowenssh.agent.task;

/** 指定 taskId 不存在。 */
public class TaskNotFoundException extends RuntimeException {

    private final String taskId;

    public TaskNotFoundException(String taskId) {
        super("任务不存在: " + taskId);
        this.taskId = taskId;
    }

    public String taskId() {
        return taskId;
    }
}
