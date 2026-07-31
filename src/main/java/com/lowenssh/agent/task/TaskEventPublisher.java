package com.lowenssh.agent.task;

import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 任务事件的进程内实时总线。
 *
 * 数据库负责可靠回放；这里的 replay 缓冲只解决“查询历史与订阅实时流之间”的竞态窗口。
 */
@Component
public class TaskEventPublisher {

    private static final int LIVE_REPLAY_LIMIT = 512;
    private final Map<String, Sinks.Many<TaskEventView>> sinks = new ConcurrentHashMap<>();
    private final AtomicBoolean closed = new AtomicBoolean();

    public void publish(TaskEventView event) {
        if (closed.get()) {
            return;
        }
        sink(event.taskId()).tryEmitNext(event);
    }

    public Flux<TaskEventView> live(String taskId) {
        if (closed.get()) {
            return Flux.empty();
        }
        return sink(taskId).asFlux();
    }

    private Sinks.Many<TaskEventView> sink(String taskId) {
        return sinks.computeIfAbsent(taskId,
                ignored -> Sinks.many().replay().limit(LIVE_REPLAY_LIMIT));
    }

    /**
     * Spring 在停止 Web Server 前发布 ContextClosedEvent。此时主动完成所有无限 SSE，
     * 避免优雅停机把它们当作活跃请求一直等待到超时。
     */
    @EventListener(ContextClosedEvent.class)
    public void closeStreams() {
        if (!closed.compareAndSet(false, true)) {
            return;
        }
        sinks.values().forEach(Sinks.Many::tryEmitComplete);
        sinks.clear();
    }
}
