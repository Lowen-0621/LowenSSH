package com.lowenssh.agent.task;

import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.agent.guard.CommandGuard;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import reactor.core.Disposable;

import static com.lowenssh.agent.task.TaskApiDto.CreateTaskRequest;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Phase 1 数据库验收。
 *
 * H2 使用 MySQL 模式，只替代测试数据库；并发控制仍经过真实 SQL 唯一键、事务和 SELECT FOR UPDATE。
 */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:taskdb;MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;CASE_INSENSITIVE_IDENTIFIERS=TRUE",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.hikari.maximum-pool-size=24",
        "spring.sql.init.mode=always",
        "spring.sql.init.schema-locations=classpath:task-test-schema.sql",
        "spring.ai.openai.api-key=test-key",
        "mybatis-plus.configuration.log-impl=org.apache.ibatis.logging.nologging.NoLoggingImpl",
        "xwssh.schema.enabled=false",
        "xwssh.crypto.allow-insecure-development-key=true",
        "xwssh.agent.idempotency-retention=PT1H",
        "xwssh.agent.task-timeout=PT10M",
        "xwssh.agent.max-tool-calls=2",
        "xwssh.agent.max-consecutive-failures=2"
})
class TaskPersistenceIntegrationTest {

    @Autowired
    private TaskCommandService commandService;

    @Autowired
    private AgentStepService stepService;

    @Autowired
    private TaskEventService eventService;

    @Autowired
    private TaskCancellationService cancellationService;

    @Autowired
    private TaskExecutionBudgetService budgetService;

    @Autowired
    private TaskRuntimeRegistry runtimeRegistry;

    @Autowired
    private TaskCancellationFinalizer cancellationFinalizer;

    @Autowired
    private TaskTimeoutScheduler timeoutScheduler;

    @Autowired
    private TaskTransitionService transitionService;

    @Autowired
    private WorkflowPersistenceService workflowPersistence;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void clean() {
        jdbc.update("DELETE FROM t_agent_event");
        jdbc.update("DELETE FROM t_agent_approval");
        jdbc.update("DELETE FROM t_agent_step");
        jdbc.update("DELETE FROM t_idempotency_record");
        jdbc.update("DELETE FROM t_agent_task");
    }

