package com.lowenssh.agent.task;

import com.lowenssh.agent.approval.ApprovalStatus;
import com.lowenssh.persistence.MessageService;
import com.lowenssh.persistence.entity.AgentApprovalEntity;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentApprovalMapper;
import com.lowenssh.persistence.mapper.AgentStepMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 非终态任务恢复器。
 *
 * 已知未执行的动作可以跳过后让模型重规划；已批准动作按数据库精确参数恢复；
 * EXECUTING 属于远端结果不确定区，只能 NEEDS_REVIEW，绝不自动重放。
 */
@Component
public class TaskRecoveryScheduler {

    private static final Logger log = LoggerFactory.getLogger(TaskRecoveryScheduler.class);
    private static final int BATCH_SIZE = 100;

    private final AgentTaskMapper taskMapper;
    private final AgentStepMapper stepMapper;
    private final AgentApprovalMapper approvalMapper;
    private final TaskRuntimeRegistry runtimeRegistry;
    private final TaskWorkflowOrchestrator orchestrator;
    private final WorkflowPersistenceService persistence;
    private final TaskCancellationFinalizer cancellationFinalizer;
    private final MessageService messageService;

    public TaskRecoveryScheduler(
            AgentTaskMapper taskMapper,
            AgentStepMapper stepMapper,
            AgentApprovalMapper approvalMapper,
            TaskRuntimeRegistry runtimeRegistry,
            TaskWorkflowOrchestrator orchestrator,
            WorkflowPersistenceService persistence,
            TaskCancellationFinalizer cancellationFinalizer,
            MessageService messageService) {
        this.taskMapper = taskMapper;
        this.stepMapper = stepMapper;
        this.approvalMapper = approvalMapper;
        this.runtimeRegistry = runtimeRegistry;
        this.orchestrator = orchestrator;
        this.persistence = persistence;
        this.cancellationFinalizer = cancellationFinalizer;
        this.messageService = messageService;
    }

    @Scheduled(
            initialDelayString = "${xwssh.agent.recovery-initial-delay:5s}",
            fixedDelayString = "${xwssh.agent.recovery-scan-interval:5s}")
    public void recover() {
        for (AgentTaskEntity task : taskMapper.selectRecoverable(BATCH_SIZE)) {
            if (runtimeRegistry.isRunning(task.getTaskId())) {
                continue;
            }
            try {
                recover(task);
            } catch (RuntimeException e) {
                log.warn("恢复 Agent 任务失败 taskId={}", task.getTaskId(), e);
            }
        }
    }

    private void recover(AgentTaskEntity task) {
        TaskStatus status = TaskStatus.valueOf(task.getStatus());
        switch (status) {
            case CREATED, PLANNING -> orchestrator.start(task.getTaskId());
            case VERIFYING, SUMMARIZING ->
                    orchestrator.continueAfterRestart(task.getTaskId());
            case RISK_CHECKING -> recoverRiskChecking(task);
            case WAITING_APPROVAL -> recoverApproval(task);
            case EXECUTING -> persistence.needsReview(
                    task.getTaskId(),
                    "服务重启时 Step 仍为 EXECUTING，无法证明远端动作是否已经发生，禁止自动重放");
            case CANCELLING ->
                    cancellationFinalizer.finalizeIfCancelling(task.getTaskId());
            default -> {
                // 查询只返回非终态；保留 default 防新增状态后误执行。
            }
        }
    }

    private void recoverRiskChecking(AgentTaskEntity task) {
        AgentStepEntity step = stepMapper.selectLatestByTask(task.getTaskId());
        if (step != null && "RISK_CHECKED".equals(step.getStatus())) {
            messageService.saveToolResult(
                    task.getSessionId(), step.getToolCallId(),
                    "服务重启前该动作尚未取得执行权，因此没有执行；请重新规划。");
        }
        orchestrator.continueAfterRestart(task.getTaskId());
    }

    private void recoverApproval(AgentTaskEntity task) {
        AgentApprovalEntity approval = approvalMapper.selectLatestByTask(task.getTaskId());
        if (approval == null) {
            persistence.fail(
                    task.getTaskId(), "APPROVAL_STATE_MISSING",
                    "任务处于 WAITING_APPROVAL，但审批记录不存在");
            return;
        }
        ApprovalStatus status = ApprovalStatus.valueOf(approval.getStatus());
        switch (status) {
            case PENDING -> {
                // 保持等待；审批 HTTP 或过期扫描器会改变数据库真相，下一轮再恢复。
            }
            case APPROVED -> orchestrator.resumeApprovedStep(task.getTaskId());
            case REJECTED -> {
                messageService.saveToolResult(
                        task.getSessionId(), approval.getToolCallId(),
                        "用户已拒绝该动作，请换用安全方案。");
                persistence.continueRiskChecking(task.getTaskId());
                orchestrator.continueAfterRestart(task.getTaskId());
            }
            case EXPIRED -> persistence.fail(
                    task.getTaskId(), "APPROVAL_EXPIRED", "审批已超时");
            case CANCELLED ->
                    cancellationFinalizer.finalizeIfCancelling(task.getTaskId());
        }
    }
}
