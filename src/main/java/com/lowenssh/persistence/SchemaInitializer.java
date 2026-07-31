package com.lowenssh.persistence;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.util.List;

/**
 * 启动时自动建表 + 轻量迁移 —— 让首次部署 / 升级无需手动跑 schema.sql。
 *
 * 做两件事（都幂等，重复启动安全）：
 *  1. CREATE TABLE IF NOT EXISTS：建齐 t_host / t_session / t_message / t_audit。
 *  2. 给 t_session 补 host_id 列（老库没有），并把历史会话按 host/port/user 去重，
 *     自动生成对应主机、回填 host_id —— 老对话不丢，能归到主机簿对应主机下。
 *
 * 为什么不用 Flyway：项目刻意保持轻量（无额外依赖），迁移逻辑简单，手写幂等 SQL 够用。
 * 用 JdbcTemplate 直接执行 DDL；列是否存在查 information_schema，避开 MySQL
 * 不支持「ADD COLUMN IF NOT EXISTS」的问题。
 */
@Component
@ConditionalOnProperty(name = "xwssh.schema.enabled", havingValue = "true", matchIfMissing = true)
public class SchemaInitializer {

    private static final Logger log = LoggerFactory.getLogger(SchemaInitializer.class);
    private final JdbcTemplate jdbc;

    public SchemaInitializer(DataSource dataSource) {
        this.jdbc = new JdbcTemplate(dataSource);
    }

    @jakarta.annotation.PostConstruct
    public void init() {
        createTables();
        migrateHostAuthentication();
        migrateSessionHostId();
    }

    /** 建齐所有表（幂等） */
    private void createTables() {
        jdbc.execute("""
            CREATE TABLE IF NOT EXISTS t_host (
                id           BIGINT       NOT NULL AUTO_INCREMENT,
                alias        VARCHAR(128)          DEFAULT NULL,
                ssh_host     VARCHAR(128) NOT NULL,
                ssh_port     INT                   DEFAULT 22,
                ssh_user     VARCHAR(64)  NOT NULL,
                password_enc VARCHAR(512)          DEFAULT NULL,
                auth_type    VARCHAR(16)  NOT NULL DEFAULT 'PASSWORD',
                private_key_path VARCHAR(1024)      DEFAULT NULL,
                passphrase_enc VARCHAR(512)         DEFAULT NULL,
                created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='主机簿'
            """);
        jdbc.execute("""
            CREATE TABLE IF NOT EXISTS t_session (
                id           BIGINT       NOT NULL AUTO_INCREMENT,
                host_id      BIGINT                DEFAULT NULL,
                title        VARCHAR(255)          DEFAULT NULL,
                ssh_host     VARCHAR(128)          DEFAULT NULL,
                ssh_port     INT                   DEFAULT 22,
                ssh_user     VARCHAR(64)           DEFAULT NULL,
                created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_host (host_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会话'
            """);
        jdbc.execute("""
            CREATE TABLE IF NOT EXISTS t_message (
                id           BIGINT       NOT NULL AUTO_INCREMENT,
                session_id   BIGINT       NOT NULL,
                role         VARCHAR(16)  NOT NULL,
                content      MEDIUMTEXT            DEFAULT NULL,
                tool_calls   MEDIUMTEXT            DEFAULT NULL,
                tool_call_id VARCHAR(64)           DEFAULT NULL,
                created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_session (session_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='对话消息'
            """);
        jdbc.execute("""
            CREATE TABLE IF NOT EXISTS t_audit (
                id           BIGINT       NOT NULL AUTO_INCREMENT,
                session_id   BIGINT       NOT NULL,
                command      TEXT         NOT NULL,
                stdout       MEDIUMTEXT            DEFAULT NULL,
                stderr       MEDIUMTEXT            DEFAULT NULL,
                exit_code    INT                   DEFAULT NULL,
                dangerous    TINYINT      NOT NULL DEFAULT 0,
                confirmed    TINYINT      NOT NULL DEFAULT 0,
                created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_session (session_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='命令执行审计'
            """);
        createAgentWorkflowTables();
    }