    @Test
    void 一百个并发相同幂等键只创建一个任务() throws Exception {
        int requests = 100;
        ExecutorService pool = Executors.newFixedThreadPool(20);
        CountDownLatch start = new CountDownLatch(1);
        List<CompletableFuture<TaskCommandService.CreateResult>> futures = new ArrayList<>();

        try {
            for (int i = 0; i < requests; i++) {
                futures.add(CompletableFuture.supplyAsync(() -> {
                    await(start);
                    return commandService.create(
                            "same-create-key",
                            new CreateTaskRequest(1L, 2L, "检查磁盘"));
                }, pool));
            }
            start.countDown();

            List<TaskCommandService.CreateResult> responses = futures.stream()
                    .map(future -> future.orTimeout(20, TimeUnit.SECONDS).join())
                    .toList();
            Set<String> taskIds = responses.stream()
                    .map(result -> result.response().taskId())
                    .collect(java.util.stream.Collectors.toSet());

            assertThat(taskIds).hasSize(1);
            assertThat(responses).filteredOn(result -> !result.replayed()).hasSize(1);
            assertThat(responses).extracting(TaskCommandService.CreateResult::response)
                    .containsOnly(responses.get(0).response());
            assertThat(count("t_agent_task")).isEqualTo(1);
            assertThat(count("t_idempotency_record")).isEqualTo(1);
            assertThat(count("t_agent_event")).isEqualTo(1);
        } finally {
            pool.shutdownNow();
            assertThat(pool.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    @Test
    void 同一个幂等键不能绑定不同请求() {
        commandService.create("conflict-key", new CreateTaskRequest(1L, 2L, "检查磁盘"));

        assertThatThrownBy(() -> commandService.create(
                "conflict-key", new CreateTaskRequest(1L, 2L, "检查内存")))
                .isInstanceOf(IdempotencyConflictException.class);

        assertThat(count("t_agent_task")).isEqualTo(1);
    }

    @Test
    void 相同ToolCall参数字段顺序不同仍复用同一个Step() {
        String taskId = commandService.create(
                "step-key", new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();

        AgentStepEntity first = stepService.createOrGet(
                taskId, "call-1", TaskPhase.EXECUTE, "TOOL",
                "execCommand", "{\"command\":\"df -h\",\"timeout\":30}", "v1");
        AgentStepEntity second = stepService.createOrGet(
                taskId, "call-1", TaskPhase.EXECUTE, "TOOL",
                "execCommand", "{\"timeout\":30,\"command\":\"df -h\"}", "v1");

        assertThat(second.getStepId()).isEqualTo(first.getStepId());
        assertThat(count("t_agent_step")).isEqualTo(1);
    }

    @Test
    void LastEventId只回放之后的事件() {
        String taskId = commandService.create(
                "event-key", new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        TaskEventView first = eventService.replay(taskId, 0).get(0);
        TaskEventView second = eventService.append(taskId, "planning", java.util.Map.of("round", 1));
        TaskEventView third = eventService.append(taskId, "risk_checking", java.util.Map.of("round", 1));

        List<TaskEventView> replayed = eventService.replay(taskId, first.id());

        assertThat(replayed).extracting(TaskEventView::id)
                .containsExactly(second.id(), third.id());
        assertThat(replayed).extracting(TaskEventView::sequence)
                .containsExactly(2L, 3L);
    }

    @Test
    void 新任务持久化整体截止时间() {
        String taskId = commandService.create(
                "deadline-key", new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();

        TaskApiDto.TaskView task = commandService.get(taskId);

        assertThat(task.deadlineAt()).isAfter(task.createdAt().plusMinutes(9));
        assertThat(task.deadlineAt()).isBefore(task.createdAt().plusMinutes(11));
    }

    @Test
    void 取消任务严格幂等且同键不能取消另一个任务() {
        String firstTask = commandService.create(
                "cancel-create-1", new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        String secondTask = commandService.create(
                "cancel-create-2", new CreateTaskRequest(1L, 2L, "检查内存")).response().taskId();

        TaskCancellationService.CancelResult first =
                cancellationService.cancel(firstTask, "cancel-key");
        TaskCancellationService.CancelResult replay =
                cancellationService.cancel(firstTask, "cancel-key");

        assertThat(first.response()).isEqualTo(replay.response());
        assertThat(first.replayed()).isFalse();
        assertThat(replay.replayed()).isTrue();
        assertThat(first.response().status()).isEqualTo(TaskStatus.CANCELLED.name());
        assertThat(first.response().cancelRequested()).isTrue();
        assertThatThrownBy(() -> cancellationService.cancel(secondTask, "cancel-key"))
                .isInstanceOf(IdempotencyConflictException.class);
        assertThat(eventService.replay(firstTask, 0))
                .extracting(TaskEventView::type)
                .containsExactly("task_created", "task_cancelling", "task_cancelled");
    }

    @Test
    void 五十个并发取消请求只推进一次状态() throws Exception {
        String taskId = commandService.create(
                "concurrent-cancel-create",
                new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        int requests = 50;
        ExecutorService pool = Executors.newFixedThreadPool(16);
        CountDownLatch start = new CountDownLatch(1);
        List<CompletableFuture<TaskCancellationService.CancelResult>> futures =
                new ArrayList<>();

        try {
            for (int i = 0; i < requests; i++) {
                futures.add(CompletableFuture.supplyAsync(() -> {
                    await(start);
                    return cancellationService.cancel(taskId, "same-cancel-key");
                }, pool));
            }
            start.countDown();
            List<TaskCancellationService.CancelResult> results = futures.stream()
                    .map(future -> future.orTimeout(20, TimeUnit.SECONDS).join())
                    .toList();

            assertThat(results).filteredOn(result -> !result.replayed()).hasSize(1);
            assertThat(results).extracting(TaskCancellationService.CancelResult::response)
                    .containsOnly(results.get(0).response());
            assertThat(eventService.replay(taskId, 0))
                    .extracting(TaskEventView::type)
                    .containsExactly("task_created", "task_cancelling", "task_cancelled");
        } finally {
            pool.shutdownNow();
            assertThat(pool.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    @Test
    void 工具次数和连续失败上限持久化且成功会清零失败次数() {
        String taskId = commandService.create(
                "budget-key", new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();

        assertThat(budgetService.acquireToolCall(taskId).toolCalls()).isEqualTo(1);
        assertThat(budgetService.recordToolResult(taskId, false).consecutiveFailures()).isEqualTo(1);
        assertThat(budgetService.recordToolResult(taskId, true).consecutiveFailures()).isZero();
        assertThat(budgetService.acquireToolCall(taskId).toolCalls()).isEqualTo(2);
        assertThatThrownBy(() -> budgetService.acquireToolCall(taskId))
                .isInstanceOf(TaskLimitExceededException.class)
                .extracting("code")
                .isEqualTo("MAX_TOOL_CALLS");

        assertThat(budgetService.recordToolResult(taskId, false).consecutiveFailures()).isEqualTo(1);
        assertThatThrownBy(() -> budgetService.recordToolResult(taskId, false))
                .isInstanceOf(TaskLimitExceededException.class)
                .extracting("code")
                .isEqualTo("MAX_CONSECUTIVE_FAILURES");
        Integer failures = jdbc.queryForObject(
                "SELECT consecutive_failures FROM t_agent_task WHERE task_id = ?",
                Integer.class, taskId);
        assertThat(failures).isEqualTo(2);
    }

    @Test
    void 运行中任务先进入Cancelling并在工作线程停止后进入Cancelled() throws Exception {
        String taskId = commandService.create(
                "running-cancel-create",
                new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        CountDownLatch registered = new CountDownLatch(1);
        CountDownLatch stopped = new CountDownLatch(1);
        Thread worker = new Thread(() -> {
            try (TaskRuntimeRegistry.Registration ignored = runtimeRegistry.register(taskId)) {
                registered.countDown();
                try {
                    Thread.sleep(30_000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            } finally {
                cancellationFinalizer.finalizeIfCancelling(taskId);
                stopped.countDown();
            }
        });
        worker.start();
        assertThat(registered.await(2, TimeUnit.SECONDS)).isTrue();

        TaskCancellationService.CancelResult response =
                cancellationService.cancel(taskId, "running-cancel-key");

        assertThat(response.response().status()).isEqualTo(TaskStatus.CANCELLING.name());
        assertThat(stopped.await(3, TimeUnit.SECONDS)).isTrue();
        worker.join(2_000);
        assertThat(commandService.get(taskId).status()).isEqualTo(TaskStatus.CANCELLED.name());
        assertThat(eventService.replay(taskId, 0))
                .extracting(TaskEventView::type)
                .containsExactly("task_created", "task_cancelling", "task_cancelled");
    }

    @Test
    void 整体截止时间扫描会持久化TimedOut() {
        String taskId = commandService.create(
                "timeout-create",
                new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        jdbc.update("UPDATE t_agent_task SET deadline_at = DATEADD('SECOND', -1, CURRENT_TIMESTAMP) "
                + "WHERE task_id = ?", taskId);

        timeoutScheduler.expireOverdueTasks();

        assertThat(commandService.get(taskId).status()).isEqualTo(TaskStatus.TIMED_OUT.name());
        assertThat(eventService.replay(taskId, 0))
                .extracting(TaskEventView::type)
                .containsExactly("task_created", "task_timed_out");
    }

    @Test
    void 断开Sse订阅不会取消后台任务() {
        String taskId = commandService.create(
                "sse-dispose-create",
                new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();

        Disposable subscription = eventService.stream(taskId, 0).subscribe();
        subscription.dispose();

        TaskApiDto.TaskView task = commandService.get(taskId);
        assertThat(task.status()).isEqualTo(TaskStatus.CREATED.name());
        assertThat(task.cancelRequested()).isFalse();
    }

    @Test
    void 完整工作流按PlanRiskExecuteVerifySummary持久化() {
        String taskId = commandService.create(
                "workflow-create",
                new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        transitionService.transition(
                taskId, TaskStatus.PLANNING, TaskPhase.PLAN, "task_planning");
        workflowPersistence.beforeModelCall(taskId, 1);
        workflowPersistence.recordPlan(
                taskId, "{\"goal\":\"检查磁盘\",\"actions\":[\"df -h\"]}");
        workflowPersistence.continueRiskChecking(taskId);
        AgentStepEntity step = workflowPersistence.recordRisk(
                taskId, "tool-1", "execCommand",
                "{\"command\":\"df -h\"}",
                new CommandGuard.Verdict(
                        CommandGuard.Decision.ALLOW, "只读命令"));

        workflowPersistence.beginExecution(
                taskId, List.of(new WorkflowPersistenceService.ExecutionClaim(
                        step.getStepId(), "{\"status\":\"NOT_REQUIRED\"}")));
        WorkflowPersistenceService.FinishBatchResult finish =
                workflowPersistence.finishExecution(
                        taskId, List.of(new WorkflowPersistenceService.ExecutionOutcome(
                                step.getStepId(), true,
                                "exitCode=0\nstdout:\n/dev/sda 40%",
                                0, false, false, false)));
        workflowPersistence.saveVerification(
                taskId, step.getStepId(),
                new WorkflowPersistenceService.VerificationRecord(
                        "PASSED", "检查退出码", "只读命令成功", "无需回滚"));
        workflowPersistence.continueRiskChecking(taskId);
        workflowPersistence.succeed(taskId, "磁盘使用率 40%");

        assertThat(finish.failureLimitReached()).isFalse();
        TaskApiDto.TaskView task = commandService.get(taskId);
        assertThat(task.status()).isEqualTo(TaskStatus.SUCCEEDED.name());
        assertThat(task.phase()).isEqualTo(TaskPhase.SUMMARY.name());
        assertThat(jdbc.queryForObject(
                "SELECT model_calls FROM t_agent_task WHERE task_id = ?",
                Integer.class, taskId)).isEqualTo(1);
        assertThat(jdbc.queryForObject(
                "SELECT tool_calls FROM t_agent_task WHERE task_id = ?",
                Integer.class, taskId)).isEqualTo(1);
        AgentStepEntity persisted = jdbc.queryForObject(
                "SELECT step_id FROM t_agent_step WHERE step_id = ?",
                (rs, rowNum) -> {
                    AgentStepEntity entity = new AgentStepEntity();
                    entity.setStepId(rs.getString(1));
                    return entity;
                }, step.getStepId());
        assertThat(persisted).isNotNull();
        assertThat(jdbc.queryForObject(
                "SELECT verification_result FROM t_agent_step WHERE step_id = ?",
                String.class, step.getStepId())).isEqualTo("只读命令成功");
        assertThat(eventService.replay(taskId, 0))
                .extracting(TaskEventView::type)
                .containsSubsequence(
                        "task_planning", "model_call_started", "plan_created",
                        "task_risk_checking", "risk_checked", "task_executing",
                        "tool_execution_finished", "task_verifying",
                        "step_verified", "task_risk_checking",
                        "task_summarizing", "task_succeeded");
    }

    @Test
    void 已执行Step不能重放且预算计数整体回滚() {
        String taskId = commandService.create(
                "no-replay-create",
                new CreateTaskRequest(1L, 2L, "检查磁盘")).response().taskId();
        transitionService.transition(
                taskId, TaskStatus.PLANNING, TaskPhase.PLAN, "task_planning");
        workflowPersistence.recordPlan(taskId, "{\"goal\":\"检查磁盘\"}");
        workflowPersistence.continueRiskChecking(taskId);
        AgentStepEntity step = workflowPersistence.recordRisk(
                taskId, "tool-no-replay", "execCommand",
                "{\"command\":\"df -h\"}",
                new CommandGuard.Verdict(CommandGuard.Decision.ALLOW, "只读"));
        WorkflowPersistenceService.ExecutionClaim claim =
                new WorkflowPersistenceService.ExecutionClaim(step.getStepId(), "{}");
        workflowPersistence.beginExecution(taskId, List.of(claim));
        workflowPersistence.finishExecution(
                taskId, List.of(new WorkflowPersistenceService.ExecutionOutcome(
                        step.getStepId(), true, "exitCode=0", 0,
                        false, false, false)));
        workflowPersistence.continueRiskChecking(taskId);

        assertThatThrownBy(() ->
                workflowPersistence.beginExecution(taskId, List.of(claim)))
                .isInstanceOf(DuplicateToolExecutionException.class);
        assertThat(jdbc.queryForObject(
                "SELECT tool_calls FROM t_agent_task WHERE task_id = ?",
                Integer.class, taskId)).isEqualTo(1);
    }

    private long count(String table) {
        Long value = jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Long.class);
        return value == null ? 0 : value;
    }

    private static void await(CountDownLatch latch) {
        try {
            if (!latch.await(Duration.ofSeconds(5).toMillis(), TimeUnit.MILLISECONDS)) {
                throw new IllegalStateException("并发测试启动超时");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("并发测试被中断", e);
        }
    }
}
