package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 主机实体 —— 对应 t_host，主机簿里的一台常用服务器。
 *
 * 与 t_session 的关系：一台主机下可有多个历史会话（session.host_id 外键关联），
 * 进入某主机后只看该主机的会话历史（按主机隔离）。
 *
 * passwordEnc 存的是 AES-GCM 密文（CryptoUtil 加密），绝不存明文；
 * 对外 DTO 也不回传密码，只在 connect 时解密用一次。
 */
@Data
@TableName("t_host")
public class HostEntity {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String alias;        // 用户起的别名，如「京东云」，可空
    private String sshHost;      // 驼峰自动映射下划线 ssh_host
    private Integer sshPort;
    private String sshUser;
    private String passwordEnc;  // AES-GCM 密文，对应 password_enc
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
