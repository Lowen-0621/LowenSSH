package com.lowenssh.agent.task;

/**
 * Step 已经开始或完成，无法证明远端副作用未发生。
 * 恢复时必须转人工复核，绝不能自动重放。
 */
public class DuplicateToolExecutionException extends RuntimeException {

    public DuplicateToolExecutionException(String stepId, String status) {
        super("Step " + stepId + " 当前为 " + status + "，拒绝重复执行");
    }
}
