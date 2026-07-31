package com.lowenssh.agent.approval;

/** CompletableFuture 唤醒 Agent 时传递的审批结果。 */
public enum ApprovalDecision {
    APPROVED,
    REJECTED,
    EXPIRED,
    CANCELLED;

    public static ApprovalDecision from(ApprovalStatus status) {
        if (status == ApprovalStatus.PENDING) {
            throw new IllegalArgumentException("PENDING 还不是审批决定");
        }
        return valueOf(status.name());
    }
}
