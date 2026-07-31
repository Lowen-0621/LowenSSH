package com.lowenssh.agent.task;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.AgentRunObserver;
import com.lowenssh.agent.ToolRiskCommand;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.ssh.SshClient;
import com.lowenssh.observability.AgentMetrics;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.model.ChatResponse;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.time.Duration;
import java.util.concurrent.Future;

import static com.lowenssh.agent.task.WorkflowPersistenceService.ExecutionClaim;
import static com.lowenssh.agent.task.WorkflowPersistenceService.ExecutionOutcome;

/** 把现有 AgentService 的真实执行节点映射到持久化任务/Step/事件。 */
public class PersistentAgentRunObserver implements AgentRunObserver {

    private static final Pattern EXIT_CODE =
            Pattern.compile("(?m)^exitCode=(-?\\d+)\\s*$");

    private final String taskId;
    private final SshClient ssh;
    private final WorkflowPersistenceService persistence;
    private final ExecutionSafetyService safety;
    private final ObjectMapper objectMapper;
    private final AgentMetrics metrics;
    private final TaskRuntimeRegistry runtimeRegistry;
    private final Map<String, StepContext> steps = new LinkedHashMap<>();
    private boolean planRecorded;
    private long modelStartedNanos;
    private final long taskStartedNanos = System.nanoTime();

    public PersistentAgentRunObserver(
            String taskId,
            SshClient ssh,
            WorkflowPersistenceService persistence,
            ExecutionSafetyService safety,
            ObjectMapper objectMapper,
            AgentMetrics metrics,
            TaskRuntimeRegistry runtimeRegistry) {
        this.taskId = taskId;
        this.ssh = ssh;
        this.persistence = persistence;
        this.safety = safety;
        this.objectMapper = objectMapper;
        this.metrics = metrics;
        this.runtimeRegistry = runtimeRegistry;
    }

    @Override
    public void beforeModelCall(int round) {
        modelStartedNanos = System.nanoTime();
        persistence.beforeModelCall(taskId, round);
    }

    @Override
    public void onModelCallStarted(Future<?> modelCall) {
        runtimeRegistry.bindModelCall(taskId, modelCall);
    }

    @Override
    public void onModelCallFinished(Future<?> modelCall) {
        runtimeRegistry.clearModelCall(taskId, modelCall);
    }

    @Override
    public void onModelResponse(int round, ChatResponse response) {
        metrics.modelCall(response, Duration.ofNanos(
                Math.max(0, System.nanoTime() - modelStartedNanos)));
        if (planRecorded) {
            return;
        }
        planRecorded = true;
        persistence.recordPlan(taskId, planJson(round, response));
        if (response != null && response.hasToolCalls()) {
            persistence.continueRiskChecking(taskId);
        }
    }

    @Override
    public void onRiskChecked(AssistantMessage.ToolCall call, CommandGuard.Verdict verdict) {
        metrics.policy(verdict);
        AgentStepEntity step = persistence.recordRisk(
                taskId, call.id(), call.name(), call.arguments(), verdict);
        steps.put(call.id(), new StepContext(
                step.getStepId(), call.name(), call.arguments(),
                ToolRiskCommand.from(call.name(), call.arguments(), objectMapper), verdict));
    }

    @Override
    public void beforeToolExecution(List<AssistantMessage.ToolCall> calls) {
        List<ExecutionClaim> claims = new ArrayList<>();
        for (AssistantMessage.ToolCall call : calls) {
            StepContext context = requireContext(call.id());
            String snapshot = safety.snapshot(
                    context.toolName(), context.command(), context.verdict(), ssh);
            claims.add(new ExecutionClaim(context.stepId(), snapshot));
        }
        persistence.beginExecution(taskId, claims);
    }

