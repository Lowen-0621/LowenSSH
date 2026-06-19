-- XiaowenSSH 建表 SQL（手动执行：mysql -u root -p xiaowenssh < schema.sql）
-- 库已建：CREATE DATABASE xiaowenssh DEFAULT CHARACTER SET utf8mb4;
-- 注：应用启动时 SchemaInitializer 会自动跑这些建表/加列，平时无需手动执行此文件。

-- 主机表：主机簿里的一台常用服务器，password_enc 存 AES-GCM 密文
CREATE TABLE IF NOT EXISTS t_host (
    id           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    alias        VARCHAR(128)          DEFAULT NULL COMMENT '主机别名',
    ssh_host     VARCHAR(128) NOT NULL COMMENT '目标服务器 host',
    ssh_port     INT                   DEFAULT 22   COMMENT '端口',
    ssh_user     VARCHAR(64)  NOT NULL COMMENT 'SSH 用户名',
    password_enc VARCHAR(512)          DEFAULT NULL COMMENT 'SSH 密码密文（AES-GCM）',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='主机簿';

-- 会话表：一次对话 = 一个 session，绑定一台目标服务器（host_id 关联 t_host）
CREATE TABLE IF NOT EXISTS t_session (
    id           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    host_id      BIGINT                DEFAULT NULL COMMENT '所属主机 t_host.id',
    title        VARCHAR(255)          DEFAULT NULL COMMENT '会话标题',
    ssh_host     VARCHAR(128)          DEFAULT NULL COMMENT '目标服务器 host',
    ssh_port     INT                   DEFAULT 22   COMMENT '目标服务器端口',
    ssh_user     VARCHAR(64)           DEFAULT NULL COMMENT 'SSH 用户名',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    KEY idx_host (host_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会话';

-- 消息表：对话历史，agentic loop 的上下文来源
CREATE TABLE IF NOT EXISTS t_message (
    id           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    session_id   BIGINT       NOT NULL COMMENT '所属会话',
    role         VARCHAR(16)  NOT NULL COMMENT '角色: user/assistant/tool/system',
    content      MEDIUMTEXT            DEFAULT NULL COMMENT '消息内容',
    tool_calls   MEDIUMTEXT            DEFAULT NULL COMMENT '工具调用 JSON（assistant 发起时）',
    tool_call_id VARCHAR(64)           DEFAULT NULL COMMENT '工具结果对应的调用 id（role=tool 时）',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    KEY idx_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='对话消息';

-- 审计表：每条实际执行的命令都记一笔，可追溯
CREATE TABLE IF NOT EXISTS t_audit (
    id           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    session_id   BIGINT       NOT NULL COMMENT '所属会话',
    command      TEXT         NOT NULL COMMENT '执行的命令',
    stdout       MEDIUMTEXT            DEFAULT NULL COMMENT '标准输出',
    stderr       MEDIUMTEXT            DEFAULT NULL COMMENT '错误输出',
    exit_code    INT                   DEFAULT NULL COMMENT '退出码',
    dangerous    TINYINT      NOT NULL DEFAULT 0 COMMENT '是否危险命令: 0否 1是',
    confirmed    TINYINT      NOT NULL DEFAULT 0 COMMENT '是否经人工确认: 0否 1是',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '执行时间',
    PRIMARY KEY (id),
    KEY idx_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='命令执行审计';
