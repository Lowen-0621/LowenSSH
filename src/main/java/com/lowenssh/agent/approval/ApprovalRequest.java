package com.lowenssh.agent.approval;

import java.time.Duration;
import java.util.List;

/** Agent 在 Risk Check 后创建持久化审批所需的数据。 */
public record ApprovalRequest(
        String taskId,
        String stepId,
        String riskLevel,
        String reason,
        List<String> matchedRules,
        String policyVersion,
        Duration timeout
) {
}
