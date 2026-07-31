package com.lowenssh.agent.task;

import com.lowenssh.ssh.SshClient;
import org.springframework.stereotype.Component;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * JVM 内任务运行句柄。
 *
 * 数据库保存“应当取消”，这里负责把信号送到当前工作线程、模型 Future 和 SSH Channel。
 * SSE 订阅不登记在这里，所以客户端断开 SSE 不会误取消后台任务。
 */
@Component
public class TaskRuntimeRegistry {

    private final ConcurrentMap<String, RuntimeHandle> runtimes = new ConcurrentHashMap<>();

    public Registration register(String taskId) {
        RuntimeHandle handle = new RuntimeHandle(Thread.currentThread());
        RuntimeHandle existing = runtimes.putIfAbsent(taskId, handle);
        if (existing != null) {
            throw new IllegalStateException("任务已有运行实例: " + taskId);
        }
        return new Registration(taskId, handle);
    }

    public void bindSsh(String taskId, SshClient sshClient) {
        require(taskId).sshClient = sshClient;
    }

    public void bindModelCall(String taskId, Future<?> modelCall) {
        RuntimeHandle handle = require(taskId);
        handle.modelCall = modelCall;
        // 处理“取消信号先到、Future 随后才绑定”的竞态。
        if (handle.cancelRequested.get()) {
            modelCall.cancel(true);
        }
    }

    public void clearModelCall(String taskId, Future<?> modelCall) {
        RuntimeHandle handle = runtimes.get(taskId);
        if (handle != null && handle.modelCall == modelCall) {
            handle.modelCall = null;
        }
    }

    public boolean isRunning(String taskId) {
        return runtimes.containsKey(taskId);
    }

    public boolean isCancellationRequested(String taskId) {
        RuntimeHandle handle = runtimes.get(taskId);
        return handle != null && handle.cancelRequested.get();
    }

    /**
     * 尽能力取消所有后台资源。Future.cancel(true) 只能发中断信号，
     * 第三方 HTTP 客户端是否真正终止由其实现决定，因此返回值不冒充“已终止”。
     */
    public CancellationSignal signalCancellation(String taskId) {
        RuntimeHandle handle = runtimes.get(taskId);
        if (handle == null) {
            return CancellationSignal.NOT_RUNNING;
        }
        handle.cancelRequested.set(true);
        boolean modelSignalAccepted = handle.modelCall != null && handle.modelCall.cancel(true);
        boolean sshChannelClosed = handle.sshClient != null && handle.sshClient.cancelActiveCommand();
        handle.worker.interrupt();
        return new CancellationSignal(true, modelSignalAccepted, sshChannelClosed);
    }

    private RuntimeHandle require(String taskId) {
        RuntimeHandle handle = runtimes.get(taskId);
        if (handle == null) {
            throw new IllegalStateException("任务未注册运行句柄: " + taskId);
        }
        return handle;
    }

    private static final class RuntimeHandle {
        private final Thread worker;
        private final AtomicBoolean cancelRequested = new AtomicBoolean();
        private volatile Future<?> modelCall;
        private volatile SshClient sshClient;

        private RuntimeHandle(Thread worker) {
            this.worker = worker;
        }
    }

    public record CancellationSignal(
            boolean runtimeFound,
            boolean modelSignalAccepted,
            boolean sshChannelClosed
    ) {
        private static final CancellationSignal NOT_RUNNING =
                new CancellationSignal(false, false, false);
    }

    public final class Registration implements AutoCloseable {
        private final String taskId;
        private final RuntimeHandle handle;
        private final AtomicBoolean closed = new AtomicBoolean();

        private Registration(String taskId, RuntimeHandle handle) {
            this.taskId = taskId;
            this.handle = handle;
        }

        @Override
        public void close() {
            if (closed.compareAndSet(false, true)) {
                runtimes.remove(taskId, handle);
            }
        }
    }
}
