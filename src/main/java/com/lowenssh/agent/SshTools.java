package com.lowenssh.agent;

import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.ssh.ExecResult;
import com.lowenssh.ssh.RemoteFile;
import com.lowenssh.ssh.SshClient;
import com.lowenssh.persistence.AuditService;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

import java.util.List;
import java.util.concurrent.locks.Lock;

/**
 * Agent 的工具集 —— 会话级实例：一个 SshTools 绑定一台已连接的目标机。
 *
 * 为什么不做成 @Service 单例：连接信息是会话级的（"这次会话操作哪台机"），
 * 单例工具没法持有"当前会话的连接"。所以每次发起一轮 agent 任务时 new 一个，
 * 把连好的 SshClient + 本次会话 id + 审计/门禁注进来，loop 结束随会话释放。
 *
 * 审计：execCommand 是真正下发命令的点，在这里记一笔 t_audit（执行点审计）。
 * 能到达这里的命令必经 AgentService.screen 放行，所以危险命令视为已确认。
 *
 * SFTP 工具（listFiles/deleteFile/makeDir/moveFile）走 ChannelSftp。写操作映射成
 * 等价 shell 命令（rm/mkdir/mv）过同一个 CommandGuard：DENY 直接拒，复用现有规则，
 * 审计可读。SFTP 与人工面板共用一条 Session，操作在 lock 内串行化（lock 可为 null，
 * 同步测试场景独占连接无需锁）。
 */
public class SshTools {

    private final SshClient ssh;
    private final Long sessionId;
    private final AuditService auditService;
    private final CommandGuard guard;
    private final Lock lock;   // 与人工 SFTP/监控串行化，可为 null（独占连接时）

    public SshTools(SshClient ssh, Long sessionId, AuditService auditService, CommandGuard guard) {
        this(ssh, sessionId, auditService, guard, null);
    }

    public SshTools(SshClient ssh, Long sessionId, AuditService auditService, CommandGuard guard, Lock lock) {
        this.ssh = ssh;
        this.sessionId = sessionId;
        this.auditService = auditService;
        this.guard = guard;
        this.lock = lock;
    }

    @Tool(description = "在目标服务器上执行一条 shell 命令，返回标准输出、错误输出和退出码。用于查看系统状态、进程、磁盘等运维操作。")
    public String execCommand(
            @ToolParam(description = "要执行的 shell 命令，例如 'df -h' 或 'ps aux | grep java'") String command) {
        // execCommand 是可写工具：审计要标注危险性。能执行到这说明已过门禁放行，
        // 危险命令（非 ALLOW）视为已确认（confirmed=true）。
        boolean dangerous = guard.evaluate(command).decision() != CommandGuard.Decision.ALLOW;
        return runAndAudit(command, dangerous, dangerous);
    }

    @Tool(description = "读取目标服务器上指定路径的文本文件的完整内容。")
    public String readRemoteFile(
            @ToolParam(description = "远程文件的绝对路径，例如 '/etc/nginx/nginx.conf'") String path) {
        // 只读工具：固定非危险、无需确认。单引号包裹防路径里的空格/特殊字符
        return runAndAudit("cat '" + path + "'", false, false);
    }

    @Tool(description = "读取目标服务器上日志文件的末尾若干行，用于快速查看最新日志。")
    public String tailLog(
            @ToolParam(description = "日志文件的绝对路径，例如 '/var/log/nginx/error.log'") String path,
            @ToolParam(description = "读取末尾的行数，例如 100") int lines) {
        return runAndAudit("tail -n " + lines + " '" + path + "'", false, false);
    }

    // —— SFTP 文件操作工具 ——

    @Tool(description = "列出目标服务器上指定目录的文件和子目录，返回每项的名称、是否目录、大小（字节）和权限。")
    public String listFiles(
            @ToolParam(description = "要列出的目录绝对路径，例如 '/var/log'") String path) {
        return withLock(() -> {
            try {
                List<RemoteFile> files = ssh.listDir(path);
                if (files.isEmpty()) return "（空目录）" + path;
                StringBuilder sb = new StringBuilder("目录 ").append(path).append(" 共 ")
                        .append(files.size()).append(" 项:\n");
                for (RemoteFile f : files) {
                    sb.append(f.isDir() ? "[d] " : "[f] ").append(f.name())
                      .append("  ").append(f.isDir() ? "-" : f.size() + "B")
                      .append("  ").append(f.perms()).append("\n");
                }
                return sb.toString();
            } catch (Exception e) {
                return "列目录失败: " + e.getMessage();
            }
        });
    }

