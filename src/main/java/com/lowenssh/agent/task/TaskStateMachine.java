package com.lowenssh.agent.task;

import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

/**
 * 任务状态机的纯函数部分。
 *
 * 数据库更新前必须先经过这里，避免 Controller、审批服务和恢复任务各自写出不同迁移规则。
 */
public final class TaskStateMachine {

    private static final Map<TaskStatus, Set<TaskStatus>> TRANSITIONS = transitions();

    private TaskStateMachine() {
    }

    public static boolean canTransition(TaskStatus from, TaskStatus to) {
        if (from == to) {
            return true; // 重复请求保持幂等
        }
        if (from.isTerminal()) {
            return false;
        }
        return TRANSITIONS.getOrDefault(from, Set.of()).contains(to);
    }

    public static void requireTransition(TaskStatus from, TaskStatus to) {
        if (!canTransition(from, to)) {
            throw new IllegalTaskTransitionException(from, to);
        }
    }

    private static Map<TaskStatus, Set<TaskStatus>> transitions() {
        Map<TaskStatus, Set<TaskStatus>> map = new EnumMap<>(TaskStatus.class);
        map.put(TaskStatus.CREATED, EnumSet.of(
                TaskStatus.PLANNING, TaskStatus.CANCELLING, TaskStatus.CANCELLED,
                TaskStatus.TIMED_OUT, TaskStatus.FAILED));
        map.put(TaskStatus.PLANNING, EnumSet.of(
                TaskStatus.RISK_CHECKING, TaskStatus.SUMMARIZING,
                TaskStatus.CANCELLING, TaskStatus.TIMED_OUT, TaskStatus.FAILED));
        map.put(TaskStatus.RISK_CHECKING, EnumSet.of(
                TaskStatus.WAITING_APPROVAL, TaskStatus.EXECUTING, TaskStatus.SUMMARIZING,
                TaskStatus.CANCELLING, TaskStatus.TIMED_OUT, TaskStatus.FAILED));
        map.put(TaskStatus.WAITING_APPROVAL, EnumSet.of(
                TaskStatus.RISK_CHECKING, TaskStatus.EXECUTING, TaskStatus.SUMMARIZING,
                TaskStatus.CANCELLING, TaskStatus.TIMED_OUT, TaskStatus.FAILED));
        map.put(TaskStatus.EXECUTING, EnumSet.of(
                TaskStatus.RISK_CHECKING, TaskStatus.VERIFYING, TaskStatus.SUMMARIZING,
                TaskStatus.CANCELLING, TaskStatus.TIMED_OUT, TaskStatus.FAILED,
                TaskStatus.NEEDS_REVIEW));
        map.put(TaskStatus.VERIFYING, EnumSet.of(
                TaskStatus.RISK_CHECKING, TaskStatus.SUMMARIZING,
                TaskStatus.CANCELLING, TaskStatus.TIMED_OUT, TaskStatus.FAILED));
        map.put(TaskStatus.SUMMARIZING, EnumSet.of(
                TaskStatus.SUCCEEDED, TaskStatus.FAILED,
                TaskStatus.CANCELLING, TaskStatus.TIMED_OUT));
        map.put(TaskStatus.CANCELLING, EnumSet.of(
                TaskStatus.CANCELLED, TaskStatus.NEEDS_REVIEW));
        return Map.copyOf(map);
    }
}
