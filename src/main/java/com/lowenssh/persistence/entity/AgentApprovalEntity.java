package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 持久化人工审批，对应 t_agent_approval。 */
@Data
@TableName("t_agent_approval")
public class AgentApprovalEntity {

    @TableId(type = IdType.INPUT)
    private String approvalId;
    private String taskId;
    private String stepId;
    private String toolCallId;
    private String actionDigest;
    private String status;
    private String riskLevel;
    private String reason;
    private String matchedRules;
    private LocalDateTime expiresAt;
    private LocalDateTime decidedAt;
    private Long version;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
