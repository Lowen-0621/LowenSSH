package com.lowenssh.agent.guard.policy;

import org.springframework.stereotype.Component;

import java.util.Optional;
import java.util.regex.Pattern;

/** 文件写入、服务变更、进程终止和权限变更需要审批。 */
@Component
public class WriteOperationPolicy implements CommandPolicy {

    private static final Pattern SIDE_EFFECT = Pattern.compile(
            "\\b(rm|kill|pkill|killall|chmod|chown|truncate|mv|cp|mkdir|touch)\\b"
                    + "|\\bsystemctl\\s+(start|stop|restart|reload|enable|disable)\\b"
                    + "|\\bservice\\s+\\S+\\s+(start|stop|restart|reload)\\b"
                    + "|\\b(apt|apt-get|yum|dnf)\\s+(install|remove|purge|upgrade)\\b"
                    + "|\\bsed\\b.*\\s-i(?:\\s|$)"
                    + "|\\bcurl\\b.*(--request\\s+(POST|PUT|PATCH|DELETE)|-X\\s*(POST|PUT|PATCH|DELETE)"
                    + "|--data(?:-\\S+)?|-d\\s|-T\\s|--upload-file)"
                    + "|(^|[^>])>{1,2}(?!\\s*/dev/null)",
            Pattern.CASE_INSENSITIVE | Pattern.DOTALL);

    private static final Pattern SENSITIVE_PATH = Pattern.compile(
            "(/etc/|/var/lib/(mysql|postgres)|/root/|\\.ssh/|/boot/)",
            Pattern.CASE_INSENSITIVE);

    @Override
    public Optional<PolicyMatch> evaluate(CommandContext context) {
        String command = context.command() == null ? "" : context.command();
        if (!SIDE_EFFECT.matcher(command).find()) {
            return Optional.empty();
        }
        boolean sensitive = SENSITIVE_PATH.matcher(command).find();
        return Optional.of(new PolicyMatch(
                PolicyDecision.ASK,
                sensitive ? RiskLevel.HIGH : RiskLevel.MEDIUM,
                sensitive ? "命令将修改敏感路径或关键服务数据" : "命令包含有副作用的操作",
                sensitive ? "ask.sensitive_write" : "ask.side_effect"));
    }
}
