package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 会话实体 —— 对应 t_session
 */
@Data
@TableName("t_session")
public class SessionEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long hostId;      // 所属主机（t_host.id），历史按主机隔离的关键
    private String title;
    private String sshHost;   // 驼峰自动映射下划线 ssh_host（MP 默认开启）
    private Integer sshPort;
    private String sshUser;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
