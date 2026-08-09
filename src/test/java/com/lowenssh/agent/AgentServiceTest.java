package com.lowenssh.agent;

import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.agent.guard.ConfirmationHandler;
import com.lowenssh.persistence.AuditService;
import com.lowenssh.persistence.MessageService;
import com.lowenssh.ssh.SshClient;
import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.metadata.ChatGenerationMetadata;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.model.tool.ToolCallingManager;
import org.springframework.ai.model.tool.ToolExecutionResult;
import org.springframework.ai.openai.OpenAiChatModel;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Agent loop 核心单测 —— 项目卖点是"手写 loop + 安全门禁"，loop 的决策分支必须覆盖：
 *   1. 模型不再调工具 → 给出结论结束
 *   2. DENY 命令 → 不执行、回灌拒绝、loop 继续让模型换方案
 *   3. ASK 命令用户拒绝 → 同 DENY（不执行）
 *   4. ASK 命令用户批准 → 交框架执行
 *   5. MAX_ROUNDS 上限 → 防死循环兜底
 *
 * 全程不连真模型/真 SSH：chatModel、toolCallingManager 用 mock；门禁用真 CommandGuard
 * （它本身已有独立单测，这里用真实判定让用例更接近线上）。
 */
class AgentServiceTest {

    private static final Long SID = 1L;

    // —— 依赖：模型和工具执行器 mock，其余给真实/哑实现 ——
    private final OpenAiChatModel chatModel = mock(OpenAiChatModel.class);
    private final ToolCallingManager toolCallingManager = mock(ToolCallingManager.class);
    private final CommandGuard guard = new CommandGuard();
    private final AuditService auditService = mock(AuditService.class);
    private final MessageService messageService = mock(MessageService.class);
    // ContextManager 用真实对象但阈值设到永不压缩，截断也不影响这里的短消息
    private final ContextManager contextManager = new ContextManager(null, 8000, 800, 999999, 6, 3);

    private final AgentService service = new AgentService(
            chatModel, toolCallingManager, guard, auditService, messageService, contextManager, 15);

    // ToolCallbacks.from(tools) 只反射读 @Tool 注解，不真连 SSH，deps 给 null 即可
    private SshTools tools() {
        return new SshTools(new SshClient(), SID, auditService, guard);
    }

    // —— 造 ChatResponse 的辅助方法 ——

    /** 造一个"模型给出纯文字结论、无 tool_call"的响应 */
    private ChatResponse textResponse(String text) {
        return new ChatResponse(List.of(
                new Generation(new AssistantMessage(text), ChatGenerationMetadata.NULL)));
    }

    /** 造一个"模型要调 execCommand 跑某条命令"的响应。
     *  用 AssistantMessage.builder() 公开 API（1.1.5 带 toolCall 的构造器是 protected）。 */
    private ChatResponse execCallResponse(String callId, String command) {
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

    // ============================ 1. 正常结束 ============================

    @Test
    void 模型不调工具时直接给出结论结束() {
        when(chatModel.call(any(Prompt.class))).thenReturn(textResponse("磁盘还剩 58%，一切正常。"));

        String result = service.run(SID, "看下磁盘", tools(), (cmd, reason) -> true);

        assertEquals("磁盘还剩 58%，一切正常。", result);
        // 没有工具调用，执行器一次都不该被碰
        verify(toolCallingManager, never()).executeToolCalls(any(), any());
    }

    // ============================ 2. DENY 命令被拦 ============================

    @Test
    void DENY命令不执行且回灌拒绝后继续loop() {
        // 第 1 轮：模型想跑 rm -rf /（必被 DENY）；第 2 轮：模型改口给结论
        when(chatModel.call(any(Prompt.class)))
                .thenReturn(execCallResponse("c1", "rm -rf /"))
                .thenReturn(textResponse("好的，我不执行删除操作。"));

        String result = service.run(SID, "清理磁盘", tools(), (cmd, reason) -> true);

        assertEquals("好的，我不执行删除操作。", result);
        // 危险命令绝不能进框架执行
        verify(toolCallingManager, never()).executeToolCalls(any(), any());
        // 拦截点必须落审计
        verify(auditService).logBlocked(eq(SID), eq("rm -rf /"), eq(true), anyString());
    }

    // ============================ 3. ASK 用户拒绝 ============================

    @Test
    void ASK命令用户拒绝则不执行() {
        // systemctl restart 命中 ASK；确认器返回 false（拒绝）
        when(chatModel.call(any(Prompt.class)))
                .thenReturn(execCallResponse("c1", "systemctl restart nginx"))
                .thenReturn(textResponse("已取消重启。"));

        ConfirmationHandler denyAll = (cmd, reason) -> false;
        String result = service.run(SID, "重启nginx", tools(), denyAll);

        assertEquals("已取消重启。", result);
        verify(toolCallingManager, never()).executeToolCalls(any(), any());
    }

    // ============================ 4. ASK 用户批准 → 执行 ============================

    @Test
    void ASK命令用户批准则交框架执行() {
        when(chatModel.call(any(Prompt.class)))
                .thenReturn(execCallResponse("c1", "systemctl restart nginx"))
                .thenReturn(textResponse("nginx 已重启完成。"));

        // 批准后框架执行，返回一段只含工具结果、无新 tool_call 的历史，让下一轮收尾
        ToolExecutionResult execResult = mock(ToolExecutionResult.class);
        when(execResult.conversationHistory()).thenReturn(List.<Message>of(
                ToolResponseMessage.builder()
                        .responses(List.of(new ToolResponseMessage.ToolResponse(
                                "c1", "execCommand", "Job for nginx.service done.")))
                        .build()));
        when(toolCallingManager.executeToolCalls(any(), any())).thenReturn(execResult);

        ConfirmationHandler approveAll = (cmd, reason) -> true;
        String result = service.run(SID, "重启nginx", tools(), approveAll);

        assertEquals("nginx 已重启完成。", result);
        // 批准的命令确实交给框架执行了一次
        verify(toolCallingManager).executeToolCalls(any(), any());
    }

    // ============================ 5. 死循环兜底 ============================

    @Test
    void 模型反复调安全命令达上限则兜底返回() {
        // 每轮都返回一个 ALLOW 命令，永不收尾 → 必然撞 MAX_ROUNDS
        when(chatModel.call(any(Prompt.class)))
                .thenReturn(execCallResponse("c", "ls -al"));

        // ALLOW 命令会进框架执行，给个空历史让 loop 继续转
        ToolExecutionResult execResult = mock(ToolExecutionResult.class);
        when(execResult.conversationHistory()).thenReturn(List.<Message>of());
        when(toolCallingManager.executeToolCalls(any(), any())).thenReturn(execResult);

        String result = service.run(SID, "一直查", tools(), (cmd, reason) -> true);

        assertTrue(result.contains("最大循环轮数"), "撞上限应返回兜底文案，实际：" + result);
    }
}
