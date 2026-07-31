package com.lowenssh.agent.approval;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.task.IdempotencyScope;
import com.lowenssh.agent.task.RequestFingerprint;
import com.lowenssh.agent.task.TaskEventService;
import com.lowenssh.agent.task.TaskPhase;
import com.lowenssh.agent.task.TaskStatus;
import com.lowenssh.agent.task.TaskTransitionService;
import com.lowenssh.persistence.entity.AgentApprovalEntity;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.persistence.entity.IdempotencyRecordEntity;
import com.lowenssh.persistence.mapper.AgentApprovalMapper;
import com.lowenssh.persistence.mapper.AgentStepMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import com.lowenssh.persistence.mapper.IdempotencyRecordMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Map;

import static com.lowenssh.agent.approval.ApprovalApiDto.DecideApprovalRequest;

/**
 * 严格幂等的审批决定。
 *
 * HTTP 200 和业务冲突 409 都会保存响应，重试同一个 Idempotency-Key 时原样回放。
 */
@Service
public class ApprovalDecisionService {

    private static final int HTTP_OK = 200;
    private static final int HTTP_NOT_FOUND = 404;
    private static final int HTTP_CONFLICT = 409;

    private final AgentTaskMapper taskMapper;
    private final AgentStepMapper stepMapper;
    private final AgentApprovalMapper approvalMapper;
    private final IdempotencyRecordMapper idempotencyMapper;
    private final TaskEventService eventService;
    private final TaskTransitionService transitionService;
    private final ApprovalService approvalService;
    private final ObjectMapper objectMapper;
    private final Duration idempotencyRetention;

    public record DecisionResult(int httpStatus, JsonNode body, boolean replayed) {
    }

    public ApprovalDecisionService(AgentTaskMapper taskMapper,
                                   AgentStepMapper stepMapper,
                                   AgentApprovalMapper approvalMapper,
                                   IdempotencyRecordMapper idempotencyMapper,
                                   TaskEventService eventService,
                                   TaskTransitionService transitionService,
                                   ApprovalService approvalService,
                                   ObjectMapper objectMapper,
                                   @Value("${xwssh.agent.idempotency-retention:PT24H}")
                                   Duration idempotencyRetention) {
        this.taskMapper = taskMapper;
        this.stepMapper = stepMapper;
        this.approvalMapper = approvalMapper;
        this.idempotencyMapper = idempotencyMapper;
        this.eventService = eventService;
        this.transitionService = transitionService;
        this.approvalService = approvalService;
        this.objectMapper = objectMapper;
        this.idempotencyRetention = idempotencyRetention;
    }

