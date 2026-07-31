package com.lowenssh.agent.approval;

import com.lowenssh.agent.guard.ConfirmationHandler;
import com.lowenssh.agent.guard.ConfirmationRequest;
import com.lowenssh.agent.task.AgentStepService;
import com.lowenssh.agent.task.TaskPhase;
import com.lowenssh.agent.task.TaskStatus;
import com.lowenssh.agent.task.TaskTransitionService;
import com.lowenssh.persistence.entity.AgentStepEntity;

import java.time.Duration;
import java.util.List;

/**
 * AgentService 与持久化审批状态机之间的适配器。
 *
 * 一个实例只绑定一个 taskId，避免不同任务共享可变审批上下文。
 */
public class PersistentConfirmationHandler implements ConfirmationHandler {

    private final String taskId;
    private final AgentStepService stepService;
    private final ApprovalCoordinator coordinator;
    private final TaskTransitionService transitionService;
    private final Duration timeout;
    private final String policyVersion;

    public PersistentConfirmationHandler(String taskId,
                                         AgentStepService stepService,
                                         ApprovalCoordinator coordinator,
                                         TaskTransitionService transitionService,
                                         Duration timeout,
                                         String policyVersion) {
        this.taskId = taskId;
        this.stepService = stepService;
        this.coordinator = coordinator;
        this.transitionService = transitionService;
        this.timeout = timeout;
        this.policyVersion = policyVersion;
    }

    @Override
    public boolean confirm(String command, String reason) {
        throw new IllegalStateException("持久化审批必须携带 Tool Call 上下文");
    }

    @Override
    public boolean confirm(ConfirmationRequest request) {
        AgentStepEntity step = stepService.createOrGet(
                taskId,
                request.toolCallId(),
                TaskPhase.APPROVE,
                "TOOL_APPROVAL",
                request.toolName(),
                request.argumentsJson(),
                policyVersion
        );
        ApprovalDecision decision = coordinator.requestAndAwait(new ApprovalRequest(
                taskId,
                step.getStepId(),
                request.riskLevel(),
                request.reason(),
                request.matchedRules(),
                request.policyVersion(),
                timeout
        ));
        if (decision == ApprovalDecision.APPROVED) {
            // 这里只恢复到风险检查；同一批可能还有其他 ASK。
            // 全批检查完后由持久化 observer 一次性获取执行权并进入 EXECUTING。
            transitionService.transition(
                    taskId, TaskStatus.RISK_CHECKING, TaskPhase.RISK_CHECK,
                    "task_approval_granted");
        } else if (decision == ApprovalDecision.REJECTED) {
            transitionService.transition(
                    taskId, TaskStatus.RISK_CHECKING, TaskPhase.RISK_CHECK,
                    "task_approval_rejected");
        }
        return decision == ApprovalDecision.APPROVED;
    }
}
