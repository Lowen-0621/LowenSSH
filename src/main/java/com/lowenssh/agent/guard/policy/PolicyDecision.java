package com.lowenssh.agent.guard.policy;

/** 策略链统一决定，严重度顺序为 DENY > ASK > ALLOW。 */
public enum PolicyDecision {
    DENY,
    ASK,
    ALLOW
}
