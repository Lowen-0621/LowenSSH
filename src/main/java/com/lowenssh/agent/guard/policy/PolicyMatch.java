package com.lowenssh.agent.guard.policy;

/** 单条规则命中结果，由策略引擎合并为最终 PolicyResult。 */
public record PolicyMatch(
        PolicyDecision decision,
        RiskLevel riskLevel,
        String reason,
        String ruleId
) {
}
