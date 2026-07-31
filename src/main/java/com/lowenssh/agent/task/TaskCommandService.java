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

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

import static com.lowenssh.agent.task.TaskApiDto.CreateTaskRequest;
import static com.lowenssh.agent.task.TaskApiDto.CreateTaskResponse;
import static com.lowenssh.agent.task.TaskApiDto.TaskView;

/** 创建、查询任务以及严格幂等响应回放。 */
@Service
public class TaskCommandService {

    private static final int HTTP_ACCEPTED = 202;
    private static final int MAX_IDEMPOTENCY_KEY_LENGTH = 128;

    private final AgentTaskMapper taskMapper;
    private final IdempotencyRecordMapper idempotencyMapper;
    private final TaskEventService eventService;
    private final ObjectMapper objectMapper;
    private final Duration idempotencyRetention;
    private final Duration taskTimeout;

    /** body 在首次请求和重放时完全一致；replayed 只用于 Controller 设置响应头。 */
    public record CreateResult(CreateTaskResponse response, boolean replayed) {
    }

    public TaskCommandService(AgentTaskMapper taskMapper,
                              IdempotencyRecordMapper idempotencyMapper,
                              TaskEventService eventService,
                              ObjectMapper objectMapper,
                              @Value("${xwssh.agent.idempotency-retention:PT24H}")
                              Duration idempotencyRetention,
                              @Value("${xwssh.agent.task-timeout:PT10M}")
                              Duration taskTimeout) {
        this.taskMapper = taskMapper;
        this.idempotencyMapper = idempotencyMapper;
        this.eventService = eventService;
        this.objectMapper = objectMapper;
        this.idempotencyRetention = idempotencyRetention;
        if (taskTimeout == null || taskTimeout.isZero() || taskTimeout.isNegative()) {
            throw new IllegalArgumentException("Agent 整体任务超时必须大于 0");
        }
        this.taskTimeout = taskTimeout;
    }

    /**
     * 严格幂等创建任务。
     *
     * INSERT ... ON DUPLICATE KEY 争抢唯一键；随后 SELECT FOR UPDATE 读取唯一记录。
     * 任务和幂等响应在同一事务提交，
     * 不会留下“Key 已占用但任务不存在”的半成品。
     */
    @Transactional
    public CreateResult create(String idempotencyKey, CreateTaskRequest request) {
        validate(idempotencyKey, request);
        String key = idempotencyKey.strip();
        String requestHash = RequestFingerprint.sha256(
                request.sessionId(), request.hostId(), request.task().strip());
        String scope = IdempotencyScope.CREATE_TASK.name();

        idempotencyMapper.deleteExpiredKey(scope, key);
        idempotencyMapper.insertPlaceholder(
                scope, key, requestHash, LocalDateTime.now().plus(idempotencyRetention));
        IdempotencyRecordEntity record = idempotencyMapper.selectForUpdate(scope, key);
        if (record == null) {
            throw new IllegalStateException("幂等记录插入后无法读取");
        }
        if (!requestHash.equals(record.getRequestHash())) {
            throw new IdempotencyConflictException(key);
        }
        if (record.getResponseJson() != null) {
            return new CreateResult(fromJson(record.getResponseJson()), true);
        }

        AgentTaskEntity task = new AgentTaskEntity();
        task.setTaskId(UUID.randomUUID().toString());
        task.setSessionId(request.sessionId());
        task.setHostId(request.hostId());
        task.setRequestHash(requestHash);
        task.setTaskText(request.task().strip());
        task.setStatus(TaskStatus.CREATED.name());
        task.setPhase(TaskPhase.PLAN.name());
        task.setCancelRequested(false);
        task.setDeadlineAt(LocalDateTime.now().plus(taskTimeout));
        task.setModelCalls(0);
        task.setToolCalls(0);
        task.setConsecutiveFailures(0);
        task.setNextStepSequence(1L);
        task.setNextEventSequence(1L);
        task.setVersion(0L);
        task.setCreatedAt(LocalDateTime.now());
        task.setUpdatedAt(task.getCreatedAt());
        taskMapper.insert(task);

        eventService.append(task.getTaskId(), "task_created", Map.of(
                "taskId", task.getTaskId(),
                "status", task.getStatus(),
                "phase", task.getPhase()
        ));

        CreateTaskResponse response = new CreateTaskResponse(
                task.getTaskId(), task.getStatus(), task.getPhase());
        idempotencyMapper.saveResponse(
                record.getId(), task.getTaskId(), HTTP_ACCEPTED, toJson(response));
        return new CreateResult(response, false);
    }

    @Transactional(readOnly = true)
    public TaskView get(String taskId) {
        AgentTaskEntity task = taskMapper.selectById(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        return toView(task);
    }

    private TaskView toView(AgentTaskEntity task) {
        return new TaskView(
                task.getTaskId(),
                task.getSessionId(),
                task.getHostId(),
                task.getStatus(),
                task.getPhase(),
                Boolean.TRUE.equals(task.getCancelRequested()),
                task.getVersion(),
                task.getDeadlineAt(),
                task.getCreatedAt(),
                task.getUpdatedAt()
        );
    }

    private void validate(String key, CreateTaskRequest request) {
        if (key == null || key.isBlank()) {
            throw new IllegalArgumentException("缺少 Idempotency-Key");
        }
        if (key.strip().length() > MAX_IDEMPOTENCY_KEY_LENGTH) {
            throw new IllegalArgumentException("Idempotency-Key 最长 128 个字符");
        }
        if (request == null || request.task() == null || request.task().isBlank()) {
            throw new IllegalArgumentException("任务内容不能为空");
        }
    }

    private String toJson(CreateTaskResponse response) {
        try {
            return objectMapper.writeValueAsString(response);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("幂等响应序列化失败", e);
        }
    }

    private CreateTaskResponse fromJson(String json) {
        try {
            return objectMapper.readValue(json, CreateTaskResponse.class);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("已保存的幂等响应无法反序列化", e);
        }
    }
}
