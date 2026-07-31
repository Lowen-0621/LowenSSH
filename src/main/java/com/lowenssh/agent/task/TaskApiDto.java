package com.lowenssh.agent.task;

import java.time.LocalDateTime;

/** 新任务 API 的请求和响应模型。 */
public final class TaskApiDto {

    private TaskApiDto() {
    }

    /**
     * Phase 1 只持久化任务，不保存 SSH 密码。
     * sessionId/hostId 将在后续执行编排阶段用于绑定现有安全连接。
     */
    public record CreateTaskRequest(Long sessionId, Long hostId, String task) {
    }

    public record CreateTaskResponse(
            String taskId,
            String status,
            String phase
    ) {
    }

    public record CancelTaskResponse(
            String taskId,
            String status,
            String phase,
            boolean cancelRequested
    ) {
    }

    public record TaskView(
            String taskId,
            Long sessionId,
            Long hostId,
            String status,
            String phase,
            boolean cancelRequested,
            long version,
            LocalDateTime deadlineAt,
            LocalDateTime createdAt,
            LocalDateTime updatedAt
    ) {
    }

    public record ApiError(String code, String message) {
    }
}