    /** 老库补齐密码/私钥认证字段；已有主机默认沿用 PASSWORD。 */
    private void migrateHostAuthentication() {
        if (!columnExists("t_host", "auth_type")) {
            jdbc.execute("""
                    ALTER TABLE t_host
                    ADD COLUMN auth_type VARCHAR(16) NOT NULL DEFAULT 'PASSWORD'
                    AFTER password_enc
                    """);
        }
        if (!columnExists("t_host", "private_key_path")) {
            jdbc.execute("""
                    ALTER TABLE t_host
                    ADD COLUMN private_key_path VARCHAR(1024) DEFAULT NULL
                    AFTER auth_type
                    """);
        }
        if (!columnExists("t_host", "passphrase_enc")) {
            jdbc.execute("""
                    ALTER TABLE t_host
                    ADD COLUMN passphrase_enc VARCHAR(512) DEFAULT NULL
                    AFTER private_key_path
                    """);
        }
    }

    /** 建立 Agent 状态机、审批、事件与幂等表。 */
    private void createAgentWorkflowTables() {
        jdbc.execute("""
            CREATE TABLE IF NOT EXISTS t_agent_task (
                task_id               CHAR(36)      NOT NULL,
                session_id            BIGINT                 DEFAULT NULL,
                host_id               BIGINT                 DEFAULT NULL,
                request_hash          CHAR(64)      NOT NULL,
                task_text             TEXT          NOT NULL,
                status                VARCHAR(32)   NOT NULL,
                phase                 VARCHAR(32)   NOT NULL,
                cancel_requested      TINYINT       NOT NULL DEFAULT 0,
                deadline_at           DATETIME(6)            DEFAULT NULL,
                model_calls           INT           NOT NULL DEFAULT 0,
                tool_calls            INT           NOT NULL DEFAULT 0,
                consecutive_failures  INT           NOT NULL DEFAULT 0,
                next_step_sequence    BIGINT        NOT NULL DEFAULT 1,
                next_event_sequence   BIGINT        NOT NULL DEFAULT 1,
                final_summary         MEDIUMTEXT             DEFAULT NULL,
                error_code            VARCHAR(64)            DEFAULT NULL,
                error_message         TEXT                   DEFAULT NULL,
                version               BIGINT        NOT NULL DEFAULT 0,
                started_at            DATETIME(6)            DEFAULT NULL,
                finished_at           DATETIME(6)            DEFAULT NULL,
                created_at            DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                updated_at            DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
                PRIMARY KEY (task_id),
                KEY idx_agent_task_session (session_id),
                KEY idx_agent_task_status (status, updated_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 持久化任务'
            """);
        jdbc.execute("""
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 工作流步骤'
            """);
        jdbc.execute("""
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 人工审批'
            """);
        jdbc.execute("""
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent 可回放事件'
            """);
        jdbc.execute("""
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='HTTP 严格幂等记录'
            """);
    }

    /**
     * 给 t_session 补 host_id 列并迁移老数据。
     * 仅当列不存在时执行加列 + 迁移，已迁移过的库再启动是空操作。
     */
    private void migrateSessionHostId() {
        if (columnExists("t_session", "host_id")) {
            return;  // 新库建表时已带 host_id，或已迁移过，跳过
        }
        log.info("检测到老版 t_session 无 host_id 列，开始迁移历史会话到主机簿…");
        jdbc.execute("ALTER TABLE t_session ADD COLUMN host_id BIGINT DEFAULT NULL AFTER id");
        jdbc.execute("ALTER TABLE t_session ADD KEY idx_host (host_id)");

        // 把历史会话里出现过的 (host,port,user) 去重，每组生成一台主机
        List<java.util.Map<String, Object>> groups = jdbc.queryForList("""
            SELECT ssh_host, ssh_port, ssh_user
            FROM t_session
            WHERE ssh_host IS NOT NULL
            GROUP BY ssh_host, ssh_port, ssh_user
            """);
        int migrated = 0;
        for (var g : groups) {
            String host = (String) g.get("ssh_host");
            Integer port = g.get("ssh_port") == null ? 22 : ((Number) g.get("ssh_port")).intValue();
            String user = (String) g.get("ssh_user");
            // 老会话没存密码，迁移出的主机 password_enc 留空，首次连接时让用户补填
            jdbc.update("INSERT INTO t_host (alias, ssh_host, ssh_port, ssh_user) VALUES (?,?,?,?)",
                    null, host, port, user);
            Long hostId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            jdbc.update("""
                UPDATE t_session SET host_id = ?
                WHERE ssh_host = ? AND ssh_port = ? AND ssh_user = ?
                """, hostId, host, port, user);
            migrated++;
        }
        log.info("历史会话迁移完成，自动生成主机 {} 台", migrated);
    }

    /** 查 information_schema 判断列是否存在 */
    private boolean columnExists(String table, String column) {
        Integer cnt = jdbc.queryForObject("""
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
            """, Integer.class, table, column);
        return cnt != null && cnt > 0;
    }
}
