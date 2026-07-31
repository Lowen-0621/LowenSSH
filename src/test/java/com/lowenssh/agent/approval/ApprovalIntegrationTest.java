package com.lowenssh.agent.approval;

import com.lowenssh.agent.task.AgentStepService;
import com.lowenssh.agent.task.TaskCommandService;
import com.lowenssh.agent.task.TaskEventService;
import com.lowenssh.agent.task.TaskPhase;
import com.lowenssh.agent.task.TaskStatus;
import com.lowenssh.agent.task.TaskTransitionService;
import com.lowenssh.persistence.entity.AgentStepEntity;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static com.lowenssh.agent.approval.ApprovalApiDto.ApprovalView;
import static com.lowenssh.agent.approval.ApprovalApiDto.DecideApprovalRequest;
import static com.lowenssh.agent.task.TaskApiDto.CreateTaskRequest;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:approvaldb;MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE;CASE_INSENSITIVE_IDENTIFIERS=TRUE",
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
        "xwssh.agent.approval-expiry-scan-interval=1h"
})
class ApprovalIntegrationTest {

    @Autowired
    private TaskCommandService taskService;
    @Autowired
    private TaskTransitionService transitionService;
    @Autowired
    private AgentStepService stepService;
    @Autowired
    private ApprovalService approvalService;
    @Autowired
    private ApprovalCoordinator coordinator;
    @Autowired
    private ApprovalDecisionService decisionService;
    @Autowired
    private TaskEventService eventService;
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
    void 审批请求持久化并产生approvalRequired事件且approvalId稳定() {
        ApprovalRequest request = prepareApproval(Duration.ofMinutes(2));

        ApprovalView first = approvalService.request(request);
        ApprovalView second = approvalService.request(request);

        assertThat(second.approvalId()).isEqualTo(first.approvalId());
        assertThat(first.status()).isEqualTo("PENDING");
        assertThat(count("t_agent_approval")).isEqualTo(1);
        assertThat(eventTypes(first.taskId()))
                .containsSequence("task_waiting_approval", "approval_required");
        assertThat(eventTypes(first.taskId()).stream()
                .filter("approval_required"::equals)).hasSize(1);
        assertThat(status(first.taskId())).isEqualTo("WAITING_APPROVAL");
    }

    @Test
    void 批准会唤醒等待中的CompletableFuture且重复审批不重复推进() {
        ApprovalRequest request = prepareApproval(Duration.ofMinutes(2));
        ApprovalView approval = approvalService.request(request);

        CompletableFuture<ApprovalDecision> waiting =
                CompletableFuture.supplyAsync(() -> coordinator.requestAndAwait(request));
        ApprovalDecisionService.DecisionResult first = decisionService.decide(
                approval.approvalId(), "approve-key", new DecideApprovalRequest(true));
        ApprovalDecisionService.DecisionResult replay = decisionService.decide(
                approval.approvalId(), "approve-key", new DecideApprovalRequest(true));
        ApprovalDecisionService.DecisionResult sameDecisionNewKey = decisionService.decide(
                approval.approvalId(), "approve-key-2", new DecideApprovalRequest(true));
        ApprovalDecisionService.DecisionResult conflicting = decisionService.decide(
                approval.approvalId(), "reject-after-approve", new DecideApprovalRequest(false));

        assertThat(waiting.orTimeout(2, TimeUnit.SECONDS).join())
                .isEqualTo(ApprovalDecision.APPROVED);
        assertThat(first.httpStatus()).isEqualTo(200);
        assertThat(replay.httpStatus()).isEqualTo(200);
        assertThat(replay.replayed()).isTrue();
        assertThat(replay.body()).isEqualTo(first.body());
        assertThat(sameDecisionNewKey.httpStatus()).isEqualTo(200);
        assertThat(conflicting.httpStatus()).isEqualTo(409);
        assertThat(conflicting.body().get("code").asText())
                .isEqualTo("APPROVAL_ALREADY_DECIDED");
        assertThat(eventTypes(approval.taskId()).stream()
                .filter("approval_decided"::equals)).hasSize(1);
    }

    @Test
    void 审批先完成再注册Future也不会丢失唤醒() {
        ApprovalRequest request = prepareApproval(Duration.ofMinutes(2));
        ApprovalView approval = approvalService.request(request);
        decisionService.decide(
                approval.approvalId(), "early-approve", new DecideApprovalRequest(true));

        ApprovalDecision decision = coordinator.requestAndAwait(request);

        assertThat(decision).isEqualTo(ApprovalDecision.APPROVED);
    }

