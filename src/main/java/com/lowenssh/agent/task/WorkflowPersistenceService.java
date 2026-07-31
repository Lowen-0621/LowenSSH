package com.lowenssh.agent.task;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentStepMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.Map;

/** Plan/Risk/Execute/Verify/Summary 各检查点的事务写入口。 */
@Service
public class WorkflowPersistenceService {

    private final AgentTaskMapper taskMapper;
    private final AgentStepMapper stepMapper;
    private final AgentStepService stepService;
    private final TaskTransitionService transitionService;
    private final TaskEventService eventService;
    private final ObjectMapper objectMapper;
    private final int maxToolCalls;
    private final int maxConsecutiveFailures;
    private final String policyVersion;

    public WorkflowPersistenceService(
            AgentTaskMapper taskMapper,
            AgentStepMapper stepMapper,
            AgentStepService stepService,
            TaskTransitionService transitionService,
            TaskEventService eventService,
            ObjectMapper objectMapper,
            @Value("${xwssh.agent.max-tool-calls:30}") int maxToolCalls,
            @Value("${xwssh.agent.max-consecutive-failures:3}") int maxConsecutiveFailures,
            @Value("${xwssh.security.policy-version:v1}") String policyVersion) {
        this.taskMapper = taskMapper;
        this.stepMapper = stepMapper;
        this.stepService = stepService;
        this.transitionService = transitionService;
        this.eventService = eventService;
        this.objectMapper = objectMapper;
        this.maxToolCalls = maxToolCalls;
        this.maxConsecutiveFailures = maxConsecutiveFailures;
        this.policyVersion = policyVersion;
    }

    @Transactional
    public void beforeModelCall(String taskId, int round) {
        AgentTaskEntity task = requireActiveTask(taskId);
        if (taskMapper.incrementModelCalls(taskId, task.getVersion()) != 1) {
            throw new IllegalStateException("模型调用计数并发更新失败: " + taskId);
        }
        eventService.append(taskId, "model_call_started", Map.of("round", round));
    }

    @Transactional
    public AgentStepEntity recordPlan(String taskId, String planJson) {
        AgentStepEntity step = stepService.createOrGet(
                taskId, "plan-1", TaskPhase.PLAN, "PLAN",
                "model_plan", planJson, policyVersion);
        AgentStepEntity locked = stepMapper.selectForUpdate(step.getStepId());
        if (!"COMPLETED".equals(locked.getStatus())) {
            int updated = stepMapper.finishNonToolStep(
                    locked.getStepId(), "COMPLETED", planJson, locked.getVersion());
            if (updated != 1) {
                throw new IllegalStateException("Plan Step 持久化失败");
            }
            eventService.append(taskId, "plan_created", Map.of(
                    "stepId", step.getStepId(),
                    "plan", parseJson(planJson)
            ));
        }
        return stepMapper.selectById(step.getStepId());
    }

    @Transactional
    public AgentStepEntity recordRisk(String taskId,
                                      String toolCallId,
                                      String toolName,
                                      String argumentsJson,
                                      CommandGuard.Verdict verdict) {
        AgentStepEntity step = stepService.createOrGet(
                taskId, toolCallId, TaskPhase.RISK_CHECK, "TOOL",
                toolName, argumentsJson, policyVersion);
        AgentStepEntity locked = stepMapper.selectForUpdate(step.getStepId());
        String riskLevel = verdict.riskLevel().name();
        String status = verdict.decision() == CommandGuard.Decision.DENY
                ? "DENIED" : "RISK_CHECKED";
        String matchedRules = toJson(verdict.matchedRules());
        if (!"WAITING_APPROVAL".equals(locked.getStatus())
                && !"READY_TO_EXECUTE".equals(locked.getStatus())) {
            int updated = stepMapper.markRiskChecked(
                    locked.getStepId(), TaskPhase.RISK_CHECK.name(), status,
                    riskLevel, policyVersion, matchedRules, locked.getVersion());
            if (updated != 1) {
                throw new IllegalStateException("Risk Check Step 持久化失败");
            }
        }
        eventService.append(taskId, "risk_checked", Map.of(
                "stepId", step.getStepId(),
                "toolCallId", toolCallId,
                "decision", verdict.decision().name(),
                "riskLevel", riskLevel,
                "reason", verdict.reason()
        ));
        return stepMapper.selectById(step.getStepId());
    }

