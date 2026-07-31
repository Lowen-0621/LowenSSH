package com.lowenssh.agent.task;

import com.lowenssh.ssh.SshClient;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class TaskRuntimeRegistryTest {

    @Test
    void 取消会同时通知模型工作线程和SSH通道() throws Exception {
        TaskRuntimeRegistry registry = new TaskRuntimeRegistry();
        SshClient ssh = mock(SshClient.class);
        when(ssh.cancelActiveCommand()).thenReturn(true);
        CompletableFuture<Void> modelCall = new CompletableFuture<>();
        CountDownLatch registered = new CountDownLatch(1);
        CountDownLatch interrupted = new CountDownLatch(1);

        Thread worker = new Thread(() -> {
            try (TaskRuntimeRegistry.Registration ignored = registry.register("task-1")) {
                registry.bindSsh("task-1", ssh);
                registry.bindModelCall("task-1", modelCall);
                registered.countDown();
                try {
                    Thread.sleep(30_000);
                } catch (InterruptedException e) {
                    interrupted.countDown();
                    Thread.currentThread().interrupt();
                }
            }
        });
        worker.start();
        assertThat(registered.await(2, TimeUnit.SECONDS)).isTrue();

        TaskRuntimeRegistry.CancellationSignal signal =
                registry.signalCancellation("task-1");

        assertThat(signal.runtimeFound()).isTrue();
        assertThat(signal.modelSignalAccepted()).isTrue();
        assertThat(signal.sshChannelClosed()).isTrue();
        assertThat(modelCall.isCancelled()).isTrue();
        assertThat(interrupted.await(2, TimeUnit.SECONDS)).isTrue();
        worker.join(2_000);
        assertThat(worker.isAlive()).isFalse();
        verify(ssh).cancelActiveCommand();
    }

    @Test
    void 未运行任务的取消信号是安全空操作() {
        TaskRuntimeRegistry.CancellationSignal signal =
                new TaskRuntimeRegistry().signalCancellation("missing");

        assertThat(signal.runtimeFound()).isFalse();
        assertThat(signal.modelSignalAccepted()).isFalse();
        assertThat(signal.sshChannelClosed()).isFalse();
    }

    @Test
    void 取消先到时后绑定的模型调用也会立即取消() {
        TaskRuntimeRegistry registry = new TaskRuntimeRegistry();
        CompletableFuture<Void> modelCall = new CompletableFuture<>();

        try (TaskRuntimeRegistry.Registration ignored = registry.register("task-race")) {
            registry.signalCancellation("task-race");
            registry.bindModelCall("task-race", modelCall);
        }

        assertThat(modelCall.isCancelled()).isTrue();
    }
}
