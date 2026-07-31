package com.lowenssh.agent.task;

import com.lowenssh.agent.SessionManager;
import com.lowenssh.agent.approval.ApprovalDecisionService;
import com.lowenssh.agent.approval.ApprovalApiDto;
import com.lowenssh.agent.approval.ApprovalRequest;
import com.lowenssh.agent.approval.ApprovalService;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.persistence.AuditService;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.ssh.SshClient;
import com.lowenssh.ssh.ExecResult;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.metadata.ChatGenerationMetadata;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.openai.OpenAiChatModel;
import org.springframework.ai.model.tool.ToolCallingManager;
import org.springframework.ai.model.tool.ToolExecutionResult;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.jdbc.core.JdbcTemplate;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.time.Duration;
import java.util.List;
import java.util.Map;

import static com.lowenssh.agent.task.TaskApiDto.CreateTaskRequest;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** 新任务 API 后台编排的无工具主流程验收，不调用真实模型或真实 SSH。 */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:workflowdb;MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;CASE_INSENSITIVE_IDENTIFIERS=TRUE",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.sql.init.mode=always",
        "spring.sql.init.schema-locations=classpath:task-test-schema.sql",
        "spring.ai.openai.api-key=test-key",
        "mybatis-plus.configuration.log-impl=org.apache.ibatis.logging.nologging.NoLoggingImpl",
        "xwssh.schema.enabled=false",
        "xwssh.crypto.allow-insecure-development-key=true"
})
class TaskWorkflowOrchestratorIntegrationTest {

    @MockBean
    private OpenAiChatModel chatModel;

    @MockBean
    private com.lowenssh.persistence.MessageService messageService;

    @MockBean
    private ToolCallingManager toolCallingManager;

    @MockBean
    private AuditService auditService;

    @Autowired
    private TaskCommandService commandService;

    @Autowired
    private TaskWorkflowOrchestrator orchestrator;

    @Autowired
    private TaskEventService eventService;

    @Autowired
    private SessionManager sessionManager;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ApprovalDecisionService approvalDecisionService;

    @Autowired
    private ApprovalService approvalService;

    @Autowired
    private WorkflowPersistenceService workflowPersistence;

    @Autowired
    private TaskTransitionService transitionService;

    @Autowired
    private TaskRecoveryScheduler recoveryScheduler;

    @BeforeEach
    void clean() throws Exception {
        jdbc.update("DELETE FROM t_agent_event");
        jdbc.update("DELETE FROM t_agent_approval");
        jdbc.update("DELETE FROM t_agent_step");
        jdbc.update("DELETE FROM t_idempotency_record");
        jdbc.update("DELETE FROM t_agent_task");
        liveSessions().clear();
        when(messageService.loadHistory(any())).thenReturn(List.of());
    }

    @Test
    void 无工具任务会按Plan和Summary完成且重复启动被拒绝() throws Exception {
        long sessionId = 42L;
        injectLiveSession(sessionId);
        when(chatModel.call(any(Prompt.class))).thenReturn(new ChatResponse(List.of(
                new Generation(
                        new AssistantMessage("磁盘状态正常"),
                        ChatGenerationMetadata.NULL))));
        String taskId = commandService.create(
                "workflow-orchestrator-create",
                new CreateTaskRequest(sessionId, 2L, "检查磁盘")).response().taskId();

        assertThat(orchestrator.start(taskId)).isTrue();
        assertThat(orchestrator.start(taskId)).isFalse();
        awaitTerminal(taskId);

        TaskApiDto.TaskView task = commandService.get(taskId);
        assertThat(task.status()).isEqualTo(TaskStatus.SUCCEEDED.name());
        assertThat(task.phase()).isEqualTo(TaskPhase.SUMMARY.name());
        assertThat(eventService.replay(taskId, 0))
                .extracting(TaskEventView::type)
                .containsSubsequence(
                        "task_created", "task_planning", "model_call_started",
                        "plan_created", "task_summarizing", "task_succeeded");
    }

