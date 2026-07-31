package com.lowenssh.agent.guard.policy;

import java.util.List;

/** 面向审计、审批和 SSE 的完整策略结果。 */
public record PolicyResult(
        PolicyDecision decision,
        RiskLevel riskLevel,
        String reason,
        List<String> matchedRules,
        String policyVersion
) {
    public PolicyResult {
        matchedRules = matchedRules == null ? List.of() : List.copyOf(matchedRules);
    }
}