    @Transactional
    public DecisionResult decide(String approvalId,
                                 String idempotencyKey,
                                 DecideApprovalRequest request) {
        validate(approvalId, idempotencyKey, request);
        String key = idempotencyKey.strip();
        String scope = IdempotencyScope.DECIDE_APPROVAL.name();
        String requestHash = RequestFingerprint.sha256(approvalId, request.approved());

        idempotencyMapper.deleteExpiredKey(scope, key);
        idempotencyMapper.insertPlaceholder(
                scope, key, requestHash, LocalDateTime.now().plus(idempotencyRetention));
        IdempotencyRecordEntity idempotency = idempotencyMapper.selectForUpdate(scope, key);
        if (!requestHash.equals(idempotency.getRequestHash())) {
            return conflict("IDEMPOTENCY_KEY_REUSED",
                    "Idempotency-Key 已被不同审批请求使用", false);
        }
        if (idempotency.getResponseJson() != null) {
            return new DecisionResult(
                    idempotency.getResponseStatus(),
                    parse(idempotency.getResponseJson()),
                    true
            );
        }

        AgentApprovalEntity snapshot = approvalMapper.selectById(approvalId);
        if (snapshot == null) {
            return persist(idempotency, HTTP_NOT_FOUND,
                    error("APPROVAL_NOT_FOUND", "审批不存在"), null);
        }

        // 全部审批写操作统一 task → approval → step 锁顺序，降低并发决定/超时/取消死锁风险。
        taskMapper.selectForUpdate(snapshot.getTaskId());
        AgentApprovalEntity approval = approvalMapper.selectForUpdate(approvalId);
        ApprovalStatus current = ApprovalStatus.valueOf(approval.getStatus());
        ApprovalStatus requested = request.approved()
                ? ApprovalStatus.APPROVED
                : ApprovalStatus.REJECTED;

        if (current.isTerminal()) {
            return existingTerminal(idempotency, approval, current, requested);
        }

        ApprovalStatus target = approval.getExpiresAt().isAfter(LocalDateTime.now())
                ? requested
                : ApprovalStatus.EXPIRED;
        int updated = approvalMapper.decidePending(
                approvalId, target.name(), LocalDateTime.now(), approval.getVersion());
        if (updated != 1) {
            AgentApprovalEntity raced = approvalMapper.selectForUpdate(approvalId);
            return existingTerminal(
                    idempotency, raced, ApprovalStatus.valueOf(raced.getStatus()), requested);
        }

        AgentStepEntity step = stepMapper.selectForUpdate(approval.getStepId());
        if (step != null) {
            stepMapper.markApprovalState(
                    step.getStepId(),
                    target == ApprovalStatus.APPROVED ? "READY_TO_EXECUTE" : "APPROVAL_" + target.name(),
                    step.getRiskLevel(),
                    step.getPolicyVersion(),
                    step.getMatchedRules(),
                    step.getVersion()
            );
        }

        AgentApprovalEntity decided = approvalMapper.selectForUpdate(approvalId);
        String eventType = target == ApprovalStatus.EXPIRED
                ? "approval_expired"
                : "approval_decided";
        eventService.append(decided.getTaskId(), eventType, approvalService.toView(decided));
        if (target == ApprovalStatus.EXPIRED) {
            transitionService.transition(
                    decided.getTaskId(), TaskStatus.TIMED_OUT,
                    TaskPhase.APPROVE, "task_timed_out");
        }
        approvalService.completeAfterCommit(approvalId, ApprovalDecision.from(target));

        if (target == ApprovalStatus.EXPIRED) {
            return persist(idempotency, HTTP_CONFLICT,
                    error("APPROVAL_EXPIRED", "审批已超时"), approvalId);
        }
        return persist(idempotency, HTTP_OK,
                objectMapper.valueToTree(approvalService.toView(decided)), approvalId);
    }

    private DecisionResult existingTerminal(IdempotencyRecordEntity idempotency,
                                            AgentApprovalEntity approval,
                                            ApprovalStatus current,
                                            ApprovalStatus requested) {
        if (current == requested) {
            return persist(idempotency, HTTP_OK,
                    objectMapper.valueToTree(approvalService.toView(approval)),
                    approval.getApprovalId());
        }
        String code = switch (current) {
            case EXPIRED -> "APPROVAL_EXPIRED";
            case CANCELLED -> "APPROVAL_CANCELLED";
            default -> "APPROVAL_ALREADY_DECIDED";
        };
        return persist(idempotency, HTTP_CONFLICT,
                error(code, "审批已经是 " + current + "，不能改为 " + requested),
                approval.getApprovalId());
    }

    private DecisionResult persist(IdempotencyRecordEntity record,
                                   int status,
                                   JsonNode body,
                                   String resourceId) {
        idempotencyMapper.saveResponse(
                record.getId(), resourceId, status, stringify(body));
        return new DecisionResult(status, body, false);
    }

    private DecisionResult conflict(String code, String message, boolean replayed) {
        return new DecisionResult(HTTP_CONFLICT, error(code, message), replayed);
    }

    private JsonNode error(String code, String message) {
        return objectMapper.valueToTree(Map.of("code", code, "message", message));
    }

    private String stringify(JsonNode body) {
        try {
            return objectMapper.writeValueAsString(body);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("审批响应序列化失败", e);
        }
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("已保存的审批响应损坏", e);
        }
    }

    private void validate(String approvalId, String key, DecideApprovalRequest request) {
        if (approvalId == null || approvalId.isBlank()) {
            throw new IllegalArgumentException("approvalId 不能为空");
        }
        if (key == null || key.isBlank()) {
            throw new IllegalArgumentException("缺少 Idempotency-Key");
        }
        if (key.strip().length() > 128) {
            throw new IllegalArgumentException("Idempotency-Key 最长 128 个字符");
        }
        if (request == null) {
            throw new IllegalArgumentException("审批决定不能为空");
        }
    }
}
