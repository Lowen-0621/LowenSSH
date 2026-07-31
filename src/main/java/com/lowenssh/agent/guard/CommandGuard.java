package com.lowenssh.agent.guard;

import com.lowenssh.agent.guard.policy.CommandContext;
import com.lowenssh.agent.guard.policy.CommandPolicyEngine;
import com.lowenssh.agent.guard.policy.CommandShapePolicy;
import com.lowenssh.agent.guard.policy.DestructiveCommandPolicy;
import com.lowenssh.agent.guard.policy.IndirectExecutionPolicy;
import com.lowenssh.agent.guard.policy.PolicyResult;
import com.lowenssh.agent.guard.policy.PrivilegeEscalationPolicy;
import com.lowenssh.agent.guard.policy.ReadOnlyCommandPolicy;
import com.lowenssh.agent.guard.policy.RiskLevel;
import com.lowenssh.agent.guard.policy.WriteOperationPolicy;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 兼容门面：旧调用仍拿 DENY/ASK/ALLOW，内部已经升级为可组合规则链。
 *
 * 规则链只是纵深防御的一层，不能证明任意 Shell 绝对安全；生产仍需最小权限账号、
 * sudo 白名单、主机隔离、known_hosts 和人工审批。
 */
@Component
public class CommandGuard {

    public enum Decision {
        DENY,
        ASK,
        ALLOW
    }

    public record Verdict(
            Decision decision,
            String reason,
            RiskLevel riskLevel,
            List<String> matchedRules,
            String policyVersion
    ) {
        public Verdict {
            matchedRules = matchedRules == null ? List.of() : List.copyOf(matchedRules);
        }

        /** 兼容既有单测和扩展点。 */
        public Verdict(Decision decision, String reason) {
            this(decision, reason, defaultRisk(decision), List.of(), "v1");
        }

        private static RiskLevel defaultRisk(Decision decision) {
            return switch (decision) {
                case ALLOW -> RiskLevel.LOW;
                case ASK -> RiskLevel.MEDIUM;
                case DENY -> RiskLevel.CRITICAL;
            };
        }
    }

    private final CommandPolicyEngine engine;

    /** Spring 使用配置化策略链。 */
    @Autowired
    public CommandGuard(CommandPolicyEngine engine) {
        this.engine = engine;
    }

    /** 兼容不启动 Spring 的纯单元测试。 */
    public CommandGuard() {
        this(new CommandPolicyEngine(List.of(
                new DestructiveCommandPolicy(),
                new IndirectExecutionPolicy(),
                new PrivilegeEscalationPolicy(),
                new WriteOperationPolicy(),
                new CommandShapePolicy(4096),
                new ReadOnlyCommandPolicy()
        ), "v1"));
    }

    public Verdict evaluate(String command) {
        return evaluate(CommandContext.of(command));
    }

    public Verdict evaluate(CommandContext context) {
        PolicyResult result = engine.evaluate(context);
        return new Verdict(
                Decision.valueOf(result.decision().name()),
                result.reason(),
                result.riskLevel(),
                result.matchedRules(),
                result.policyVersion());
    }
}
