package com.lowenssh.agent.guard.policy;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/** 合并全部规则，最严格决定获胜；默认不在只读白名单的未知命令进入 ASK。 */
@Component
public class CommandPolicyEngine {

    private final List<CommandPolicy> policies;
    private final String policyVersion;

    public CommandPolicyEngine(
            List<CommandPolicy> policies,
            @Value("${xwssh.security.policy-version:v1}") String policyVersion) {
        this.policies = List.copyOf(policies);
        this.policyVersion = policyVersion;
    }

    public PolicyResult evaluate(CommandContext context) {
        List<PolicyMatch> matches = policies.stream()
                .map(policy -> policy.evaluate(context))
                .flatMap(java.util.Optional::stream)
                .toList();
        PolicyMatch winner = matches.stream()
                .min(java.util.Comparator
                        .comparing((PolicyMatch match) -> match.decision().ordinal())
                        .thenComparing(match -> -match.riskLevel().ordinal()))
                .orElse(new PolicyMatch(
                        PolicyDecision.ASK, RiskLevel.MEDIUM,
                        "命令不在只读白名单，需要人工确认", "ask.unknown_command"));
        List<String> ruleIds = new ArrayList<>();
        for (PolicyMatch match : matches) {
            ruleIds.add(match.ruleId());
        }
        if (ruleIds.isEmpty()) {
            ruleIds.add(winner.ruleId());
        }
        return new PolicyResult(
                winner.decision(), winner.riskLevel(), winner.reason(),
                ruleIds, policyVersion);
    }
}