    /**
     * 一次事务内先检查全部 Step 和工具预算，再为整批动作获取唯一执行权。
     * 任一步不满足都会整体回滚，不出现“半批已标 EXECUTING”。
     */
    @Transactional
    public void beginExecution(String taskId, List<ExecutionClaim> claims) {
        AgentTaskEntity task = requireActiveTask(taskId);
        int used = task.getToolCalls() == null ? 0 : task.getToolCalls();
        if (used + claims.size() > maxToolCalls) {
            throw new TaskLimitExceededException(
                    "MAX_TOOL_CALLS", "工具调用次数将超过上限 " + maxToolCalls);
        }
        List<ExecutionClaim> ordered = claims.stream()
                .sorted(Comparator.comparing(ExecutionClaim::stepId))
                .toList();
        for (ExecutionClaim claim : ordered) {
            AgentStepEntity step = stepMapper.selectForUpdate(claim.stepId());
            if (step == null || !taskId.equals(step.getTaskId())) {
                throw new IllegalArgumentException("执行 Step 不存在或不属于任务");
            }
            if (!"RISK_CHECKED".equals(step.getStatus())
                    && !"READY_TO_EXECUTE".equals(step.getStatus())) {
                throw new DuplicateToolExecutionException(step.getStepId(), step.getStatus());
            }
        }
        if (taskMapper.addToolCalls(taskId, claims.size(), task.getVersion()) != 1) {
            throw new IllegalStateException("工具调用预算并发更新失败: " + taskId);
        }
        for (ExecutionClaim claim : ordered) {
            AgentStepEntity step = stepMapper.selectForUpdate(claim.stepId());
            if (stepMapper.claimExecution(
                    step.getStepId(), claim.preSnapshot(), step.getVersion()) != 1) {
                throw new DuplicateToolExecutionException(step.getStepId(), step.getStatus());
            }
        }
        transitionService.transition(
                taskId, TaskStatus.EXECUTING, TaskPhase.EXECUTE, "task_executing");
    }

