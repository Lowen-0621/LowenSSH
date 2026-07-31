package com.lowenssh.agent.task;

import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;

/**
 * 任务状态迁移的唯一写入口。
 *
 * Phase 2 之后审批、取消、超时和恢复器都必须调用它，不能直接 update 状态字段。
 */
@Service
public class TaskTransitionService {

    private final AgentTaskMapper taskMapper;
    private final TaskEventService eventService;

    public TaskTransitionService(AgentTaskMapper taskMapper, TaskEventService eventService) {
        this.taskMapper = taskMapper;
        this.eventService = eventService;
    }

    @Transactional
    public AgentTaskEntity transition(String taskId,
                                      TaskStatus targetStatus,
                                      TaskPhase targetPhase,
                                      String eventType) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        TaskStatus current = TaskStatus.valueOf(task.getStatus());
        TaskStateMachine.requireTransition(current, targetStatus);

        if (current == targetStatus && targetPhase.name().equals(task.getPhase())) {
            return task;
        }
        int updated = taskMapper.transition(
                taskId, targetStatus.name(), targetPhase.name(), task.getVersion());
        if (updated != 1) {
            throw new IllegalStateException("任务状态并发更新失败: " + taskId);
        }
        eventService.append(taskId, eventType, Map.of(
                "taskId", taskId,
                "from", current.name(),
                "to", targetStatus.name(),
                "phase", targetPhase.name()
        ));
        return taskMapper.selectById(taskId);
    }
}
