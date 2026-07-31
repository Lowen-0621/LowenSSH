package com.lowenssh.agent.approval;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 兜底回收没有活跃等待线程的过期审批。
 *
 * 正常等待由 ApprovalCoordinator 触发过期；该扫描器负责 SSE 客户端断开或进程恢复后的遗留记录。
 */
@Component
public class ApprovalExpiryScheduler {

    private static final Logger log = LoggerFactory.getLogger(ApprovalExpiryScheduler.class);
    private static final int BATCH_SIZE = 100;

    private final ApprovalService approvalService;

    public ApprovalExpiryScheduler(ApprovalService approvalService) {
        this.approvalService = approvalService;
    }

    @Scheduled(fixedDelayString = "${xwssh.agent.approval-expiry-scan-interval:5s}")
    public void expirePending() {
        for (String approvalId : approvalService.findExpiredPendingIds(BATCH_SIZE)) {
            try {
                approvalService.expire(approvalId);
            } catch (Exception e) {
                log.warn("过期审批处理失败 approvalId={}: {}", approvalId, e.getMessage());
            }
        }
    }
}
