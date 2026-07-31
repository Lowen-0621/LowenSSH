package com.lowenssh.agent.task;

/** 幂等键作用域；不同操作可以安全复用相同的文本 Key。 */
public enum IdempotencyScope {
    CREATE_TASK,
    DECIDE_APPROVAL,
    CANCEL_TASK
}
