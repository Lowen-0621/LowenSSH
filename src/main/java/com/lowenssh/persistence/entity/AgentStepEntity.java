package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** Agent 工作流中的一个持久化步骤，对应 t_agent_step。 */
@Data
@TableName("t_agent_step")
public class AgentStepEntity {

    @TableId(type = IdType.INPUT)
    private String stepId;
    private String taskId;
    private Integer sequenceNo;
    private String toolCallId;
    private String phase;
    private String stepType;
    private String status;
    private String toolName;
    private String argumentsJson;
    private String actionDigest;
    private String riskLevel;
    private String policyVersion;
    private String matchedRules;
    private String preSnapshot;
    private String resultSummary;
    private Integer exitCode;
    private Boolean timedOut;
    private Boolean truncated;
    private String verificationPlan;
    private String verificationResult;
    private String rollbackSuggestion;
    private Long version;
    private LocalDateTime startedAt;
    private LocalDateTime finishedAt;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
