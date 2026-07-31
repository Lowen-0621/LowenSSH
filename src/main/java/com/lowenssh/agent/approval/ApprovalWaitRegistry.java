package com.lowenssh.agent.approval;

import org.springframework.stereotype.Component;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * JVM 内审批等待表。
 *
 * 它只负责通知，不是状态真相；进程重启后 Map 会消失，恢复时必须重新读取数据库。
 */
@Component
public class ApprovalWaitRegistry {

    private final ConcurrentMap<String, CompletableFuture<ApprovalDecision>> waits =
            new ConcurrentHashMap<>();

    public CompletableFuture<ApprovalDecision> register(String approvalId) {
        return waits.computeIfAbsent(approvalId, ignored -> new CompletableFuture<>());
    }

    public boolean complete(String approvalId, ApprovalDecision decision) {
        CompletableFuture<ApprovalDecision> future = waits.get(approvalId);
        return future != null && future.complete(decision);
    }

    public void remove(String approvalId, CompletableFuture<ApprovalDecision> future) {
        waits.remove(approvalId, future);
    }

    int size() {
        return waits.size();
    }
}
