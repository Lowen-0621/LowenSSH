package com.lowenssh.agent.guard.policy;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Optional;

/** 命令长度和复合结构控制。 */
@Component
public class CommandShapePolicy implements CommandPolicy {

    private final int maxLength;

    public CommandShapePolicy(
            @Value("${xwssh.security.max-command-length:4096}") int maxLength) {
        this.maxLength = maxLength;
    }

    @Override
    public Optional<PolicyMatch> evaluate(CommandContext context) {
        String command = context.command() == null ? "" : context.command();
        if (command.length() > maxLength) {
            return Optional.of(new PolicyMatch(
                    PolicyDecision.DENY, RiskLevel.HIGH,
                    "命令长度超过 " + maxLength + "，拒绝难以审计的超长输入",
                    "deny.command_too_long"));
        }
        if (command.matches("(?s).*(&&|\\|\\||[;|\\n]).*")) {
            return Optional.of(new PolicyMatch(
                    PolicyDecision.ALLOW, RiskLevel.LOW,
                    "复合命令已按整条命令应用全部策略",
                    "inspect.compound_command"));
        }
        return Optional.empty();
    }
}
