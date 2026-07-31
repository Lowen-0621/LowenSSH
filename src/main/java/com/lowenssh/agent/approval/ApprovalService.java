package com.lowenssh.agent.approval;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.task.TaskEventService;
import com.lowenssh.agent.task.TaskPhase;
import com.lowenssh.agent.task.TaskStateMachine;
import com.lowenssh.agent.task.TaskStatus;
import com.lowenssh.agent.task.TaskTransitionService;
import com.lowenssh.persistence.entity.AgentApprovalEntity;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentApprovalMapper;
import com.lowenssh.persistence.mapper.AgentStepMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static com.lowenssh.agent.approval.ApprovalApiDto.ApprovalView;

/** 审批请求、过期与读取的事务服务。 */
@Service
public class ApprovalService {

    private final AgentTaskMapper taskMapper;
    private final AgentStepMapper stepMapper;
    private final AgentApprovalMapper approvalMapper;
    private final TaskTransitionService transitionService;
    private final TaskEventService eventService;
    private final ApprovalWaitRegistry waitRegistry;
    private final ObjectMapper objectMapper;

    public ApprovalService(AgentTaskMapper taskMapper,
                           AgentStepMapper stepMapper,
                           AgentApprovalMapper approvalMapper,
                           TaskTransitionService transitionService,
                           TaskEventService eventService,
                           ApprovalWaitRegistry waitRegistry,
                           ObjectMapper objectMapper) {
        this.taskMapper = taskMapper;
        this.stepMapper = stepMapper;
        this.approvalMapper = approvalMapper;
        this.transitionService = transitionService;
        this.eventService = eventService;
        this.waitRegistry = waitRegistry;
        this.objectMapper = objectMapper;
    }

    /**
     * 创建或复用审批。
     *
     * 任务、Step、Approval 和 approval_required 事件在同一个事务内提交。
     */
    @Transactional
    public ApprovalView request(ApprovalRequest request) {
        if (request.timeout() == null || request.timeout().isNegative() || request.timeout().isZero()) {
            throw new IllegalArgumentException("审批超时必须大于 0");
        }
        AgentTaskEntity task = taskMapper.selectForUpdate(request.taskId());
        if (task == null) {
            throw new IllegalArgumentException("审批关联的任务不存在");
        }
        AgentStepEntity step = stepMapper.selectForUpdate(request.stepId());
        if (step == null || !request.taskId().equals(step.getTaskId())) {
            throw new IllegalArgumentException("审批关联的 Step 不存在或不属于该任务");
        }

        AgentApprovalEntity existing = approvalMapper.selectByActionForUpdate(
                request.taskId(), step.getToolCallId(), step.getActionDigest());
        if (existing != null) {
            return toView(existing);
        }

        TaskStatus current = TaskStatus.valueOf(task.getStatus());
        TaskStateMachine.requireTransition(current, TaskStatus.WAITING_APPROVAL);

        AgentApprovalEntity approval = new AgentApprovalEntity();
        approval.setApprovalId(UUID.randomUUID().toString());
        approval.setTaskId(request.taskId());
        approval.setStepId(request.stepId());
        approval.setToolCallId(step.getToolCallId());
        approval.setActionDigest(step.getActionDigest());
        approval.setStatus(ApprovalStatus.PENDING.name());
        approval.setRiskLevel(request.riskLevel());
        approval.setReason(request.reason());
        approval.setMatchedRules(toJson(request.matchedRules()));
        approval.setExpiresAt(LocalDateTime.now().plus(request.timeout()));
        approval.setVersion(0L);

        approvalMapper.insertOrKeepExisting(approval);
        AgentApprovalEntity persisted = approvalMapper.selectByActionForUpdate(
                request.taskId(), step.getToolCallId(), step.getActionDigest());
        if (persisted == null) {
            throw new IllegalStateException("审批插入后无法读取");
        }
        if (!approval.getApprovalId().equals(persisted.getApprovalId())) {
            return toView(persisted);
        }

        int stepUpdated = stepMapper.markApprovalState(
                step.getStepId(), "WAITING_APPROVAL", request.riskLevel(),
                request.policyVersion(), approval.getMatchedRules(), step.getVersion());
        if (stepUpdated != 1) {
            throw new IllegalStateException("审批 Step 状态更新失败");
        }

        transitionService.transition(
                request.taskId(), TaskStatus.WAITING_APPROVAL,
                TaskPhase.APPROVE, "task_waiting_approval");
        ApprovalView view = toView(persisted);
        eventService.append(request.taskId(), "approval_required", view);
        return view;
    }

