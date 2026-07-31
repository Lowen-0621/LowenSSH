package com.lowenssh.agent.task;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.entity.IdempotencyRecordEntity;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import com.lowenssh.persistence.mapper.IdempotencyRecordMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Map;

import static com.lowenssh.agent.task.TaskApiDto.CancelTaskResponse;

/** 严格幂等地持久化取消意图，并在事务提交后中断实际后台资源。 */
@Service
public class TaskCancellationService {

    private static final int HTTP_OK = 200;
    private static final int MAX_IDEMPOTENCY_KEY_LENGTH = 128;

    private final AgentTaskMapper taskMapper;
    private final IdempotencyRecordMapper idempotencyMapper;
    private final TaskEventService eventService;
    private final TaskTransitionService transitionService;
    private final TaskCancellationFinalizer cancellationFinalizer;
    private final TaskRuntimeRegistry runtimeRegistry;
    private final ObjectMapper objectMapper;
    private final Duration idempotencyRetention;

    public record CancelResult(CancelTaskResponse response, boolean replayed) {
    }

    public TaskCancellationService(
            AgentTaskMapper taskMapper,
            IdempotencyRecordMapper idempotencyMapper,
            TaskEventService eventService,
            TaskTransitionService transitionService,
            TaskCancellationFinalizer cancellationFinalizer,
            TaskRuntimeRegistry runtimeRegistry,
            ObjectMapper objectMapper,
            @Value("${xwssh.agent.idempotency-retention:PT24H}") Duration idempotencyRetention) {
        this.taskMapper = taskMapper;
        this.idempotencyMapper = idempotencyMapper;
        this.eventService = eventService;
        this.transitionService = transitionService;
        this.cancellationFinalizer = cancellationFinalizer;
        this.runtimeRegistry = runtimeRegistry;
        this.objectMapper = objectMapper;
        this.idempotencyRetention = idempotencyRetention;
    }

    @Transactional
    public CancelResult cancel(String taskId, String idempotencyKey) {
        validate(taskId, idempotencyKey);
        String key = idempotencyKey.strip();
        String scope = IdempotencyScope.CANCEL_TASK.name();
        String requestHash = RequestFingerprint.sha256(taskId, "cancel");

        idempotencyMapper.deleteExpiredKey(scope, key);
        idempotencyMapper.insertPlaceholder(
                scope, key, requestHash, LocalDateTime.now().plus(idempotencyRetention));
        IdempotencyRecordEntity record = idempotencyMapper.selectForUpdate(scope, key);
        if (record == null) {
            throw new IllegalStateException("取消幂等记录插入后无法读取");
        }
        if (!requestHash.equals(record.getRequestHash())) {
            throw new IdempotencyConflictException(key);
        }
        if (record.getResponseJson() != null) {
            return new CancelResult(fromJson(record.getResponseJson()), true);
        }

        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        TaskStatus current = TaskStatus.valueOf(task.getStatus());
        AgentTaskEntity result = task;
        if (!current.isTerminal() && current != TaskStatus.CANCELLING) {
            TaskStateMachine.requireTransition(current, TaskStatus.CANCELLING);
            int updated = taskMapper.requestCancellation(
                    taskId, TaskStatus.CANCELLING.name(), task.getVersion());
            if (updated != 1) {
                throw new IllegalStateException("任务取消状态并发更新失败: " + taskId);
            }
            eventService.append(taskId, "task_cancelling", Map.of(
                    "taskId", taskId,
                    "from", current.name(),
                    "to", TaskStatus.CANCELLING.name()
            ));
            result = taskMapper.selectForUpdate(taskId);
        }

        boolean running = runtimeRegistry.isRunning(taskId);
        if (!running && TaskStatus.valueOf(result.getStatus()) == TaskStatus.CANCELLING) {
            result = transitionService.transition(
                    taskId, TaskStatus.CANCELLED, TaskPhase.valueOf(result.getPhase()),
                    "task_cancelled");
        }

        CancelTaskResponse response = toResponse(result);
        idempotencyMapper.saveResponse(record.getId(), taskId, HTTP_OK, toJson(response));
        afterCommit(() -> {
            TaskRuntimeRegistry.CancellationSignal signal =
                    runtimeRegistry.signalCancellation(taskId);
            if (!signal.runtimeFound()) {
                cancellationFinalizer.finalizeIfCancelling(taskId);
            }
        });
        return new CancelResult(response, false);
    }

    private CancelTaskResponse toResponse(AgentTaskEntity task) {
        return new CancelTaskResponse(
                task.getTaskId(), task.getStatus(), task.getPhase(),
                Boolean.TRUE.equals(task.getCancelRequested()));
    }

    private void validate(String taskId, String key) {
        if (taskId == null || taskId.isBlank()) {
            throw new IllegalArgumentException("taskId 不能为空");
        }
        if (key == null || key.isBlank()) {
            throw new IllegalArgumentException("缺少 Idempotency-Key");
        }
        if (key.strip().length() > MAX_IDEMPOTENCY_KEY_LENGTH) {
            throw new IllegalArgumentException("Idempotency-Key 最长 128 个字符");
        }
    }

    private String toJson(CancelTaskResponse response) {
        try {
            return objectMapper.writeValueAsString(response);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("取消幂等响应序列化失败", e);
        }
    }

    private CancelTaskResponse fromJson(String json) {
        try {
            return objectMapper.readValue(json, CancelTaskResponse.class);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("已保存的取消响应无法反序列化", e);
        }
    }

    private void afterCommit(Runnable action) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            action.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                action.run();
            }
        });
    }
}