    @Test
    void Ask任务等待审批后从原调用点恢复执行并完成() throws Exception {
        long sessionId = 43L;
        SshClient ssh = injectLiveSession(sessionId);
        when(ssh.exec("systemctl is-active -- nginx"))
                .thenReturn(new ExecResult("active\n", "", 0));
        ChatResponse toolCall = toolCallResponse(
                "approval-call-1", "systemctl restart nginx");
        when(chatModel.call(any(Prompt.class)))
                .thenReturn(toolCall)
                .thenReturn(new ChatResponse(List.of(
                        new Generation(
                                new AssistantMessage("nginx 已重启并验证为 active"),
                                ChatGenerationMetadata.NULL))));
        ToolExecutionResult execution = mock(ToolExecutionResult.class);
        when(execution.conversationHistory()).thenReturn(List.<Message>of(
                ToolResponseMessage.builder()
                        .responses(List.of(new ToolResponseMessage.ToolResponse(
                                "approval-call-1", "execCommand",
                                "exitCode=0\nstdout:\nrestarted")))
                        .build()));
        when(toolCallingManager.executeToolCalls(any(), any())).thenReturn(execution);

        String taskId = commandService.create(
                "ask-workflow-create",
                new CreateTaskRequest(sessionId, 2L, "重启 nginx")).response().taskId();
        assertThat(orchestrator.start(taskId)).isTrue();
        awaitStatus(taskId, TaskStatus.WAITING_APPROVAL);
        String approvalId = jdbc.queryForObject(
                "SELECT approval_id FROM t_agent_approval WHERE task_id = ?",
                String.class, taskId);

        ApprovalDecisionService.DecisionResult decision =
                approvalDecisionService.decide(
                        approvalId, "approve-workflow-key",
                        new ApprovalApiDto.DecideApprovalRequest(true));
        awaitTerminal(taskId);

        assertThat(decision.httpStatus()).isEqualTo(200);
        assertThat(commandService.get(taskId).status())
                .isEqualTo(TaskStatus.SUCCEEDED.name());
        assertThat(eventService.replay(taskId, 0))
                .extracting(TaskEventView::type)
                .containsSubsequence(
                        "risk_checked", "task_waiting_approval",
                        "approval_required", "approval_decided",
                        "task_approval_granted", "task_executing",
                        "tool_execution_finished", "task_verifying",
                        "step_verified", "task_succeeded");
        assertThat(jdbc.queryForObject(
                "SELECT status FROM t_agent_step WHERE tool_call_id = ?",
                String.class, "approval-call-1")).isEqualTo("EXECUTED");
    }

    @Test
    void 服务重启后已批准Step按数据库精确参数恢复且只执行一次() throws Exception {
        long sessionId = 44L;
        SshClient ssh = injectLiveSession(sessionId);
        when(ssh.exec("systemctl is-active -- nginx"))
                .thenReturn(new ExecResult("active\n", "", 0));
        when(ssh.exec("systemctl restart nginx"))
                .thenReturn(new ExecResult("restarted\n", "", 0));
        when(chatModel.call(any(Prompt.class))).thenReturn(new ChatResponse(List.of(
                new Generation(
                        new AssistantMessage("恢复后的 nginx 状态为 active"),
                        ChatGenerationMetadata.NULL))));

        String taskId = commandService.create(
                "restart-recovery-create",
                new CreateTaskRequest(sessionId, 2L, "重启 nginx")).response().taskId();
        transitionService.transition(
                taskId, TaskStatus.PLANNING, TaskPhase.PLAN, "task_planning");
        workflowPersistence.recordPlan(taskId, "{\"goal\":\"重启 nginx\"}");
        workflowPersistence.continueRiskChecking(taskId);
        AgentStepEntity step = workflowPersistence.recordRisk(
                taskId, "restart-call-1", "execCommand",
                "{\"command\":\"systemctl restart nginx\"}",
                new CommandGuard.Verdict(
                        CommandGuard.Decision.ASK, "重启服务需要审批"));
        String approvalId = approvalService.request(new ApprovalRequest(
                taskId, step.getStepId(), "MEDIUM", "重启服务需要审批",
                List.of("command_guard.ask"), "v1", Duration.ofMinutes(2)))
                .approvalId();
        approvalDecisionService.decide(
                approvalId, "restart-recovery-approve",
                new ApprovalApiDto.DecideApprovalRequest(true));

        recoveryScheduler.recover();
        awaitTerminal(taskId);

        assertThat(commandService.get(taskId).status())
                .isEqualTo(TaskStatus.SUCCEEDED.name());
        verify(ssh, times(1)).exec("systemctl restart nginx");
        assertThat(jdbc.queryForObject(
                "SELECT status FROM t_agent_step WHERE step_id = ?",
                String.class, step.getStepId())).isEqualTo("EXECUTED");
    }

