package com.lowenssh.agent.guard;

import java.util.List;

/** ASK 审批所需的完整 Tool Call 上下文。 */
public record ConfirmationRequest(
        String toolCallId,
        String toolName,
        String argumentsJson,
        String command,
        String reason,
        String riskLevel,
        List<String> matchedRules,
        String policyVersion
) {
    public ConfirmationRequest(
            String toolCallId,
            String toolName,
            String argumentsJson,
            String command,
            String reason) {
        this(toolCallId, toolName, argumentsJson, command, reason,
                "MEDIUM", List.of(), "v1");
    }
}
