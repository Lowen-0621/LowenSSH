package com.lowenssh.agent.task;

import java.util.EnumSet;
import java.util.Set;

/**
 * Agent 任务状态。
 *
 * 终态一旦写入就不能回退；非终态之间的合法迁移统一由 {@link TaskStateMachine} 校验。
 */
public enum TaskStatus {
    CREATED,
    PLANNING,
    RISK_CHECKING,
    WAITING_APPROVAL,
    EXECUTING,
    VERIFYING,
    SUMMARIZING,
    CANCELLING,
    SUCCEEDED,
    FAILED,
    CANCELLED,
    TIMED_OUT,
    NEEDS_REVIEW;

    private static final Set<TaskStatus> TERMINAL = EnumSet.of(
            SUCCEEDED, FAILED, CANCELLED, TIMED_OUT, NEEDS_REVIEW
    );

    public boolean isTerminal() {
        return TERMINAL.contains(this);
    }
}
