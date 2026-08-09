package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 对话消息实体 —— 对应 t_message
 * agentic loop 的上下文就是按 session_id 捞出这张表的历史
 */
@Data
@TableName("t_message")
public class MessageEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long sessionId;
    private String role;        // user / assistant / tool / system
    private String content;
    private String toolCalls;   // assistant 发起工具调用时的 JSON
    private String toolCallId;  // role=tool 时对应的调用 id
    private LocalDateTime createdAt;
}
