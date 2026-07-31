package com.lowenssh.agent;

import com.lowenssh.agent.guard.CommandGuard;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.model.ChatResponse;

import java.util.List;
import java.util.concurrent.Future;

/**
 * Agent Loop 的持久化检查点。
 *
 * 默认实现为空，旧同步/SSE 接口行为不变；新版任务编排器用它把模型、风险、执行和验证写入状态机。
 */
public interface AgentRunObserver {

    AgentRunObserver NOOP = new AgentRunObserver() {
    };

    default void beforeModelCall(int round) {
    }

    /** 暴露当前模型调用句柄，使任务取消可以中断实际 HTTP 调用线程。 */
    default void onModelCallStarted(Future<?> modelCall) {
    }

    default void onModelCallFinished(Future<?> modelCall) {
    }

    default void onModelResponse(int round, ChatResponse response) {
    }

    default void onRiskChecked(AssistantMessage.ToolCall call, CommandGuard.Verdict verdict) {
    }

    default void beforeToolExecution(List<AssistantMessage.ToolCall> calls) {
    }

    default void afterToolExecution(List<ToolResponseMessage.ToolResponse> responses) {
    }

    default void onFinalAnswer(String answer) {
    }

    default void onMaxRounds(String summary) {
    }
}
