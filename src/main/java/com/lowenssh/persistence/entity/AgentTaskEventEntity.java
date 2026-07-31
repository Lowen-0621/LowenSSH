package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 可回放的任务领域事件，对应 t_agent_event。 */
@Data
@TableName("t_agent_event")
public class AgentTaskEventEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String taskId;
    private Long sequenceNo;
    private String eventType;
    private String payloadJson;
    private LocalDateTime createdAt;
}
