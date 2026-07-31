package com.lowenssh.agent.task;

/** 工作线程观察到持久化取消请求后退出 Loop。 */
public class TaskCancelledException extends RuntimeException {

    public TaskCancelledException() {
        super("任务已请求取消");
    }
}
