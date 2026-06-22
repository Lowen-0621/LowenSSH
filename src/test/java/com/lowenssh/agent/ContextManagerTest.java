package com.lowenssh.agent;

import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.metadata.ChatGenerationMetadata;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.openai.OpenAiChatModel;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 上下文管理单测 —— 截断/压缩/配对/熔断是 M3 的硬逻辑，必须覆盖。
 * Layer 0 截断不调模型，chatModel 传 null；Layer 4 压缩用 mock 模拟摘要返回，纯逻辑不连真模型。
 */
class ContextManagerTest {

    // ============================ Layer 0：截断 ============================

    /** 截断不调模型，chatModel 给 null 也能跑 */
    private ContextManager truncator(int maxChars) {
        // old 阈值给同值：旧用例只放单条工具结果、位置都在保留区内，走 recent 分支，old 不生效
        return new ContextManager(null, maxChars, maxChars, 999999, 6, 3);
    }

    /** 造一条工具结果消息 */
    private ToolResponseMessage toolMsg(String id, String name, String data) {
        return ToolResponseMessage.builder()
                .responses(List.of(new ToolResponseMessage.ToolResponse(id, name, data)))
                .build();
    }

    private String toolData(Message msg) {
        return ((ToolResponseMessage) msg).getResponses().get(0).responseData();
    }

    @Test
    void 短工具结果不截断() {
        ContextManager cm = truncator(8000);
        List<Message> in = List.of(toolMsg("1", "execCommand", "磁盘占用 42%"));
        List<Message> out = cm.truncateToolResponses(in);
        assertEquals("磁盘占用 42%", toolData(out.get(0)));
    }

    @Test
    void 超长工具结果截断中段保留头尾() {
        ContextManager cm = truncator(100);
        String big = "H".repeat(80) + "M".repeat(500) + "T".repeat(80);
        List<Message> out = cm.truncateToolResponses(List.of(toolMsg("1", "tailLog", big)));
        String data = toolData(out.get(0));
        // 截断后总长远小于原始；含截断提示；保留了开头的 H 和结尾的 T
        assertTrue(data.length() < big.length(), "应被截短");
        assertTrue(data.contains("已截断"), "应含截断提示");
        assertTrue(data.contains("t_message"), "提示应指向 t_message");
        assertTrue(data.startsWith("H"), "应保留头部");
        assertTrue(data.endsWith("T"), "应保留尾部");
    }

    @Test
    void 截断只动工具结果不动普通消息() {
        ContextManager cm = truncator(50);
        List<Message> in = List.of(
                new SystemMessage("系统提示"),
                new UserMessage("查一下磁盘"),
                toolMsg("1", "execCommand", "X".repeat(500)));
        List<Message> out = cm.truncateToolResponses(in);
        assertEquals("系统提示", out.get(0).getText());
        assertEquals("查一下磁盘", out.get(1).getText());
        assertTrue(toolData(out.get(2)).contains("已截断"));
    }

    @Test
    void 截断幂等再跑结果不变() {
        ContextManager cm = truncator(100);
        List<Message> once = cm.truncateToolResponses(List.of(toolMsg("1", "x", "Z".repeat(800))));
        List<Message> twice = cm.truncateToolResponses(once);
        assertEquals(toolData(once.get(0)), toolData(twice.get(0)));
    }

    @Test
    void 旧工具结果用更小阈值收紧() {
        // 近区大阈值 1000、旧区小阈值 100，keep-recent=2
        ContextManager cm = new ContextManager(null, 1000, 100, 999999, 2, 3);
        String big = "X".repeat(900);
        // 列表：旧工具结果(距末尾4) + 两条占位 + 近工具结果(距末尾1)
        List<Message> in = List.of(
                toolMsg("old", "tailLog", big),
                new UserMessage("中间一"),
                new UserMessage("中间二"),
                toolMsg("new", "tailLog", big));
        List<Message> out = cm.truncateToolResponses(in);
        String oldData = toolData(out.get(0));
        String newData = toolData(out.get(3));
        // 旧的被小阈值截断（含提示且远小于 900）；新的在阈值内不截
        assertTrue(oldData.contains("已截断"), "旧工具结果应被截断");
        assertTrue(oldData.length() < 200, "旧工具结果应收紧到小阈值附近");
        assertEquals(big, newData, "近区工具结果在大阈值内不应被截");
    }

    // ============================ Layer 4：压缩 ============================

    /** 造一个会返回固定摘要文本的 mock 模型 */
    private OpenAiChatModel mockModel(String summary) {
        OpenAiChatModel m = mock(OpenAiChatModel.class);
        ChatResponse resp = new ChatResponse(List.of(
                new Generation(new AssistantMessage(summary), ChatGenerationMetadata.NULL)));
        when(m.call(any(org.springframework.ai.chat.prompt.Prompt.class))).thenReturn(resp);
        return m;
    }

