package com.lowenssh.agent.task;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.entity.AgentTaskEventEntity;
import com.lowenssh.persistence.mapper.AgentTaskEventMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import reactor.core.publisher.Flux;

import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 任务事件存储和回放。
 *
 * 事件先持久化，事务提交后才进入实时流，避免客户端看到最终被回滚的“幽灵事件”。
 */
@Service
public class TaskEventService {

    private final AgentTaskMapper taskMapper;
    private final AgentTaskEventMapper eventMapper;
    private final TaskEventPublisher publisher;
    private final ObjectMapper objectMapper;

    public TaskEventService(AgentTaskMapper taskMapper,
                            AgentTaskEventMapper eventMapper,
                            TaskEventPublisher publisher,
                            ObjectMapper objectMapper) {
        this.taskMapper = taskMapper;
        this.eventMapper = eventMapper;
        this.publisher = publisher;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public TaskEventView append(String taskId, String type, Object payload) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }

        long sequence = task.getNextEventSequence();
        int advanced = taskMapper.advanceEventSequence(
                taskId, sequence + 1, task.getVersion());
        if (advanced != 1) {
            throw new IllegalStateException("任务事件序号并发更新失败: " + taskId);
        }

        AgentTaskEventEntity entity = new AgentTaskEventEntity();
        entity.setTaskId(taskId);
        entity.setSequenceNo(sequence);
        entity.setEventType(type);
        entity.setPayloadJson(toJson(payload));
        entity.setCreatedAt(LocalDateTime.now());
        eventMapper.insert(entity);

        TaskEventView view = toView(entity);
        publishAfterCommit(view);
        return view;
    }

    @Transactional(readOnly = true)
    public List<TaskEventView> replay(String taskId, long afterEventId) {
        return eventMapper.selectAfter(taskId, Math.max(0, afterEventId)).stream()
                .map(this::toView)
                .toList();
    }

    /**
     * 历史回放后衔接实时流。
     *
     * 实时 Sink 自带小型 replay 缓冲；AtomicLong 过滤历史查询与实时缓冲中的重复事件。
     */
    public Flux<TaskEventView> stream(String taskId, long afterEventId) {
        return Flux.defer(() -> {
            AtomicLong lastSeen = new AtomicLong(Math.max(0, afterEventId));
            Flux<TaskEventView> history = Flux.fromIterable(replay(taskId, afterEventId));
            return Flux.concat(history, publisher.live(taskId))
                    .filter(event -> advance(lastSeen, event.id()));
        });
    }

    private boolean advance(AtomicLong lastSeen, long eventId) {
        while (true) {
            long current = lastSeen.get();
            if (eventId <= current) {
                return false;
            }
            if (lastSeen.compareAndSet(current, eventId)) {
                return true;
            }
        }
    }

    private String toJson(Object payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("任务事件无法序列化", e);
        }
    }

    private TaskEventView toView(AgentTaskEventEntity entity) {
        return new TaskEventView(
                entity.getId(),
                entity.getTaskId(),
                entity.getSequenceNo(),
                entity.getEventType(),
                parseJson(entity.getPayloadJson()),
                entity.getCreatedAt()
        );
    }

    private com.fasterxml.jackson.databind.JsonNode parseJson(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("数据库中的任务事件 JSON 已损坏", e);
        }
    }

    private void publishAfterCommit(TaskEventView event) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            publisher.publish(event);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                publisher.publish(event);
            }
        });
    }
}
