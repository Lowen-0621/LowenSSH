package com.lowenssh.agent;

import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.ssh.ExecResult;
import com.lowenssh.ssh.SshClient;
import com.lowenssh.persistence.AuditService;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

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
 * 今晚阶段：三个工具全部基于 SshClient.exec 实现（readRemoteFile=cat、
 * tailLog=tail -n），先把 loop 跑通。SFTP（ChannelSftp）留后再换。
 */
public class SshTools {

    private final SshClient ssh;
    private final Long sessionId;
    private final AuditService auditService;
    private final CommandGuard guard;

    public SshTools(SshClient ssh, Long sessionId, AuditService auditService, CommandGuard guard) {
        this.ssh = ssh;
        this.sessionId = sessionId;
        this.auditService = auditService;
        this.guard = guard;
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
