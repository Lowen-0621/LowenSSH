package com.lowenssh.agent.task;

import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

/** 扫描整体截止时间，先持久化 TIMED_OUT，再中断当前 JVM 中的后台资源。 */
@Component
public class TaskTimeoutScheduler {

    private static final Logger log = LoggerFactory.getLogger(TaskTimeoutScheduler.class);
    private static final int BATCH_SIZE = 100;

    private final AgentTaskMapper taskMapper;
    private final TaskTransitionService transitionService;
    private final TaskRuntimeRegistry runtimeRegistry;

    public TaskTimeoutScheduler(AgentTaskMapper taskMapper,
                                TaskTransitionService transitionService,
                                TaskRuntimeRegistry runtimeRegistry) {
        this.taskMapper = taskMapper;
        this.transitionService = transitionService;
        this.runtimeRegistry = runtimeRegistry;
    }

    @Scheduled(fixedDelayString = "${xwssh.agent.task-timeout-scan-interval:5s}")
    public void expireOverdueTasks() {
        for (AgentTaskEntity task : taskMapper.selectOverdue(LocalDateTime.now(), BATCH_SIZE)) {
            try {
                transitionService.transition(
                        task.getTaskId(), TaskStatus.TIMED_OUT,
                        TaskPhase.valueOf(task.getPhase()), "task_timed_out");
                runtimeRegistry.signalCancellation(task.getTaskId());
            } catch (IllegalTaskTransitionException ignored) {
                // 扫描结果到加锁更新之间可能已进入终态，这是正常并发。
            } catch (RuntimeException e) {
                log.warn("任务超时收敛失败 taskId={}", task.getTaskId(), e);
            }
        }
    }
}
