package com.lowenssh.agent.task;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.AgentService;
import com.lowenssh.agent.SessionManager;
import com.lowenssh.agent.SshTools;
import com.lowenssh.agent.ToolRiskCommand;
import com.lowenssh.agent.approval.PersistentConfirmationHandlerFactory;
import com.lowenssh.agent.approval.ApprovalStatus;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.persistence.AuditService;
import com.lowenssh.persistence.MessageService;
import com.lowenssh.persistence.entity.AgentApprovalEntity;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentApprovalMapper;
import com.lowenssh.persistence.mapper.AgentStepMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import com.lowenssh.ssh.ExecResult;
import com.lowenssh.observability.AgentMetrics;
import jakarta.annotation.PreDestroy;
import org.springframework.stereotype.Service;

import java.util.Set;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static com.lowenssh.agent.task.WorkflowPersistenceService.ExecutionClaim;
import static com.lowenssh.agent.task.WorkflowPersistenceService.ExecutionOutcome;

/**
 * 新版持久化任务的异步入口。
 *
 * HTTP/SSE 线程不执行 Agent Loop；专用工作线程登记运行句柄后，取消信号才能真正传到
 * 模型调用线程和 SSH Channel。仅取消 SSE 订阅不会触碰这里。
 */
@Service
public class TaskWorkflowOrchestrator {

    private static final Pattern EXIT_CODE =
            Pattern.compile("(?m)^exitCode=(-?\\d+)\\s*$");

    private final AgentTaskMapper taskMapper;
    private final AgentStepMapper stepMapper;
    private final AgentApprovalMapper approvalMapper;
    private final TaskTransitionService transitionService;
    private final WorkflowPersistenceService persistence;
    private final TaskRuntimeRegistry runtimeRegistry;
    private final TaskCancellationFinalizer cancellationFinalizer;
    private final SessionManager sessionManager;
    private final AgentService agentService;
    private final PersistentConfirmationHandlerFactory confirmationFactory;
    private final ExecutionSafetyService safetyService;
    private final AuditService auditService;
    private final CommandGuard guard;
    private final ObjectMapper objectMapper;
    private final MessageService messageService;
    private final AgentMetrics metrics;
    private final Set<String> scheduled = ConcurrentHashMap.newKeySet();
    private final ExecutorService workers;

