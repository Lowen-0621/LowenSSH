package com.lowenssh.agent.guard.policy;

import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.Set;

/** 明确只读命令白名单；复合管道要求每一段首命令都在白名单。 */
@Component
public class ReadOnlyCommandPolicy implements CommandPolicy {

    private static final Set<String> READ_ONLY = Set.of(
            "ls", "cd", "echo", "pwd", "whoami", "id", "uname", "hostname", "date",
            "df", "du", "free", "uptime", "ps", "pgrep", "top",
            "cat", "head", "tail", "grep", "egrep", "fgrep", "awk", "sed",
            "find", "stat", "file", "wc", "sort", "uniq", "cut", "tr",
            "ss", "netstat", "lsof", "ip", "ping", "curl", "dig", "nslookup",
            "systemctl", "journalctl", "dmesg", "env", "printenv", "which",
            "readlink", "realpath", "sha256sum", "md5sum", "test"
    );

    @Override
    public Optional<PolicyMatch> evaluate(CommandContext context) {
        String command = context.command() == null ? "" : context.command().strip();
        if (command.isEmpty()) {
            return Optional.of(new PolicyMatch(
                    PolicyDecision.ALLOW, RiskLevel.LOW,
                    "空命令不会产生副作用", "allow.empty"));
        }
        String[] segments = command.split("&&|\\|\\||[|;\\n]");
        for (String segment : segments) {
            String normalized = segment.strip()
                    .replaceFirst("^(command|builtin)\\s+", "");
            String first = normalized.split("\\s+", 2)[0];
            if (!READ_ONLY.contains(first)) {
                return Optional.empty();
            }
        }
        return Optional.of(new PolicyMatch(
                PolicyDecision.ALLOW, RiskLevel.LOW,
                "全部命令段均在只读白名单", "allow.read_only"));
    }
}
