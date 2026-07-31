package com.lowenssh.agent.guard.policy;

import java.util.Optional;

/** 一条可组合命令策略；没有命中时返回 empty。 */
public interface CommandPolicy {

    Optional<PolicyMatch> evaluate(CommandContext context);
}
