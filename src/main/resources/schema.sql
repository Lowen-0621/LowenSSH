-- LowenSSH 建表 SQL（手动执行：mysql -u root -p lowenssh < schema.sql）
-- 库已建：CREATE DATABASE lowenssh DEFAULT CHARACTER SET utf8mb4;
-- 注：应用启动时 SchemaInitializer 会自动跑这些建表/加列，平时无需手动执行此文件。

-- 主机表：主机簿里的一台常用服务器，password_enc 存 AES-GCM 密文
CREATE TABLE IF NOT EXISTS t_host (
    id           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    alias        VARCHAR(128)          DEFAULT NULL COMMENT '主机别名',
    ssh_host     VARCHAR(128) NOT NULL COMMENT '目标服务器 host',
    ssh_port     INT                   DEFAULT 22   COMMENT '端口',
    ssh_user     VARCHAR(64)  NOT NULL COMMENT 'SSH 用户名',
    password_enc VARCHAR(512)          DEFAULT NULL COMMENT 'SSH 密码密文（AES-GCM）',
    auth_type    VARCHAR(16)  NOT NULL DEFAULT 'PASSWORD' COMMENT 'PASSWORD/PRIVATE_KEY',
    private_key_path VARCHAR(1024)      DEFAULT NULL COMMENT '本机私钥路径，不保存私钥正文',
    passphrase_enc VARCHAR(512)         DEFAULT NULL COMMENT '私钥口令密文（AES-GCM）',
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

-- Agent 任务：持久化工作流状态，支持恢复、取消和严格状态迁移
CREATE TABLE IF NOT EXISTS t_agent_task (
    task_id               CHAR(36)      NOT NULL COMMENT '外部任务 UUID',
    session_id            BIGINT                 DEFAULT NULL COMMENT '关联会话',
    host_id               BIGINT                 DEFAULT NULL COMMENT '关联主机',
    request_hash          CHAR(64)      NOT NULL COMMENT '规范化请求 SHA-256',
    task_text             TEXT          NOT NULL COMMENT '用户任务',
    status                VARCHAR(32)   NOT NULL COMMENT '任务状态',
    phase                 VARCHAR(32)   NOT NULL COMMENT '当前工作流阶段',
    cancel_requested      TINYINT       NOT NULL DEFAULT 0 COMMENT '是否请求取消',
    deadline_at           DATETIME(6)            DEFAULT NULL COMMENT '整体任务截止时间',
    model_calls           INT           NOT NULL DEFAULT 0,
    tool_calls            INT           NOT NULL DEFAULT 0,
    consecutive_failures  INT           NOT NULL DEFAULT 0,
    next_step_sequence    BIGINT        NOT NULL DEFAULT 1 COMMENT '下一步骤序号',
    next_event_sequence   BIGINT        NOT NULL DEFAULT 1 COMMENT '下一事件序号',
    final_summary         MEDIUMTEXT             DEFAULT NULL,
    error_code            VARCHAR(64)            DEFAULT NULL,
    error_message         TEXT                   DEFAULT NULL,
    version               BIGINT        NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
    started_at            DATETIME(6)            DEFAULT NULL,
    finished_at           DATETIME(6)            DEFAULT NULL,
    created_at            DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at            DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (task_id),
    KEY idx_agent_task_session (session_id),
    KEY idx_agent_task_status (status, updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 持久化任务';

-- Agent Step：计划、工具执行、验证等每个步骤的持久化检查点
CREATE TABLE IF NOT EXISTS t_agent_step (
    step_id                CHAR(36)      NOT NULL,
    task_id                CHAR(36)      NOT NULL,
    sequence_no            INT           NOT NULL,
    tool_call_id           VARCHAR(128)  NOT NULL,
    phase                  VARCHAR(32)   NOT NULL,
    step_type              VARCHAR(32)   NOT NULL,
    status                 VARCHAR(32)   NOT NULL,
    tool_name              VARCHAR(128)           DEFAULT NULL,
    arguments_json         MEDIUMTEXT             DEFAULT NULL,
    action_digest          CHAR(64)      NOT NULL,
    risk_level             VARCHAR(16)            DEFAULT NULL,
    policy_version         VARCHAR(32)            DEFAULT NULL,
    matched_rules          TEXT                   DEFAULT NULL,
    pre_snapshot           MEDIUMTEXT             DEFAULT NULL,
    result_summary         MEDIUMTEXT             DEFAULT NULL,
    exit_code              INT                    DEFAULT NULL,
    timed_out              TINYINT       NOT NULL DEFAULT 0,
    truncated              TINYINT       NOT NULL DEFAULT 0,
    verification_plan      MEDIUMTEXT             DEFAULT NULL,
    verification_result    MEDIUMTEXT             DEFAULT NULL,
    rollback_suggestion    MEDIUMTEXT             DEFAULT NULL,
    version                BIGINT        NOT NULL DEFAULT 0,
    started_at             DATETIME(6)            DEFAULT NULL,
    finished_at            DATETIME(6)            DEFAULT NULL,
    created_at             DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at             DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (step_id),
    UNIQUE KEY uk_agent_step_action (task_id, tool_call_id, action_digest),
    UNIQUE KEY uk_agent_step_sequence (task_id, sequence_no),
    KEY idx_agent_step_status (task_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 工作流步骤';

-- Agent 审批：Phase 2 使用；现在先固化持久化模型
CREATE TABLE IF NOT EXISTS t_agent_approval (
    approval_id    CHAR(36)      NOT NULL,
    task_id        CHAR(36)      NOT NULL,
    step_id        CHAR(36)      NOT NULL,
    tool_call_id   VARCHAR(128)  NOT NULL,
    action_digest  CHAR(64)      NOT NULL,
    status         VARCHAR(16)   NOT NULL,
    risk_level     VARCHAR(16)            DEFAULT NULL,
    reason         TEXT                   DEFAULT NULL,
    matched_rules  TEXT                   DEFAULT NULL,
    expires_at     DATETIME(6)   NOT NULL,
    decided_at     DATETIME(6)            DEFAULT NULL,
    version        BIGINT        NOT NULL DEFAULT 0,
    created_at     DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at     DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (approval_id),
    UNIQUE KEY uk_agent_approval_action (task_id, tool_call_id, action_digest),
    KEY idx_agent_approval_status (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 人工审批';

-- 任务事件：先落库再推 SSE，id/sequence_no 支持断线续传
CREATE TABLE IF NOT EXISTS t_agent_event (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    task_id      CHAR(36)     NOT NULL,
    sequence_no  BIGINT       NOT NULL,
    event_type   VARCHAR(64)  NOT NULL,
    payload_json MEDIUMTEXT   NOT NULL,
    created_at   DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uk_agent_event_sequence (task_id, sequence_no),
    KEY idx_agent_event_replay (task_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 可回放事件';

-- HTTP 幂等记录：同 scope + key 只能绑定一个请求指纹和一份响应
CREATE TABLE IF NOT EXISTS t_idempotency_record (
    id               BIGINT        NOT NULL AUTO_INCREMENT,
    scope            VARCHAR(32)   NOT NULL,
    idempotency_key  VARCHAR(128)  NOT NULL,
    request_hash     CHAR(64)      NOT NULL,
    resource_id      VARCHAR(64)            DEFAULT NULL,
    response_status  INT                    DEFAULT NULL,
    response_json    MEDIUMTEXT             DEFAULT NULL,
    expires_at       DATETIME(6)   NOT NULL,
    created_at       DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at       DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uk_idempotency_scope_key (scope, idempotency_key),
    KEY idx_idempotency_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='HTTP 严格幂等记录';
