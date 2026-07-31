package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 持久化 Agent 任务，对应 t_agent_task。 */
@Data
@TableName("t_agent_task")
public class AgentTaskEntity {

    @TableId(type = IdType.INPUT)
    private String taskId;
    private Long sessionId;
    private Long hostId;
    private String requestHash;
    private String taskText;
    private String status;
    private String phase;
    private Boolean cancelRequested;
    private LocalDateTime deadlineAt;
    private Integer modelCalls;
    private Integer toolCalls;
    private Integer consecutiveFailures;
    private Long nextStepSequence;
    private Long nextEventSequence;
    private String finalSummary;
    private String errorCode;
    private String errorMessage;
    private Long version;
    private LocalDateTime startedAt;
    private LocalDateTime finishedAt;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
