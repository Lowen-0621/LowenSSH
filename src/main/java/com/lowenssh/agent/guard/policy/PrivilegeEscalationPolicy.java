package com.lowenssh.agent.guard.policy;

import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.regex.Pattern;

/** sudo/su 提权必须人工审批。 */
@Component
public class PrivilegeEscalationPolicy implements CommandPolicy {

    private static final Pattern RULE =
            Pattern.compile("(^|[;&|]\\s*)\\b(sudo|su)\\b", Pattern.CASE_INSENSITIVE);

    @Override
    public Optional<PolicyMatch> evaluate(CommandContext context) {
        String command = context.command() == null ? "" : context.command();
        if (!RULE.matcher(command).find()) {
            return Optional.empty();
        }
        return Optional.of(new PolicyMatch(
                PolicyDecision.ASK, RiskLevel.HIGH,
                "命令包含权限提升", "ask.privilege_escalation"));
    }
}
