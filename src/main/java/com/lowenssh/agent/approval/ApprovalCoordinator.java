package com.lowenssh.agent.approval;

import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import static com.lowenssh.agent.approval.ApprovalApiDto.ApprovalView;

/**
 * 审批事务和线程等待之间的边界。
 *
 * request() 返回时事务已经提交，之后才阻塞 Agent 工作线程，审批 HTTP 才能更新数据库。
 */
@Service
public class ApprovalCoordinator {

    private final ApprovalService approvalService;
    private final ApprovalWaitRegistry waitRegistry;

    public ApprovalCoordinator(ApprovalService approvalService, ApprovalWaitRegistry waitRegistry) {
        this.approvalService = approvalService;
        this.waitRegistry = waitRegistry;
    }

    public ApprovalDecision requestAndAwait(ApprovalRequest request) {
        ApprovalView approval = approvalService.request(request);
        ApprovalStatus status = ApprovalStatus.valueOf(approval.status());
        if (status.isTerminal()) {
            return ApprovalDecision.from(status);
        }

        CompletableFuture<ApprovalDecision> future =
                waitRegistry.register(approval.approvalId());
        try {
            while (true) {
                // Future 注册后再次读库，封住“审批先完成、Future 后注册”的竞态窗口。
                ApprovalView latest = approvalService.get(approval.approvalId());
                ApprovalStatus latestStatus = ApprovalStatus.valueOf(latest.status());
                if (latestStatus.isTerminal()) {
                    return ApprovalDecision.from(latestStatus);
                }
                try {
                    Duration timeout = remaining(latest);
                    return future.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
                } catch (TimeoutException e) {
                    ApprovalDecision expired = approvalService.expire(approval.approvalId());
                    if (expired != null) {
                        return expired;
                    }
                    // 系统时钟/调度存在毫秒误差，数据库尚未到期时重新计算剩余时间。
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ApprovalDecision.CANCELLED;
        } catch (ExecutionException e) {
            throw new IllegalStateException("等待审批结果失败", e.getCause());
        } finally {
            waitRegistry.remove(approval.approvalId(), future);
        }
    }

    private Duration remaining(ApprovalView approval) {
        Duration remaining = Duration.between(java.time.LocalDateTime.now(), approval.expiresAt());
        return remaining.isNegative() || remaining.isZero()
                ? Duration.ofMillis(1)
                : remaining;
    }
}
