package com.lowenssh.agent.task;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.LocalDateTime;

/** 对外发送和内部实时发布共用的任务事件视图。 */
public record TaskEventView(
        long id,
        String taskId,
        long sequence,
        String type,
        JsonNode payload,
        LocalDateTime createdAt
) {
}
