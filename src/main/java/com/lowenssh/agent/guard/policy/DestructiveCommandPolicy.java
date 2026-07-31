package com.lowenssh.agent.guard.policy;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;

/** 绝对禁止的毁灭性命令。 */
@Component
public class DestructiveCommandPolicy implements CommandPolicy {

    private static final List<Pattern> RULES = List.of(
            Pattern.compile("\\brm\\s+(-\\w*\\s+)*-\\w*[rf]", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\b(mkfs|shutdown|reboot|halt)\\b", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\bdd\\s+.*\\bof\\s*=", Pattern.CASE_INSENSITIVE),
            Pattern.compile(">\\s*/dev/(sd|nvme|vd)", Pattern.CASE_INSENSITIVE),
            Pattern.compile(":\\(\\)\\s*\\{.*\\}"),
            Pattern.compile("\\bmv\\s+.*\\s+/dev/null", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\bfind\\b.*(-delete|-exec\\s+rm)", Pattern.CASE_INSENSITIVE)
    );

    @Override
    public Optional<PolicyMatch> evaluate(CommandContext context) {
        String command = safe(context.command());
        for (Pattern pattern : RULES) {
            var matcher = pattern.matcher(command);
            if (matcher.find()) {
                return Optional.of(new PolicyMatch(
                        PolicyDecision.DENY, RiskLevel.CRITICAL,
                        "命中绝对禁止的毁灭性命令: " + matcher.group(),
                        "deny.destructive"));
            }
        }
        return Optional.empty();
    }

    private String safe(String value) {
        return value == null ? "" : value;
    }
}
