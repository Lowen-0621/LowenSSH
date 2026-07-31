package com.lowenssh.agent.task;

import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 在独立事务中把已停止后台工作的任务从 CANCELLING 收敛到 CANCELLED。 */
@Service
public class TaskCancellationFinalizer {

    private final AgentTaskMapper taskMapper;
    private final TaskTransitionService transitionService;

    public TaskCancellationFinalizer(AgentTaskMapper taskMapper,
                                     TaskTransitionService transitionService) {
        this.taskMapper = taskMapper;
        this.transitionService = transitionService;
    }

    /** Agent 工作线程捕获取消并释放资源后也应调用此方法。 */
    @Transactional
    public void finalizeIfCancelling(String taskId) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task != null && TaskStatus.valueOf(task.getStatus()) == TaskStatus.CANCELLING) {
            transitionService.transition(
                    taskId, TaskStatus.CANCELLED, TaskPhase.valueOf(task.getPhase()),
                    "task_cancelled");
        }
    }
}
