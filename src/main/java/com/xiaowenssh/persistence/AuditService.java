package com.xiaowenssh.persistence;

import com.xiaowenssh.persistence.entity.AuditEntity;
import com.xiaowenssh.persistence.mapper.AuditMapper;
import com.xiaowenssh.ssh.ExecResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * 审计服务 —— 每条命令落一笔 t_audit，可追溯。Agent 安全卖点的证据链。
 *
 * 记两类：
 *  - 已执行：命令真落到服务器、带 stdout/stderr/exitCode（{@link #logExecuted}）
 *  - 被拦截：deny 拒掉 / ask 被拒，没执行、无结果（{@link #logBlocked}）
 *
 * 铁律：审计失败绝不能拖垮主任务。所有写库 try/catch 兜住，只记日志不抛。
 */
@Service
public class AuditService {

    private static final Logger log = LoggerFactory.getLogger(AuditService.class);

    private final AuditMapper auditMapper;

    public AuditService(AuditMapper auditMapper) {
        this.auditMapper = auditMapper;
    }

    /** 记录一条已执行的命令（带执行结果） */
    public void logExecuted(Long sessionId, String command, ExecResult result,
                            boolean dangerous, boolean confirmed) {
        AuditEntity e = new AuditEntity();
        e.setSessionId(sessionId);
        e.setCommand(command);
        e.setStdout(result.stdout());
        e.setStderr(result.stderr());
        e.setExitCode(result.exitCode());
        e.setDangerous(dangerous);
        e.setConfirmed(confirmed);
        save(e);
    }

    /** 记录一条被门禁拦截 / 用户拒绝的命令（未执行，exitCode 留空，原因记进 stderr） */
    public void logBlocked(Long sessionId, String command, boolean dangerous, String reason) {
        AuditEntity e = new AuditEntity();
        e.setSessionId(sessionId);
        e.setCommand(command);
        e.setStderr(reason);          // 拦截原因借 stderr 字段存，便于审计查阅
        e.setDangerous(dangerous);
        e.setConfirmed(false);        // 被拦截 = 未经确认放行
        save(e);
    }

    private void save(AuditEntity e) {
        try {
            auditMapper.insert(e);
        } catch (Exception ex) {
            // 审计写库失败不影响主流程，只告警
            log.warn("审计写库失败 command={}: {}", e.getCommand(), ex.getMessage());
        }
    }
}