    @Test
    void 等待超时会持久化Expired并把任务置为TimedOut() {
        ApprovalRequest request = prepareApproval(Duration.ofMillis(80));
        ApprovalView approval = approvalService.request(request);

        ApprovalDecision decision = coordinator.requestAndAwait(request);

        assertThat(decision).isEqualTo(ApprovalDecision.EXPIRED);
        assertThat(approvalService.get(approval.approvalId()).status()).isEqualTo("EXPIRED");
        assertThat(status(approval.taskId())).isEqualTo("TIMED_OUT");
        assertThat(eventTypes(approval.taskId())).contains("approval_expired", "task_timed_out");
    }

    @Test
    void 多个并发批准请求只有一次状态迁移事件() {
        ApprovalRequest request = prepareApproval(Duration.ofMinutes(2));
        ApprovalView approval = approvalService.request(request);
        ExecutorService pool = Executors.newFixedThreadPool(16);
        try {
            List<CompletableFuture<ApprovalDecisionService.DecisionResult>> futures =
                    new ArrayList<>();
            for (int i = 0; i < 50; i++) {
                int index = i;
                futures.add(CompletableFuture.supplyAsync(() -> decisionService.decide(
                        approval.approvalId(),
                        "parallel-approve-" + index,
                        new DecideApprovalRequest(true)
                ), pool));
            }
            List<ApprovalDecisionService.DecisionResult> results = futures.stream()
                    .map(future -> future.orTimeout(10, TimeUnit.SECONDS).join())
                    .toList();

            assertThat(results).allMatch(result -> result.httpStatus() == 200);
            assertThat(approvalService.get(approval.approvalId()).status()).isEqualTo("APPROVED");
            assertThat(eventTypes(approval.taskId()).stream()
                    .filter("approval_decided"::equals)).hasSize(1);
            assertThat(count("t_agent_approval")).isEqualTo(1);
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void 相同审批幂等键不能改成相反决定() {
        ApprovalRequest request = prepareApproval(Duration.ofMinutes(2));
        ApprovalView approval = approvalService.request(request);
        ApprovalDecisionService.DecisionResult approved = decisionService.decide(
                approval.approvalId(), "same-decision-key", new DecideApprovalRequest(true));

        ApprovalDecisionService.DecisionResult reused = decisionService.decide(
                approval.approvalId(), "same-decision-key", new DecideApprovalRequest(false));

        assertThat(approved.httpStatus()).isEqualTo(200);
        assertThat(reused.httpStatus()).isEqualTo(409);
        assertThat(reused.body().get("code").asText()).isEqualTo("IDEMPOTENCY_KEY_REUSED");
        assertThat(approvalService.get(approval.approvalId()).status()).isEqualTo("APPROVED");
    }

    private ApprovalRequest prepareApproval(Duration timeout) {
        String taskId = taskService.create(
                "task-" + java.util.UUID.randomUUID(),
                new CreateTaskRequest(1L, 2L, "重启 nginx")).response().taskId();
        transitionService.transition(
                taskId, TaskStatus.PLANNING, TaskPhase.PLAN, "task_planning");
        transitionService.transition(
                taskId, TaskStatus.RISK_CHECKING, TaskPhase.RISK_CHECK, "task_risk_checking");
        AgentStepEntity step = stepService.createOrGet(
                taskId,
                "call-" + java.util.UUID.randomUUID(),
                TaskPhase.APPROVE,
                "TOOL_APPROVAL",
                "execCommand",
                "{\"command\":\"systemctl restart nginx\"}",
                "v1"
        );
        return new ApprovalRequest(
                taskId,
                step.getStepId(),
                "MEDIUM",
                "重启服务具有副作用",
                List.of("command_guard.ask", "service.restart"),
                "v1",
                timeout
        );
    }

    private List<String> eventTypes(String taskId) {
        return eventService.replay(taskId, 0).stream()
                .map(event -> event.type())
                .toList();
    }

    private String status(String taskId) {
        return jdbc.queryForObject(
                "SELECT status FROM t_agent_task WHERE task_id = ?",
                String.class,
                taskId
        );
    }

    private long count(String table) {
        Long value = jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Long.class);
        return value == null ? 0 : value;
    }
}
