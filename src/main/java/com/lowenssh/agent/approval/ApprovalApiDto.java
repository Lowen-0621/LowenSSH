package com.lowenssh.agent.approval;

import java.time.LocalDateTime;
import java.util.List;

/** 审批 API 与 SSE 事件使用的稳定数据结构。 */
public final class ApprovalApiDto {

    private ApprovalApiDto() {
    }

    public record DecideApprovalRequest(boolean approved) {
    }

    public record ApprovalView(
            String approvalId,
            String taskId,
            String stepId,
            String toolCallId,
            String actionDigest,
            String status,
            String riskLevel,
            String reason,
            List<String> matchedRules,
            LocalDateTime expiresAt,
            LocalDateTime decidedAt
    ) {
    }
}