    @Transactional(readOnly = true)
    public ApprovalView get(String approvalId) {
        AgentApprovalEntity entity = approvalMapper.selectById(approvalId);
        return entity == null ? null : toView(entity);
    }

    @Transactional(readOnly = true)
    public List<String> findExpiredPendingIds(int limit) {
        return approvalMapper.selectExpiredPending(LocalDateTime.now(), limit).stream()
                .map(AgentApprovalEntity::getApprovalId)
                .toList();
    }

    /**
     * 到期 CAS。若审批刚好在边界上被用户决定，CAS 失败后返回数据库中的最终结果。
     */
    @Transactional
    public ApprovalDecision expire(String approvalId) {
        AgentApprovalEntity snapshot = approvalMapper.selectById(approvalId);
        if (snapshot == null) {
            throw new IllegalArgumentException("审批不存在: " + approvalId);
        }
        AgentTaskEntity task = taskMapper.selectForUpdate(snapshot.getTaskId());
        AgentApprovalEntity approval = approvalMapper.selectForUpdate(approvalId);
        if (approval == null) {
            throw new IllegalArgumentException("审批不存在: " + approvalId);
        }
        ApprovalStatus current = ApprovalStatus.valueOf(approval.getStatus());
        if (current.isTerminal()) {
            return ApprovalDecision.from(current);
        }
        if (approval.getExpiresAt().isAfter(LocalDateTime.now())) {
            return null; // 定时器/等待误差提前触发，调用方继续等待剩余时间
        }

        int updated = approvalMapper.decidePending(
                approvalId, ApprovalStatus.EXPIRED.name(),
                LocalDateTime.now(), approval.getVersion());
        if (updated != 1) {
            AgentApprovalEntity raced = approvalMapper.selectForUpdate(approvalId);
            return ApprovalDecision.from(ApprovalStatus.valueOf(raced.getStatus()));
        }

        AgentStepEntity step = stepMapper.selectForUpdate(approval.getStepId());
        if (step != null) {
            stepMapper.markApprovalState(
                    step.getStepId(), "APPROVAL_EXPIRED", step.getRiskLevel(),
                    step.getPolicyVersion(), step.getMatchedRules(), step.getVersion());
        }
        if (task != null && TaskStatus.valueOf(task.getStatus()) == TaskStatus.WAITING_APPROVAL) {
            transitionService.transition(
                    task.getTaskId(), TaskStatus.TIMED_OUT,
                    TaskPhase.APPROVE, "task_timed_out");
        }
        eventService.append(approval.getTaskId(), "approval_expired", Map.of(
                "approvalId", approvalId,
                "taskId", approval.getTaskId(),
                "status", ApprovalStatus.EXPIRED.name()
        ));
        completeAfterCommit(approvalId, ApprovalDecision.EXPIRED);
        return ApprovalDecision.EXPIRED;
    }

    ApprovalView toView(AgentApprovalEntity entity) {
        return new ApprovalView(
                entity.getApprovalId(),
                entity.getTaskId(),
                entity.getStepId(),
                entity.getToolCallId(),
                entity.getActionDigest(),
                entity.getStatus(),
                entity.getRiskLevel(),
                entity.getReason(),
                fromJson(entity.getMatchedRules()),
                entity.getExpiresAt(),
                entity.getDecidedAt()
        );
    }

    void completeAfterCommit(String approvalId, ApprovalDecision decision) {
        Runnable complete = () -> waitRegistry.complete(approvalId, decision);
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            complete.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                complete.run();
            }
        });
    }

    private String toJson(List<String> rules) {
        try {
            return objectMapper.writeValueAsString(rules == null ? List.of() : rules);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("审批规则无法序列化", e);
        }
    }

    private List<String> fromJson(String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<>() {
            });
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("审批规则数据已损坏", e);
        }
    }
}
