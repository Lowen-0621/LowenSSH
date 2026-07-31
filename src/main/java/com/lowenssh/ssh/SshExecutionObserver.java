package com.lowenssh.ssh;

import java.time.Duration;

@FunctionalInterface
public interface SshExecutionObserver {

    SshExecutionObserver NOOP = (result, error, duration) -> {
    };

    void completed(ExecResult result, Throwable error, Duration duration);
}
