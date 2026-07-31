package com.lowenssh.agent.task;

import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;

class TaskEventPublisherTest {

    @Test
    void 应用关闭时完成全部实时事件流且不再创建新流() {
        TaskEventPublisher publisher = new TaskEventPublisher();
        AtomicBoolean completed = new AtomicBoolean();
        publisher.live("task-1")
                .doOnComplete(() -> completed.set(true))
                .subscribe();

        publisher.closeStreams();

        assertThat(completed).isTrue();
        assertThat(publisher.live("task-2").blockLast()).isNull();
    }
}
