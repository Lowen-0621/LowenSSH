package com.lowenssh.observability;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.ssh.ExecResult;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.stereotype.Component;

import java.time.Duration;

/** 不记录命令正文和密钥，只记录低基数状态/结果标签。 */
@Component
public class AgentMetrics {

    private final MeterRegistry registry;
    private final ObjectMapper objectMapper;

    public AgentMetrics(MeterRegistry registry, ObjectMapper objectMapper) {
        this.registry = registry;
        this.objectMapper = objectMapper;
    }

    public void modelCall(ChatResponse response, Duration duration) {
        registry.counter("lowenssh.agent.model.calls").increment();
        Timer.builder("lowenssh.agent.model.duration")
                .register(registry).record(duration);
        if (response != null && response.getMetadata() != null
                && response.getMetadata().getUsage() != null) {
            var usage = response.getMetadata().getUsage();
            add("lowenssh.agent.tokens.input", usage.getPromptTokens());
            add("lowenssh.agent.tokens.output", usage.getCompletionTokens());
            add("lowenssh.agent.tokens.cached", cachedTokens(usage.getNativeUsage()));
        }
    }

    public void policy(CommandGuard.Verdict verdict) {
        registry.counter(
                "lowenssh.agent.policy.decisions",
                "decision", verdict.decision().name(),
                "risk", verdict.riskLevel().name()).increment();
    }

    public void tool(boolean success, boolean timedOut, boolean cancelled) {
        registry.counter(
                "lowenssh.agent.tool.calls",
                "result", success ? "success" : "failure",
                "timed_out", Boolean.toString(timedOut),
                "cancelled", Boolean.toString(cancelled)).increment();
    }

    public void task(String status, Duration duration) {
        registry.counter("lowenssh.agent.tasks", "status", status).increment();
        Timer.builder("lowenssh.agent.task.duration")
                .tag("status", status)
                .register(registry).record(duration);
    }

    public void ssh(ExecResult result, Throwable error, Duration duration) {
        String outcome = error != null ? "error"
                : result.timedOut() ? "timeout"
                : result.cancelled() ? "cancelled"
                : result.isSuccess() ? "success" : "failure";
        Timer.builder("lowenssh.ssh.command.duration")
                .tag("outcome", outcome)
                .register(registry).record(duration);
        registry.counter("lowenssh.ssh.commands", "outcome", outcome).increment();
    }

    public void contextCompression() {
        registry.counter("lowenssh.agent.context.compressions").increment();
    }

    private void add(String name, Integer value) {
        if (value != null && value > 0) {
            registry.counter(name).increment(value);
        }
    }

    private void add(String name, long value) {
        if (value > 0) {
            registry.counter(name).increment(value);
        }
    }

    /** 兼容 OpenAI/GLM 两种字段命名；读取失败不影响主业务。 */
    private long cachedTokens(Object nativeUsage) {
        if (nativeUsage == null) {
            return 0;
        }
        try {
            var usage = objectMapper.valueToTree(nativeUsage);
            var details = usage.get("promptTokensDetails");
            if (details == null) {
                details = usage.get("prompt_tokens_details");
            }
            if (details == null) {
                return 0;
            }
            var cached = details.get("cachedTokens");
            if (cached == null) {
                cached = details.get("cached_tokens");
            }
            return cached == null ? 0 : cached.asLong();
        } catch (Exception ignored) {
            return 0;
        }
    }
}