    @Override
    public void afterToolExecution(List<ToolResponseMessage.ToolResponse> responses) {
        Map<String, ToolResponseMessage.ToolResponse> byId = new LinkedHashMap<>();
        for (ToolResponseMessage.ToolResponse response : responses) {
            byId.put(response.id(), response);
        }
        List<ExecutionOutcome> outcomes = new ArrayList<>();
        for (Map.Entry<String, StepContext> entry : steps.entrySet()) {
            StepContext context = entry.getValue();
            ToolResponseMessage.ToolResponse response = byId.get(entry.getKey());
            if (response == null) {
                continue;
            }
            String data = unwrap(response.responseData());
            Integer exitCode = exitCode(data);
            boolean timedOut = data.contains("timedOut=true");
            boolean cancelled = data.contains("cancelled=true");
            boolean truncated = data.contains("truncated=true");
            boolean success = !timedOut && !cancelled
                    && (exitCode == null ? !looksFailed(data) : exitCode == 0);
            outcomes.add(new ExecutionOutcome(
                    context.stepId(), success, limit(data, 8_000),
                    exitCode, timedOut, cancelled, truncated));
            metrics.tool(success, timedOut, cancelled);
        }
        WorkflowPersistenceService.FinishBatchResult result =
                persistence.finishExecution(taskId, outcomes);
        if (result.cancellationRequested()) {
            throw new TaskCancelledException();
        }
        for (ExecutionOutcome outcome : outcomes) {
            StepContext context = steps.values().stream()
                    .filter(value -> value.stepId().equals(outcome.stepId()))
                    .findFirst()
                    .orElseThrow();
            persistence.saveVerification(
                    taskId, outcome.stepId(),
                    safety.verify(
                            context.command(), context.verdict(),
                            outcome.success(), ssh));
        }
        if (result.failureLimitReached()) {
            throw new TaskLimitExceededException(
                    "MAX_CONSECUTIVE_FAILURES",
                    "连续工具失败次数已达到上限 " + result.consecutiveFailures());
        }
        persistence.continueRiskChecking(taskId);
    }

    @Override
    public void onFinalAnswer(String answer) {
        persistence.succeed(taskId, answer);
        metrics.task("SUCCEEDED", elapsed());
    }

    @Override
    public void onMaxRounds(String summary) {
        persistence.fail(taskId, "MAX_ROUNDS", summary);
        metrics.task("FAILED", elapsed());
    }

    private Duration elapsed() {
        return Duration.ofNanos(Math.max(0, System.nanoTime() - taskStartedNanos));
    }

    private StepContext requireContext(String toolCallId) {
        StepContext context = steps.get(toolCallId);
        if (context == null) {
            throw new IllegalStateException("Tool Call 缺少 Risk Check: " + toolCallId);
        }
        return context;
    }

    private String planJson(int round, ChatResponse response) {
        List<Map<String, Object>> actions = new ArrayList<>();
        String text = null;
        if (response != null && response.getResult() != null) {
            AssistantMessage output = response.getResult().getOutput();
            text = output.getText();
            for (AssistantMessage.ToolCall call : output.getToolCalls()) {
                actions.add(Map.of(
                        "toolCallId", call.id(),
                        "toolName", call.name(),
                        "arguments", parseJson(call.arguments())
                ));
            }
        }
        Map<String, Object> plan = new LinkedHashMap<>();
        plan.put("round", round);
        plan.put("goal", "完成用户提交的运维任务");
        plan.put("modelExplanation", text == null ? "" : text);
        plan.put("actions", actions);
        plan.put("note", "Plan 只描述意图，不代表执行许可；每个实际 Tool Call 都重新做 Risk Check");
        return toJson(plan);
    }

    private Object parseJson(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (Exception e) {
            return json;
        }
    }

    private String unwrap(String data) {
        if (data == null) {
            return "";
        }
        if (data.startsWith("\"")) {
            try {
                return objectMapper.readValue(data, String.class);
            } catch (Exception ignored) {
                return data;
            }
        }
        return data;
    }

    private Integer exitCode(String data) {
        Matcher matcher = EXIT_CODE.matcher(data);
        return matcher.find() ? Integer.valueOf(matcher.group(1)) : null;
    }

    private boolean looksFailed(String data) {
        String lower = data.toLowerCase(java.util.Locale.ROOT);
        return lower.contains("失败") || lower.contains("异常") || lower.contains("error");
    }

    private String limit(String data, int maxChars) {
        return data.length() <= maxChars ? data : data.substring(0, maxChars) + "…";
    }

    private String toJson(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Plan 序列化失败", e);
        }
    }

    private record StepContext(
            String stepId,
            String toolName,
            String argumentsJson,
            String command,
            CommandGuard.Verdict verdict
    ) {
    }
}
