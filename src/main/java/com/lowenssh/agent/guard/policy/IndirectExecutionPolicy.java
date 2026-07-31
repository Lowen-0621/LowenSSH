package com.lowenssh.agent.guard.policy;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;

/** 检测 Shell 包装、编码解码、解释器和变量间接执行。 */
@Component
public class IndirectExecutionPolicy implements CommandPolicy {

    private static final List<Pattern> RULES = List.of(
            Pattern.compile("\\b(bash|sh|zsh|dash)\\s+-c\\b", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\b(python\\d*|perl|ruby|node)\\s+-[ce]\\b", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\beval\\b", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\bfind\\b.*\\s-(exec|ok)\\b",
                    Pattern.CASE_INSENSITIVE | Pattern.DOTALL),
            Pattern.compile("\\bbase64\\s+(-d|--decode)\\b.*\\|\\s*(bash|sh)\\b",
                    Pattern.CASE_INSENSITIVE | Pattern.DOTALL),
            Pattern.compile("\\$\\([^)]+\\)|`[^`]+`"),
            Pattern.compile("(^|[;\\n])\\s*[A-Za-z_][A-Za-z0-9_]*=.*[;\\n].*\\$[A-Za-z_]",
                    Pattern.DOTALL)
    );

    @Override
    public Optional<PolicyMatch> evaluate(CommandContext context) {
        String command = context.command() == null ? "" : context.command();
        return RULES.stream()
                .filter(pattern -> pattern.matcher(command).find())
                .findFirst()
                .map(pattern -> new PolicyMatch(
                        PolicyDecision.DENY, RiskLevel.CRITICAL,
                        "检测到包装器、编码或间接执行，无法可靠分析真实命令",
                        "deny.indirect_execution"));
    }
}
