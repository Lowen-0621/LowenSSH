package com.lowenssh.agent.task;

import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * 数据库级执行预算。计数不放在 AgentService 的局部变量里，
 * 因为重试、恢复和进程重启后仍必须沿用已消耗的额度。
 */
@Service
public class TaskExecutionBudgetService {

    private final AgentTaskMapper taskMapper;
    private final int maxToolCalls;
    private final int maxConsecutiveFailures;

    public TaskExecutionBudgetService(
            AgentTaskMapper taskMapper,
            @Value("${xwssh.agent.max-tool-calls:30}") int maxToolCalls,
            @Value("${xwssh.agent.max-consecutive-failures:3}") int maxConsecutiveFailures) {
        if (maxToolCalls <= 0 || maxConsecutiveFailures <= 0) {
            throw new IllegalArgumentException("Agent 执行上限必须大于 0");
        }
        this.taskMapper = taskMapper;
        this.maxToolCalls = maxToolCalls;
        this.maxConsecutiveFailures = maxConsecutiveFailures;
    }

    /** 在实际工具执行前原子占用一次额度，避免并发或重启绕过上限。 */
    @Transactional
    public BudgetSnapshot acquireToolCall(String taskId) {
        AgentTaskEntity task = lockActiveTask(taskId);
        int calls = task.getToolCalls() == null ? 0 : task.getToolCalls();
        if (calls >= maxToolCalls) {
            throw new TaskLimitExceededException(
                    "MAX_TOOL_CALLS", "工具调用次数已达到上限 " + maxToolCalls);
        }
        if (taskMapper.incrementToolCalls(taskId, task.getVersion()) != 1) {
            throw new IllegalStateException("工具调用计数并发更新失败: " + taskId);
        }
        AgentTaskEntity updated = taskMapper.selectById(taskId);
        return snapshot(updated);
    }

    /** 成功会清零连续失败；失败只累计连续次数，不影响总工具调用次数。 */
    @Transactional(noRollbackFor = TaskLimitExceededException.class)
    public BudgetSnapshot recordToolResult(String taskId, boolean success) {
        AgentTaskEntity task = lockActiveTask(taskId);
        int current = task.getConsecutiveFailures() == null
                ? 0 : task.getConsecutiveFailures();
        int failures = success ? 0 : current + 1;
        if (taskMapper.updateConsecutiveFailures(
                taskId, failures, task.getVersion()) != 1) {
            throw new IllegalStateException("连续失败计数并发更新失败: " + taskId);
        }
        if (failures >= maxConsecutiveFailures) {
            throw new TaskLimitExceededException(
                    "MAX_CONSECUTIVE_FAILURES",
                    "连续工具失败次数已达到上限 " + maxConsecutiveFailures);
        }
        return snapshot(taskMapper.selectById(taskId));
    }

    private AgentTaskEntity lockActiveTask(String taskId) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        TaskStatus status = TaskStatus.valueOf(task.getStatus());
        if (status.isTerminal() || status == TaskStatus.CANCELLING
                || Boolean.TRUE.equals(task.getCancelRequested())) {
            throw new TaskLimitExceededException(
                    "TASK_NOT_EXECUTABLE", "任务已结束或正在取消，不能继续执行工具");
        }
        if (task.getDeadlineAt() != null
                && !LocalDateTime.now().isBefore(task.getDeadlineAt())) {
            throw new TaskLimitExceededException(
                    "TASK_DEADLINE_EXCEEDED", "任务已超过整体截止时间");
        }
        return task;
    }

    private BudgetSnapshot snapshot(AgentTaskEntity task) {
        return new BudgetSnapshot(
                task.getToolCalls(),
                maxToolCalls,
                task.getConsecutiveFailures(),
                maxConsecutiveFailures);
    }

    public record BudgetSnapshot(
            int toolCalls,
            int maxToolCalls,
            int consecutiveFailures,
            int maxConsecutiveFailures
    ) {
    }
}