    /** 造一段够长的对话（system + 多轮 user/assistant），确保 token 估算超阈值 */
    private List<Message> longHistory(int rounds) {
        java.util.List<Message> msgs = new java.util.ArrayList<>();
        msgs.add(new SystemMessage("你是运维助手"));
        for (int i = 0; i < rounds; i++) {
            msgs.add(new UserMessage("第" + i + "步：" + "内".repeat(100)));
            msgs.add(new AssistantMessage("回复" + i + "：" + "容".repeat(100)));
        }
        return msgs;
    }

    @Test
    void 未超阈值不压缩() {
        // 阈值设很大，短历史不该触发压缩
        ContextManager cm = new ContextManager(mockModel("摘要"), 8000, 800, 999999, 6, 3);
        List<Message> in = longHistory(2);
        List<Message> out = cm.compressIfNeeded(in);
        assertEquals(in.size(), out.size(), "未超阈值应原样返回");
    }

    @Test
    void 超阈值触发压缩且保留system和最近K条() {
        // 阈值调到 100 token，长历史必然超
        ContextManager cm = new ContextManager(mockModel("【这是早先对话的摘要】"), 8000, 800, 100, 6, 3);
        List<Message> in = longHistory(10);   // 1 system + 20 条
        List<Message> out = cm.compressIfNeeded(in);
        assertTrue(out.size() < in.size(), "应被压缩变短");
        // 第一条仍是 system
        assertTrue(out.get(0) instanceof SystemMessage, "首条应保留 system");
        // 第二条是摘要（UserMessage 含摘要文本）
        assertTrue(out.get(1).getText().contains("早先对话的摘要"), "次条应是摘要");
        // 保留了最近 6 条原文
        assertEquals(6, out.size() - 2, "应保留最近 6 条原文 + system + 摘要");
    }

    @Test
    void 保留区开头是孤儿工具结果时切割点前移保配对() {
        // 构造：system + assistant(tool_call) + tool_result，且 tool_result 恰好落在保留区开头
        AssistantMessage.ToolCall call = new AssistantMessage.ToolCall("c1", "function", "execCommand", "{\"command\":\"df -h\"}");
        java.util.List<Message> msgs = new java.util.ArrayList<>();
        msgs.add(new SystemMessage("系统"));
        // 前面填一堆把 token 撑上去
        for (int i = 0; i < 8; i++) {
            msgs.add(new UserMessage("填充" + "占".repeat(80)));
            msgs.add(new AssistantMessage("回复" + "位".repeat(80)));
        }
        // 末尾一对：assistant 带 tool_call + 对应 tool_result
        msgs.add(AssistantMessage.builder().content("").toolCalls(List.of(call)).build());
        msgs.add(toolMsg("c1", "execCommand", "结果"));

        // keep-recent=1 会让切割点正好落在 tool_result 上 -> 须前移把 assistant 一起留下
        ContextManager cm = new ContextManager(mockModel("摘要"), 8000, 800, 50, 1, 3);
        List<Message> out = cm.compressIfNeeded(msgs);

        // 保留区不能以孤儿 ToolResponseMessage 开头：找到摘要后的第一条原文
        // out = [system, 摘要, ...保留区]，保留区首条不应是 ToolResponseMessage
        Message firstKept = out.get(2);
        assertFalse(firstKept instanceof ToolResponseMessage,
                "保留区开头不能是孤儿 tool_result，切割点应前移到对应 assistant");
    }

    @Test
    void 摘要连续失败达阈值后熔断不再调模型() {
        // mock 模型抛异常模拟摘要失败
        OpenAiChatModel failModel = mock(OpenAiChatModel.class);
        when(failModel.call(any(org.springframework.ai.chat.prompt.Prompt.class)))
                .thenThrow(new RuntimeException("模型挂了"));
        // circuit-limit=3
        ContextManager cm = new ContextManager(failModel, 8000, 800, 100, 6, 3);

        // 前 3 次都会尝试调用并失败
        for (int i = 0; i < 3; i++) {
            cm.compressIfNeeded(longHistory(10));
        }
        // 第 4、5 次应已熔断，不再调模型
        cm.compressIfNeeded(longHistory(10));
        cm.compressIfNeeded(longHistory(10));

        // 总调用次数应恰好 3（熔断后不再调）
        verify(failModel, times(3)).call(any(org.springframework.ai.chat.prompt.Prompt.class));
    }

    @Test
    void 摘要失败时原样返回不丢历史() {
        OpenAiChatModel failModel = mock(OpenAiChatModel.class);
        when(failModel.call(any(org.springframework.ai.chat.prompt.Prompt.class)))
                .thenThrow(new RuntimeException("挂了"));
        ContextManager cm = new ContextManager(failModel, 8000, 800, 100, 6, 3);
        List<Message> in = longHistory(10);
        List<Message> out = cm.compressIfNeeded(in);
        // 摘要失败不能丢历史，必须原样返回
        assertEquals(in.size(), out.size(), "摘要失败应原样返回不丢历史");
    }

    // ============================ token 估算 ============================

    @Test
    void token估算随内容增长() {
        ContextManager cm = truncator(8000);
        int small = cm.estimateTokens(List.of(new UserMessage("短")));
        int big = cm.estimateTokens(List.of(new UserMessage("长".repeat(1000))));
        assertTrue(big > small, "内容越多估算 token 越大");
    }
}
