package com.lowenssh.agent.approval;

/** 持久化审批状态。 */
public enum ApprovalStatus {
    PENDING,
    APPROVED,
    REJECTED,
    EXPIRED,
    CANCELLED;

    public boolean isTerminal() {
        return this != PENDING;
    }
}