    @Test
    void 重启时Executing动作进入NeedsReview绝不自动重放() throws Exception {
        long sessionId = 45L;
        SshClient ssh = injectLiveSession(sessionId);
        String taskId = commandService.create(
                "uncertain-recovery-create",
                new CreateTaskRequest(sessionId, 2L, "重启 nginx")).response().taskId();
        transitionService.transition(
                taskId, TaskStatus.PLANNING, TaskPhase.PLAN, "task_planning");
        workflowPersistence.recordPlan(taskId, "{\"goal\":\"重启 nginx\"}");
        workflowPersistence.continueRiskChecking(taskId);
        AgentStepEntity step = workflowPersistence.recordRisk(
                taskId, "uncertain-call-1", "execCommand",
                "{\"command\":\"systemctl restart nginx\"}",
                new CommandGuard.Verdict(
                        CommandGuard.Decision.ALLOW, "测试执行不确定区"));
        workflowPersistence.beginExecution(
                taskId, List.of(new WorkflowPersistenceService.ExecutionClaim(
                        step.getStepId(), "{\"status\":\"CAPTURED\"}")));

        recoveryScheduler.recover();
        awaitTerminal(taskId);

        assertThat(commandService.get(taskId).status())
                .isEqualTo(TaskStatus.NEEDS_REVIEW.name());
        verify(ssh, times(0)).exec("systemctl restart nginx");
        assertThat(eventService.replay(taskId, 0))
                .extracting(TaskEventView::type)
                .contains("task_needs_review");
    }

    private void awaitTerminal(String taskId) throws InterruptedException {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        while (System.nanoTime() < deadline) {
            if (TaskStatus.valueOf(commandService.get(taskId).status()).isTerminal()) {
                return;
            }
            Thread.sleep(20);
        }
        throw new AssertionError("任务未在 5 秒内进入终态");
    }

    private void awaitStatus(String taskId, TaskStatus expected) throws InterruptedException {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        while (System.nanoTime() < deadline) {
            if (expected.name().equals(commandService.get(taskId).status())) {
                return;
            }
            Thread.sleep(20);
        }
        throw new AssertionError("任务未在 5 秒内进入 " + expected);
    }

    @SuppressWarnings("unchecked")
    private Map<Long, SessionManager.LiveSession> liveSessions() throws Exception {
        Field field = SessionManager.class.getDeclaredField("bySession");
        field.setAccessible(true);
        return (Map<Long, SessionManager.LiveSession>) field.get(sessionManager);
    }

    private SshClient injectLiveSession(long sessionId) throws Exception {
        SshClient ssh = mock(SshClient.class);
        when(ssh.isConnected()).thenReturn(true);
        Constructor<SessionManager.LiveSession> constructor =
                SessionManager.LiveSession.class.getDeclaredConstructor(
                        Long.class, String.class, int.class, String.class, SshClient.class);
        constructor.setAccessible(true);
        SessionManager.LiveSession live =
                constructor.newInstance(2L, "host", 22, "tester", ssh);
        Field id = SessionManager.LiveSession.class.getDeclaredField("sessionId");
        id.setAccessible(true);
        id.set(live, sessionId);
        liveSessions().put(sessionId, live);
        return ssh;
    }

    private ChatResponse toolCallResponse(String callId, String command) {
        AssistantMessage.ToolCall call = new AssistantMessage.ToolCall(
                callId, "function", "execCommand",
                "{\"command\":\"" + command + "\"}");
        AssistantMessage assistant = AssistantMessage.builder()
                .content("")
                .toolCalls(List.of(call))
                .build();
        return new ChatResponse(List.of(
                new Generation(assistant, ChatGenerationMetadata.NULL)));
    }
}