    @Transactional
    public FinishBatchResult finishExecution(
            String taskId, List<ExecutionOutcome> outcomes) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        int failures = task.getConsecutiveFailures() == null
                ? 0 : task.getConsecutiveFailures();
        for (ExecutionOutcome outcome : outcomes) {
            AgentStepEntity step = stepMapper.selectForUpdate(outcome.stepId());
            if (step == null || !taskId.equals(step.getTaskId())) {
                throw new IllegalArgumentException("结果 Step 不存在或不属于任务");
            }
            int updated = stepMapper.finishExecution(
                    step.getStepId(),
                    outcome.success() ? "EXECUTED" : "EXECUTION_FAILED",
                    outcome.resultSummary(), outcome.exitCode(),
                    outcome.timedOut(), outcome.truncated(), step.getVersion());
            if (updated != 1) {
                throw new DuplicateToolExecutionException(step.getStepId(), step.getStatus());
            }
            failures = outcome.success() ? 0 : failures + 1;
            eventService.append(taskId, "tool_execution_finished", Map.of(
                    "stepId", step.getStepId(),
                    "success", outcome.success(),
                    "timedOut", outcome.timedOut(),
                    "truncated", outcome.truncated()
            ));
        }
        AgentTaskEntity refreshed = taskMapper.selectForUpdate(taskId);
        if (taskMapper.updateConsecutiveFailures(
                taskId, failures, refreshed.getVersion()) != 1) {
            throw new IllegalStateException("连续失败计数更新失败: " + taskId);
        }
        AgentTaskEntity afterResults = taskMapper.selectForUpdate(taskId);
        boolean cancelling = TaskStatus.valueOf(afterResults.getStatus()) == TaskStatus.CANCELLING;
        if (!cancelling) {
            transitionService.transition(
                    taskId, TaskStatus.VERIFYING, TaskPhase.VERIFY, "task_verifying");
        }
        return new FinishBatchResult(
                failures >= maxConsecutiveFailures, failures, cancelling);
    }

    @Transactional
    public void saveVerification(String taskId,
                                 String stepId,
                                 VerificationRecord verification) {
        AgentStepEntity step = stepMapper.selectForUpdate(stepId);
        if (step == null || !taskId.equals(step.getTaskId())) {
            throw new IllegalArgumentException("验证 Step 不存在或不属于任务");
        }
        if (stepMapper.saveVerification(
                stepId, verification.plan(), verification.result(),
                verification.rollbackSuggestion(), step.getVersion()) != 1) {
            throw new IllegalStateException("验证结果持久化失败: " + stepId);
        }
        eventService.append(taskId, "step_verified", Map.of(
                "stepId", stepId,
                "status", verification.status(),
                "result", verification.result()
        ));
    }

    @Transactional
    public void continueRiskChecking(String taskId) {
        transitionService.transition(
                taskId, TaskStatus.RISK_CHECKING,
                TaskPhase.RISK_CHECK, "task_risk_checking");
    }

    @Transactional
    public void succeed(String taskId, String summary) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        TaskStatus current = TaskStatus.valueOf(task.getStatus());
        if (current.isTerminal()) {
            return;
        }
        if (current != TaskStatus.SUMMARIZING) {
            transitionService.transition(
                    taskId, TaskStatus.SUMMARIZING,
                    TaskPhase.SUMMARY, "task_summarizing");
        }
        AgentTaskEntity summarizing = taskMapper.selectForUpdate(taskId);
        TaskStateMachine.requireTransition(
                TaskStatus.valueOf(summarizing.getStatus()), TaskStatus.SUCCEEDED);
        if (taskMapper.finish(
                taskId, TaskStatus.SUCCEEDED.name(), TaskPhase.SUMMARY.name(),
                summary, null, null, summarizing.getVersion()) != 1) {
            throw new IllegalStateException("任务成功状态写入失败: " + taskId);
        }
        eventService.append(taskId, "task_succeeded", Map.of(
                "taskId", taskId, "summary", summary));
    }

    @Transactional
    public void fail(String taskId, String errorCode, String message) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            return;
        }
        TaskStatus current = TaskStatus.valueOf(task.getStatus());
        if (current.isTerminal() || current == TaskStatus.CANCELLING) {
            return;
        }
        if (TaskStateMachine.canTransition(current, TaskStatus.SUMMARIZING)) {
            transitionService.transition(
                    taskId, TaskStatus.SUMMARIZING,
                    TaskPhase.SUMMARY, "task_summarizing");
            task = taskMapper.selectForUpdate(taskId);
            current = TaskStatus.valueOf(task.getStatus());
        }
        TaskStateMachine.requireTransition(current, TaskStatus.FAILED);
        if (taskMapper.finish(
                taskId, TaskStatus.FAILED.name(), TaskPhase.valueOf(task.getPhase()).name(),
                message, errorCode, message, task.getVersion()) != 1) {
            throw new IllegalStateException("任务失败状态写入失败: " + taskId);
        }
        eventService.append(taskId, "task_failed", Map.of(
                "taskId", taskId,
                "errorCode", errorCode,
                "message", message == null ? "" : message
        ));
    }

    @Transactional
    public void needsReview(String taskId, String reason) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            return;
        }
        TaskStatus current = TaskStatus.valueOf(task.getStatus());
        if (current.isTerminal()) {
            return;
        }
        if (current != TaskStatus.EXECUTING && current != TaskStatus.CANCELLING) {
            fail(taskId, "EXECUTION_STATE_UNCERTAIN", reason);
            return;
        }
        TaskStateMachine.requireTransition(current, TaskStatus.NEEDS_REVIEW);
        if (taskMapper.finish(
                taskId, TaskStatus.NEEDS_REVIEW.name(), TaskPhase.valueOf(task.getPhase()).name(),
                reason, "EXECUTION_STATE_UNCERTAIN", reason, task.getVersion()) != 1) {
            throw new IllegalStateException("任务人工复核状态写入失败: " + taskId);
        }
        eventService.append(taskId, "task_needs_review", Map.of(
                "taskId", taskId, "reason", reason));
    }

    private AgentTaskEntity requireActiveTask(String taskId) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        TaskStatus status = TaskStatus.valueOf(task.getStatus());
        if (status.isTerminal() || status == TaskStatus.CANCELLING
                || Boolean.TRUE.equals(task.getCancelRequested())) {
            throw new TaskLimitExceededException(
                    "TASK_NOT_EXECUTABLE", "任务已结束或正在取消");
        }
        return task;
    }

    private String toJson(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("工作流数据无法序列化", e);
        }
    }

    private Object parseJson(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            return json;
        }
    }

    public record ExecutionClaim(String stepId, String preSnapshot) {
    }

    public record ExecutionOutcome(
            String stepId,
            boolean success,
            String resultSummary,
            Integer exitCode,
            boolean timedOut,
            boolean cancelled,
            boolean truncated
    ) {
    }

    public record FinishBatchResult(
            boolean failureLimitReached,
            int consecutiveFailures,
            boolean cancellationRequested
    ) {
    }

    public record VerificationRecord(
            String status,
            String plan,
            String result,
            String rollbackSuggestion
    ) {
    }
}
