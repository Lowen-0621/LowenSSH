package com.lowenssh.agent.guard;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.regex.Pattern;

/**
 * 命令门禁 —— deny / ask / allow 三态判定。Agent 安全的硬边界。
 *
 * 设计原则（抄 Claude Code 并落地）：
 *  1. 安全检查是独立代码路径，不写进工具方法、不靠模型自觉。模型越狱也绕不过这层。
 *  2. 三态评估顺序固定：先查 deny（命中即拒，deny 永远赢）→ 再看是否需 ask → 默认 allow。
 *  3. 只看"实际要执行的命令"，不看模型的话术，防花言巧语骗过门禁。
 *  4. 复合命令（&& | ; 串起来的）拆开逐段查，防"ls && rm -rf /"整条被当成一段漏过。
 *
 * 判定结果是纯函数，无副作用，方便单测。
 */
@Component
public class CommandGuard {

    /** 三态 */
    public enum Decision { DENY, ASK, ALLOW }

    /** 判定结果：状态 + 原因（原因用于回灌给模型 / 展示给用户） */
    public record Verdict(Decision decision, String reason) {
    }

    /**
     * deny 名单：不可逆的毁灭性操作，直接拒绝，不给确认机会。
     * 用正则匹配，\b 保证匹配的是独立命令词而非子串（如 dd 不误伤 add）。
     */
    private static final List<Pattern> DENY = List.of(
            Pattern.compile("\\brm\\s+(-\\w*\\s+)*-\\w*[rf]"),  // rm -rf / rm -fr 等带 r/f 组合
            Pattern.compile("\\bmkfs\\b"),                        // 格式化文件系统
            Pattern.compile("\\bdd\\b"),                          // 块设备读写，易毁盘
            Pattern.compile("\\bshutdown\\b"),                    // 关机
            Pattern.compile("\\breboot\\b"),                      // 重启
            Pattern.compile("\\bhalt\\b"),                        // 停机
            Pattern.compile(">\\s*/dev/sd"),                      // 直接写裸盘
            Pattern.compile(":\\(\\)\\s*\\{.*\\}"),               // fork 炸弹 :(){ :|:& };:
            Pattern.compile("\\bmv\\s+.*\\s+/dev/null"),          // mv 到 /dev/null 销毁数据
            // 真机联调发现：find 是 rm -rf 的等价绕过——模型被拦 rm -rf 后改用 find 删
            Pattern.compile("\\bfind\\b.*-delete"),               // find ... -delete 批量删除
            Pattern.compile("\\bfind\\b.*-exec\\s+rm")            // find ... -exec rm 批量删除
    );

    /**
     * ask 名单：有副作用但未必致命，执行前问一句。
     */
    private static final List<Pattern> ASK = List.of(
            Pattern.compile("\\brm\\b"),                          // 普通 rm（非 -rf，已被 deny 漏下来的）
            Pattern.compile("\\bkill\\b"),                        // 杀进程
            Pattern.compile("\\bsystemctl\\s+(stop|restart|disable)"), // 停/重启/禁用服务
            Pattern.compile("\\bservice\\s+\\S+\\s+(stop|restart)"),
            Pattern.compile("\\b(chmod|chown)\\b"),               // 改权限/属主
            Pattern.compile("\\b(apt|apt-get|yum|dnf)\\s+(install|remove|purge)"), // 装/卸软件
            Pattern.compile("\\btruncate\\b"),                    // 清空文件
            Pattern.compile(">\\s*/")                             // 重定向覆盖写到绝对路径文件
    );

    /**
     * 判定一条命令。复合命令会被拆段，取最严结果（任一段 deny 则整条 deny）。
     */
    public Verdict evaluate(String command) {
        if (command == null || command.isBlank()) {
            return new Verdict(Decision.ALLOW, "空命令");
        }

        Decision worst = Decision.ALLOW;
        String worstReason = "";

        // 复合命令拆段：&& || | ; 都是命令分隔符
        for (String seg : splitSegments(command)) {
            String s = seg.trim();
            if (s.isEmpty()) continue;

            Verdict v = evaluateSingle(s);
            // 取最严：DENY > ASK > ALLOW（enum ordinal 越小越严）
            if (v.decision().ordinal() < worst.ordinal()) {
                worst = v.decision();
                worstReason = v.reason();
            }
            // 已经最严了，提前结束
            if (worst == Decision.DENY) break;
        }

        if (worst == Decision.ALLOW) {
            return new Verdict(Decision.ALLOW, "只读/安全命令");
        }
        return new Verdict(worst, worstReason);
    }

    /** 单段命令判定：先 deny 再 ask 后 allow */
    private Verdict evaluateSingle(String seg) {
        for (Pattern p : DENY) {
            if (p.matcher(seg).find()) {
                return new Verdict(Decision.DENY, "命中危险命令拦截规则: " + describe(p, seg));
            }
        }
        for (Pattern p : ASK) {
            if (p.matcher(seg).find()) {
                return new Verdict(Decision.ASK, "涉及有副作用的操作: " + describe(p, seg));
            }
        }
        return new Verdict(Decision.ALLOW, "");
    }

    /** 按命令分隔符拆段，分隔符本身丢弃 */
    private List<String> splitSegments(String command) {
        // 用正则一次切掉 && || | ; 以及换行
        return List.of(command.split("&&|\\|\\||[|;\\n]"));
    }

    /** 给出命中片段，便于用户/模型理解为什么被拦 */
    private String describe(Pattern p, String seg) {
        var m = p.matcher(seg);
        if (m.find()) {
            return "'" + m.group() + "'";
        }
        return p.pattern();
    }
}