    @Tool(description = "删除目标服务器上的一个文件（不能删目录）。危险操作，会经过安全门禁审查。")
    public String deleteFile(
            @ToolParam(description = "要删除的文件绝对路径，例如 '/tmp/old.log'") String path) {
        // 映射成等价 rm 命令过门禁，复用现有删除规则
        return sftpWrite("rm '" + path + "'", () -> {
            ssh.deleteFile(path);
            return "已删除文件: " + path;
        });
    }

    @Tool(description = "在目标服务器上创建一个目录。会经过安全门禁审查。")
    public String makeDir(
            @ToolParam(description = "要创建的目录绝对路径，例如 '/opt/app/data'") String path) {
        return sftpWrite("mkdir '" + path + "'", () -> {
            ssh.mkdir(path);
            return "已创建目录: " + path;
        });
    }

    @Tool(description = "重命名或移动目标服务器上的文件/目录。会经过安全门禁审查。")
    public String moveFile(
            @ToolParam(description = "源路径绝对路径") String from,
            @ToolParam(description = "目标路径绝对路径") String to) {
        return sftpWrite("mv '" + from + "' '" + to + "'", () -> {
            ssh.rename(from, to);
            return "已移动: " + from + " -> " + to;
        });
    }

    /**
     * SFTP 写操作统一入口：先把等价 shell 命令过 CommandGuard，DENY 直接拒绝（复刻线上
     * AutoConfirmationHandler 语义：ASK 自动放行）。放行后在 lock 内执行 SFTP 动作并落审计。
     */
    private String sftpWrite(String equivCommand, SftpAction action) {
        CommandGuard.Verdict verdict = guard.evaluate(equivCommand);
        if (verdict.decision() == CommandGuard.Decision.DENY) {
            auditService.logBlocked(sessionId, equivCommand, true, "DENY: " + verdict.reason());
            return "操作被安全门禁拒绝（" + verdict.reason() + "）。请改用更安全的方式或询问用户。";
        }
        boolean dangerous = verdict.decision() != CommandGuard.Decision.ALLOW;
        return withLock(() -> {
            try {
                String msg = action.run();
                // SFTP 无 shell exitCode，成功即 0、失败走 catch
                auditService.logExecuted(sessionId, equivCommand,
                        new ExecResult(msg, "", 0), dangerous, dangerous);
                return msg;
            } catch (Exception e) {
                auditService.logExecuted(sessionId, equivCommand,
                        new ExecResult("", e.getMessage(), 1), dangerous, dangerous);
                return "操作失败: " + e.getMessage();
            }
        });
    }

    /** 在 lock 内执行（lock 为 null 时直接执行），与人工 SFTP/监控串行化共用一条 Session */
    private String withLock(java.util.function.Supplier<String> body) {
        if (lock == null) return body.get();
        lock.lock();
        try {
            return body.get();
        } finally {
            lock.unlock();
        }
    }

    /** SFTP 动作：可抛异常，返回成功描述 */
    @FunctionalInterface
    private interface SftpAction {
        String run() throws Exception;
    }

    /**
     * 执行命令 → 落审计 → 把三件套格式化成文本喂回模型。
     * 模型靠这段文本判断命令成败、决定下一步，所以 exitCode 和 stderr 都要明确带上。
     */
    private String runAndAudit(String command, boolean dangerous, boolean confirmed) {
        try {
            ExecResult r = ssh.exec(command);
            auditService.logExecuted(sessionId, command, r, dangerous, confirmed);
            StringBuilder sb = new StringBuilder();
            sb.append("exitCode=").append(r.exitCode()).append("\n");
            if (!r.stdout().isEmpty()) {
                sb.append("stdout:\n").append(r.stdout());
            }
            if (!r.stderr().isEmpty()) {
                sb.append("stderr:\n").append(r.stderr());
            }
            return sb.toString();
        } catch (Exception e) {
            // 工具内部异常不能抛给 loop，要作为"工具结果"回灌，让模型知道这步失败了
            return "命令执行异常: " + e.getMessage();
        }
    }
}
