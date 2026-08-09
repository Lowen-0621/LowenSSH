package com.lowenssh.persistence;

import com.lowenssh.persistence.entity.MessageEntity;
import com.lowenssh.persistence.mapper.MessageMapper;
import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.MessageType;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * MessageService.loadHistory 单测 —— 多轮对话的核心：把 t_message 还原成
 * Spring AI 的 Message 列表，再回灌给模型。这里重点验证还原规则正确。
 */
class MessageServiceTest {

    /** 造一条 MessageEntity 行 */
    private MessageEntity row(String role, String content, String toolCalls, String toolCallId) {
        MessageEntity e = new MessageEntity();
        e.setRole(role);
        e.setContent(content);
        e.setToolCalls(toolCalls);
        e.setToolCallId(toolCallId);
        return e;
    }

    @SuppressWarnings("unchecked")
    private MessageService serviceReturning(List<MessageEntity> rows) {
        MessageMapper mapper = mock(MessageMapper.class);
        when(mapper.selectList(any())).thenReturn(rows);
        return new MessageService(mapper);
    }

    @Test
    void 空sessionId返回空列表() {
        MessageService svc = serviceReturning(new ArrayList<>());
        assertThat(svc.loadHistory(null)).isEmpty();
    }

    @Test
    void 还原user和assistant纯文字消息() {
        List<MessageEntity> rows = List.of(
                row("user", "看下磁盘", null, null),
                row("assistant", "根分区还剩 30G", null, null));

        List<Message> history = serviceReturning(rows).loadHistory(1L);

        assertThat(history).hasSize(2);
        assertThat(history.get(0)).isInstanceOf(UserMessage.class);
        assertThat(history.get(0).getText()).isEqualTo("看下磁盘");
        assertThat(history.get(1)).isInstanceOf(AssistantMessage.class);
        assertThat(history.get(1).getText()).isEqualTo("根分区还剩 30G");
    }

    @Test
    void 还原带工具调用的完整一轮() {
        // assistant 发起一个 execCommand 调用，随后一条 tool 结果
        String toolCallsJson = "[{\"id\":\"call_1\",\"type\":\"function\","
                + "\"name\":\"execCommand\",\"arguments\":\"{\\\"command\\\":\\\"df -h\\\"}\"}]";
        List<MessageEntity> rows = List.of(
                row("user", "看下磁盘", null, null),
                row("assistant", "", toolCallsJson, null),
                row("tool", "Filesystem ... 30G", null, "call_1"),
                row("assistant", "根分区还剩 30G", null, null));

        List<Message> history = serviceReturning(rows).loadHistory(1L);

        assertThat(history).hasSize(4);
        // 第二条 assistant 带 tool_calls
        AssistantMessage assistant = (AssistantMessage) history.get(1);
        assertThat(assistant.getToolCalls()).hasSize(1);
        assertThat(assistant.getToolCalls().get(0).id()).isEqualTo("call_1");
        assertThat(assistant.getToolCalls().get(0).name()).isEqualTo("execCommand");
        // 第三条是工具结果，id 与调用配对
        assertThat(history.get(2)).isInstanceOf(ToolResponseMessage.class);
        ToolResponseMessage trm = (ToolResponseMessage) history.get(2);
        assertThat(trm.getResponses()).hasSize(1);
        assertThat(trm.getResponses().get(0).id()).isEqualTo("call_1");
    }

    @Test
    void 同一轮多条tool结果合并为一个ToolResponseMessage() {
        List<MessageEntity> rows = List.of(
                row("assistant", "", "[{\"id\":\"c1\",\"type\":\"function\",\"name\":\"execCommand\",\"arguments\":\"{}\"}]", null),
                row("tool", "结果1", null, "c1"),
                row("tool", "结果2", null, "c2"));

        List<Message> history = serviceReturning(rows).loadHistory(1L);

        // 1 条 assistant + 1 条合并后的 ToolResponseMessage（含 2 个 response）
        assertThat(history).hasSize(2);
        ToolResponseMessage trm = (ToolResponseMessage) history.get(1);
        assertThat(trm.getResponses()).hasSize(2);
    }

    @Test
    void 坏的toolCallsJson退化为纯文字assistant() {
        List<MessageEntity> rows = List.of(
                row("assistant", "兜底文字", "{不是合法json", null));

        List<Message> history = serviceReturning(rows).loadHistory(1L);

        assertThat(history).hasSize(1);
        AssistantMessage assistant = (AssistantMessage) history.get(0);
        assertThat(assistant.getMessageType()).isEqualTo(MessageType.ASSISTANT);
        assertThat(assistant.getText()).isEqualTo("兜底文字");
        // 反序列化失败：退化成无 tool_calls
        assertThat(assistant.getToolCalls()).isEmpty();
    }
}
