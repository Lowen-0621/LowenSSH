package com.lowenssh.agent.task;

/** Agent 工作流阶段。 */
public enum TaskPhase {
    PLAN,
    RISK_CHECK,
    APPROVE,
    EXECUTE,
    VERIFY,
    SUMMARY
}