    public TaskWorkflowOrchestrator(
            AgentTaskMapper taskMapper,
            AgentStepMapper stepMapper,
            AgentApprovalMapper approvalMapper,
            TaskTransitionService transitionService,
            WorkflowPersistenceService persistence,
            TaskRuntimeRegistry runtimeRegistry,
            TaskCancellationFinalizer cancellationFinalizer,
            SessionManager sessionManager,
            AgentService agentService,
            PersistentConfirmationHandlerFactory confirmationFactory,
            ExecutionSafetyService safetyService,
            AuditService auditService,
            CommandGuard guard,
            ObjectMapper objectMapper,
            MessageService messageService,
            AgentMetrics metrics) {
        this.taskMapper = taskMapper;
        this.stepMapper = stepMapper;
        this.approvalMapper = approvalMapper;
        this.transitionService = transitionService;
        this.persistence = persistence;
        this.runtimeRegistry = runtimeRegistry;
        this.cancellationFinalizer = cancellationFinalizer;
        this.sessionManager = sessionManager;
        this.agentService = agentService;
        this.confirmationFactory = confirmationFactory;
        this.safetyService = safetyService;
        this.auditService = auditService;
        this.guard = guard;
        this.objectMapper = objectMapper;
        this.messageService = messageService;
        this.metrics = metrics;
        AtomicInteger sequence = new AtomicInteger();
        this.workers = Executors.newFixedThreadPool(2, runnable -> {
            Thread thread = new Thread(runnable,
                    "agent-task-" + sequence.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        });
    }

    /** 返回 false 表示任务已排队/运行，防止幂等重放启动第二份 Loop。 */
    public boolean start(String taskId) {
        return schedule(taskId, RunMode.NORMAL);
    }

    public boolean continueAfterRestart(String taskId) {
        return schedule(taskId, RunMode.CONTINUATION);
    }

    public boolean resumeApprovedStep(String taskId) {
        return schedule(taskId, RunMode.APPROVED_STEP);
    }

    private boolean schedule(String taskId, RunMode mode) {
        if (!scheduled.add(taskId) || runtimeRegistry.isRunning(taskId)) {
            return false;
        }
        workers.execute(() -> run(taskId, mode));
        return true;
    }

    private void run(String taskId, RunMode mode) {
        try (TaskRuntimeRegistry.Registration ignored = runtimeRegistry.register(taskId)) {
            AgentTaskEntity task = taskMapper.selectById(taskId);
            if (task == null) {
                return;
            }
            SessionManager.LiveSession live = task.getSessionId() == null
                    ? null : sessionManager.get(task.getSessionId());
            if (live == null) {
                persistence.fail(
                        taskId, "SSH_SESSION_NOT_AVAILABLE",
                        "任务绑定的 SSH 会话不存在或已过期，请重新连接后创建新任务");
                return;
            }
            runtimeRegistry.bindSsh(taskId, live.ssh());

            SshTools tools = new SshTools(
                    live.ssh(), task.getSessionId(), auditService, guard, live.lock());
            PersistentAgentRunObserver observer = new PersistentAgentRunObserver(
                    taskId, live.ssh(), persistence, safetyService, objectMapper, metrics,
                    runtimeRegistry);
            if (mode == RunMode.APPROVED_STEP) {
                resumeApprovedStep(task, live, tools);
                agentService.continueRun(
                        task.getSessionId(), tools,
                        confirmationFactory.create(taskId), observer);
            } else if (mode == RunMode.CONTINUATION) {
                if (TaskStatus.valueOf(task.getStatus()) == TaskStatus.VERIFYING) {
                    persistence.continueRiskChecking(taskId);
                }
                agentService.continueRun(
                        task.getSessionId(), tools,
                        confirmationFactory.create(taskId), observer);
            } else {
                transitionService.transition(
                        taskId, TaskStatus.PLANNING, TaskPhase.PLAN, "task_planning");
                agentService.run(
                        task.getSessionId(), task.getTaskText(), tools,
                        confirmationFactory.create(taskId), observer);
            }
        } catch (TaskCancelledException | CancellationException e) {
            cancellationFinalizer.finalizeIfCancelling(taskId);
        } catch (DuplicateToolExecutionException e) {
            persistence.needsReview(taskId, e.getMessage());
        } catch (TaskLimitExceededException e) {
            persistence.fail(taskId, e.code(), e.getMessage());
        } catch (RuntimeException e) {
            if (Thread.currentThread().isInterrupted()) {
                cancellationFinalizer.finalizeIfCancelling(taskId);
            } else {
                persistence.fail(taskId, "AGENT_EXECUTION_FAILED", safeMessage(e));
            }
        } finally {
            scheduled.remove(taskId);
            // 如果取消发生在 Loop 两个检查点之间，最后仍收敛持久化状态。
            cancellationFinalizer.finalizeIfCancelling(taskId);
        }
    }

    /**
     * 服务重启后审批已通过但原调用栈丢失：只执行数据库中 READY_TO_EXECUTE 的精确 Step，
     * 仍经过一次执行权 CAS；绝不重新询问模型生成一个“相似命令”代替。
     */
    private void resumeApprovedStep(AgentTaskEntity task,
                                    SessionManager.LiveSession live,
                                    SshTools tools) {
        AgentApprovalEntity approval = approvalMapper.selectLatestByTask(task.getTaskId());
        if (approval == null
                || ApprovalStatus.valueOf(approval.getStatus()) != ApprovalStatus.APPROVED) {
            throw new IllegalStateException("没有可恢复的已批准动作");
        }
        AgentStepEntity step = stepMapper.selectById(approval.getStepId());
        if (step == null || !"READY_TO_EXECUTE".equals(step.getStatus())) {
            throw new DuplicateToolExecutionException(
                    approval.getStepId(), step == null ? "MISSING" : step.getStatus());
        }
        String command = ToolRiskCommand.from(
                step.getToolName(), step.getArgumentsJson(), objectMapper);
        if (command == null) {
            throw new IllegalStateException("待恢复审批 Step 不是有副作用工具");
        }
        CommandGuard.Verdict verdict = new CommandGuard.Verdict(
                CommandGuard.Decision.ASK,
                approval.getReason() == null ? "已持久化审批" : approval.getReason());
        String snapshot = safetyService.snapshot(
                step.getToolName(), command, verdict, live.ssh());
        persistence.beginExecution(
                task.getTaskId(), java.util.List.of(
                        new ExecutionClaim(step.getStepId(), snapshot)));

        String result = invoke(tools, step);
        Integer exitCode = exitCode(result);
        boolean timedOut = result.contains("timedOut=true");
        boolean cancelled = result.contains("cancelled=true");
        boolean truncated = result.contains("truncated=true");
        boolean success = !timedOut && !cancelled
                && (exitCode == null ? !looksFailed(result) : exitCode == 0);
        ExecutionOutcome outcome = new ExecutionOutcome(
                step.getStepId(), success, limit(result, 8_000),
                exitCode, timedOut, cancelled, truncated);
        WorkflowPersistenceService.FinishBatchResult finish =
                persistence.finishExecution(task.getTaskId(), java.util.List.of(outcome));
        messageService.saveToolResult(
                task.getSessionId(), step.getToolCallId(), result);
        if (finish.cancellationRequested()) {
            throw new TaskCancelledException();
        }
        persistence.saveVerification(
                task.getTaskId(), step.getStepId(),
                safetyService.verify(command, verdict, success, live.ssh()));
        persistence.continueRiskChecking(task.getTaskId());
    }

    private String invoke(SshTools tools, AgentStepEntity step) {
        return switch (step.getToolName()) {
            case "execCommand" -> tools.execCommand(argumentText(step.getArgumentsJson(), "command"));
            case "readRemoteFile" -> tools.readRemoteFile(argumentText(step.getArgumentsJson(), "path"));
            case "tailLog" -> tools.tailLog(
                    argumentText(step.getArgumentsJson(), "path"),
                    argumentInt(step.getArgumentsJson(), "lines"));
            case "listFiles" -> tools.listFiles(argumentText(step.getArgumentsJson(), "path"));
            case "deleteFile" -> tools.deleteFile(argumentText(step.getArgumentsJson(), "path"));
            case "makeDir" -> tools.makeDir(argumentText(step.getArgumentsJson(), "path"));
            case "moveFile" -> tools.moveFile(
                    argumentText(step.getArgumentsJson(), "from"),
                    argumentText(step.getArgumentsJson(), "to"));
            default -> throw new IllegalArgumentException(
                    "恢复器不支持工具: " + step.getToolName());
        };
    }

    private String argumentText(String json, String field) {
        try {
            var value = objectMapper.readTree(json).get(field);
            if (value == null || !value.isTextual()) {
                throw new IllegalArgumentException("工具参数缺少 " + field);
            }
            return value.asText();
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            throw new IllegalArgumentException("工具参数 JSON 无法解析", e);
        }
    }

    private int argumentInt(String json, String field) {
        try {
            var value = objectMapper.readTree(json).get(field);
            if (value == null || !value.canConvertToInt()) {
                throw new IllegalArgumentException("工具参数缺少整数 " + field);
            }
            return value.asInt();
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            throw new IllegalArgumentException("工具参数 JSON 无法解析", e);
        }
    }

    private Integer exitCode(String result) {
        Matcher matcher = EXIT_CODE.matcher(result);
        return matcher.find() ? Integer.valueOf(matcher.group(1)) : null;
    }

    private boolean looksFailed(String result) {
        String lower = result.toLowerCase(java.util.Locale.ROOT);
        return lower.contains("失败") || lower.contains("异常") || lower.contains("error");
    }

    private String limit(String result, int maxChars) {
        return result.length() <= maxChars
                ? result : result.substring(0, maxChars) + "…";
    }

    private String safeMessage(Throwable error) {
        return error.getMessage() == null
                ? error.getClass().getSimpleName()
                : error.getMessage();
    }

    @PreDestroy
    public void shutdown() {
        workers.shutdownNow();
    }

    private enum RunMode {
        NORMAL,
        CONTINUATION,
        APPROVED_STEP
    }
}
