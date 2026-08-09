package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 命令执行审计实体 —— 对应 t_audit
 * 每条实际下发到服务器的命令都落一笔，可追溯（危险命令、是否人工确认）
 */
@Data
@TableName("t_audit")
public class AuditEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long sessionId;
    private String command;
    private String stdout;
    private String stderr;
    private Integer exitCode;
    private Boolean dangerous;   // TINYINT 0/1 自动映射 Boolean
    private Boolean confirmed;
    private LocalDateTime createdAt;
}
