package com.lowenssh.agent.task;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.ssh.ExecResult;
import com.lowenssh.ssh.SshClient;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static com.lowenssh.agent.task.WorkflowPersistenceService.VerificationRecord;

/**
 * 第一版执行前快照和执行后验证。
 *
 * 只对可安全解析的 systemctl 动作执行额外只读命令；其余 Shell 明确记 UNSUPPORTED，
 * 不伪造“通用 Shell 可以自动快照/回滚”。
 */
@Service
public class ExecutionSafetyService {

    private static final Pattern SYSTEMCTL =
            Pattern.compile("^\\s*systemctl\\s+(restart|stop)\\s+([A-Za-z0-9_.@-]+)\\s*$");

    private final ObjectMapper objectMapper;

    public ExecutionSafetyService(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String snapshot(String toolName,
                           String command,
                           CommandGuard.Verdict verdict,
                           SshClient ssh) {
        if (verdict.decision() == CommandGuard.Decision.ALLOW) {
            return json(Map.of(
                    "status", "NOT_REQUIRED",
                    "reason", "只读/低风险动作不需要回滚快照"));
        }
        Matcher matcher = SYSTEMCTL.matcher(command == null ? "" : command);
        if (matcher.matches()) {
            String service = matcher.group(2);
            try {
                ExecResult state = ssh.exec("systemctl is-active -- " + service);
                return json(Map.of(
                        "status", "CAPTURED",
                        "type", "SYSTEMD_ACTIVE_STATE",
                        "service", service,
                        "activeState", state.stdout().strip(),
                        "exitCode", state.exitCode()
                ));
            } catch (Exception e) {
                return json(Map.of(
                        "status", "FAILED",
                        "type", "SYSTEMD_ACTIVE_STATE",
                        "reason", safeMessage(e)));
            }
        }
        return json(Map.of(
                "status", "UNSUPPORTED",
                "reason", "通用 Shell 动作无法可靠生成执行前快照"));
    }

    public VerificationRecord verify(String command,
                                     CommandGuard.Verdict verdict,
                                     boolean executionSuccess,
                                     SshClient ssh) {
        if (!executionSuccess) {
            return new VerificationRecord(
                    "FAILED",
                    "检查工具退出码、超时和异常标志",
                    "工具执行本身未成功，跳过效果验证",
                    rollbackSuggestion(command));
        }
        if (verdict.decision() == CommandGuard.Decision.ALLOW) {
            return new VerificationRecord(
                    "PASSED",
                    "校验只读工具是否正常返回",
                    "只读动作执行成功，无远端状态变更需要验证",
                    "无需回滚");
        }
        Matcher matcher = SYSTEMCTL.matcher(command == null ? "" : command);
        if (matcher.matches()) {
            String action = matcher.group(1);
            String service = matcher.group(2);
            String expected = "stop".equals(action) ? "inactive" : "active";
            try {
                ExecResult state = ssh.exec("systemctl is-active -- " + service);
                String actual = state.stdout().strip();
                boolean passed = expected.equals(actual);
                return new VerificationRecord(
                        passed ? "PASSED" : "FAILED",
                        "只读执行 systemctl is-active -- " + service,
                        "期望=" + expected + "，实际=" + actual
                                + "，exitCode=" + state.exitCode(),
                        rollbackSuggestion(command));
            } catch (Exception e) {
                return new VerificationRecord(
                        "FAILED",
                        "只读执行 systemctl is-active -- " + service,
                        "验证命令异常: " + safeMessage(e),
                        rollbackSuggestion(command));
            }
        }
        return new VerificationRecord(
                "UNSUPPORTED",
                "仅允许显式、只读验证器",
                "当前动作没有可靠的专用验证器，未自动执行模型生成的验证命令",
                rollbackSuggestion(command));
    }

    private String rollbackSuggestion(String command) {
        return "未自动回滚。如需回退，请根据执行前快照人工确认回滚命令，"
                + "并把该命令作为新动作重新经过 Risk Check/ASK；原命令："
                + (command == null ? "" : command);
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("安全快照序列化失败", e);
        }
    }

    private String safeMessage(Exception e) {
        return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
    }
}
