package com.lowenssh.persistence;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.persistence.entity.MessageEntity;
import com.lowenssh.persistence.mapper.MessageMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * 对话消息服务 —— 把 agentic loop 的每轮消息落 t_message，按 session_id 可还原完整对话。
 *
 * 不落 system prompt：它每次固定，捞历史时代码里加回去即可，存了是冗余。
 *
 * 铁律同 AuditService：落库失败绝不能拖垮主任务，写库 try/catch 兜住，只告警不抛。
 */
@Service
public class MessageService {

    private static final Logger log = LoggerFactory.getLogger(MessageService.class);

    private final MessageMapper messageMapper;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public MessageService(MessageMapper messageMapper) {
        this.messageMapper = messageMapper;
    }

    /** 落一条用户消息（loop 开始时的 task） */
    public void saveUser(Long sessionId, String content) {
        MessageEntity e = new MessageEntity();
        e.setSessionId(sessionId);
        e.setRole("user");
        e.setContent(content);
        save(e);
    }

    /**
     * 落一条 assistant 消息。
     * @param content    模型的文字回复（可能为空，纯工具调用时）
     * @param toolCalls  本轮发起的工具调用 JSON（无则传 null）
     */
    public void saveAssistant(Long sessionId, String content, String toolCalls) {
        MessageEntity e = new MessageEntity();
        e.setSessionId(sessionId);
        e.setRole("assistant");
        e.setContent(content);
        e.setToolCalls(toolCalls);
        save(e);
    }

    /**
     * 落一条工具结果消息（含被门禁拒绝的"拒绝结果"，这样历史能还原"模型想跑啥被拦了"）。
     * @param toolCallId 对应的工具调用 id
     * @param content    工具返回内容 / 拒绝原因
     */
    public void saveToolResult(Long sessionId, String toolCallId, String content) {
        MessageEntity e = new MessageEntity();
        e.setSessionId(sessionId);
        e.setRole("tool");
        e.setToolCallId(toolCallId);
        e.setContent(content);
        save(e);
    }

    private void save(MessageEntity e) {
        try {
            messageMapper.insert(e);
        } catch (Exception ex) {
            // 落库失败不影响主流程，只告警
            log.warn("消息写库失败 sessionId={} role={}: {}", e.getSessionId(), e.getRole(), ex.getMessage());
        }
    }

    /**
     * 按 sessionId 还原历史对话为 Spring AI 的 Message 列表（供多轮续聊回灌给模型）。
     *
     * 不含 system prompt（捞回去由 AgentService 自己加）。还原规则：
     *  - user  -> UserMessage
     *  - assistant -> AssistantMessage（带 tool_calls 反序列化，id/name 必须和后续 tool 结果配对）
     *  - tool  -> ToolResponseMessage；同一轮可能有多条 tool 行，连续的 tool 合并进一个
     *            ToolResponseMessage，符合 OpenAI 协议「一个 assistant.tool_calls 对应一组 tool 结果」
     *
     * 任一条解析失败只跳过该条，不拖垮续聊。
     */
    public List<Message> loadHistory(Long sessionId) {
        List<Message> messages = new ArrayList<>();
        if (sessionId == null) {
            return messages;
        }

        List<MessageEntity> rows;
        try {
            LambdaQueryWrapper<MessageEntity> wrapper = new LambdaQueryWrapper<MessageEntity>()
                    .eq(MessageEntity::getSessionId, sessionId)
                    .orderByAsc(MessageEntity::getId);  // 按落库顺序还原
            rows = messageMapper.selectList(wrapper);
        } catch (Exception ex) {
            log.warn("加载历史失败 sessionId={}: {}", sessionId, ex.getMessage());
            return messages;
        }

        // 连续的 tool 行要合并成一个 ToolResponseMessage，先攒着，遇到非 tool 行再 flush
        List<ToolResponseMessage.ToolResponse> pendingTool = new ArrayList<>();

        for (MessageEntity row : rows) {
            String role = row.getRole();
            if ("tool".equals(role)) {
                // 工具结果先攒进 pending，name 历史没单独存，回灌不影响模型理解，用占位即可
                pendingTool.add(new ToolResponseMessage.ToolResponse(
                        row.getToolCallId(), "", nullToEmpty(row.getContent())));
                continue;
            }

            // 遇到非 tool 行，先把攒着的工具结果 flush 成一条 ToolResponseMessage
            flushTool(messages, pendingTool);

            switch (role) {
                case "user" -> messages.add(new UserMessage(nullToEmpty(row.getContent())));
                case "assistant" -> messages.add(toAssistant(row));
                default -> { /* system 等不还原 */ }
            }
        }
        // 收尾 flush（历史以工具结果结尾的情况）
        flushTool(messages, pendingTool);

        return messages;
    }

    /**
     * 按 sessionId 把历史转成前端可直接渲染的消息列表（左栏点开旧会话回看用）。
     *
     * 与 loadHistory 不同：这里不是回灌给模型，而是给人看，所以：
     *  - user      -> {type:user, text}
     *  - assistant -> 文字非空时产出 {type:assistant, text}；带 tool_calls 时每个调用
     *                 额外产出一条 {type:tool_call, name, summary=命令}（从 arguments 提取 command）
     *  - tool      -> {type:tool_result, summary=结果内容}
     *
     * 任一条解析失败只跳过该条，不影响整体回看。
     */
    public List<com.lowenssh.agent.SessionDto.HistoryMessage> loadHistoryForView(Long sessionId) {
        List<com.lowenssh.agent.SessionDto.HistoryMessage> out = new ArrayList<>();
        if (sessionId == null) {
            return out;
        }

        List<MessageEntity> rows;
        try {
            LambdaQueryWrapper<MessageEntity> wrapper = new LambdaQueryWrapper<MessageEntity>()
                    .eq(MessageEntity::getSessionId, sessionId)
                    .orderByAsc(MessageEntity::getId);
            rows = messageMapper.selectList(wrapper);
        } catch (Exception ex) {
            log.warn("回看历史失败 sessionId={}: {}", sessionId, ex.getMessage());
            return out;
        }

        for (MessageEntity row : rows) {
            String role = row.getRole();
            switch (role == null ? "" : role) {
                case "user" -> out.add(new com.lowenssh.agent.SessionDto.HistoryMessage(
                        "user", nullToEmpty(row.getContent()), null, null));
                case "assistant" -> {
                    // 文字部分（纯工具调用时为空，不产出空气泡）
                    String text = nullToEmpty(row.getContent());
                    if (!text.isBlank()) {
                        out.add(new com.lowenssh.agent.SessionDto.HistoryMessage(
                                "assistant", text, null, null));
                    }
                    // 工具调用部分：每个 call 转一条 tool_call，展示命令
                    appendToolCalls(out, row.getToolCalls());
                }
                case "tool" -> out.add(new com.lowenssh.agent.SessionDto.HistoryMessage(
                        "tool_result", null, null, nullToEmpty(row.getContent())));
                default -> { /* system 等不回看 */ }
            }
        }
        return out;
    }

    /** 解析 assistant 的 tool_calls JSON，每个调用产出一条 tool_call 历史项（命令从 arguments 提取） */
    private void appendToolCalls(List<com.lowenssh.agent.SessionDto.HistoryMessage> out, String toolCallsJson) {
        if (toolCallsJson == null || toolCallsJson.isBlank()) {
            return;
        }
        try {
            List<AssistantMessage.ToolCall> calls = objectMapper.readValue(
                    toolCallsJson, new TypeReference<List<AssistantMessage.ToolCall>>() {});
            for (AssistantMessage.ToolCall call : calls) {
                out.add(new com.lowenssh.agent.SessionDto.HistoryMessage(
                        "tool_call", null, call.name(), extractCommand(call.arguments())));
            }
        } catch (Exception ex) {
            log.warn("回看解析 tool_calls 失败: {}", ex.getMessage());
        }
    }

    /** 从工具参数 JSON 里取 command 字段；取不到就原样返回 */
    private String extractCommand(String arguments) {
        if (arguments == null || arguments.isBlank()) {
            return "";
        }
        try {
            var node = objectMapper.readTree(arguments);
            if (node.has("command")) {
                return node.get("command").asText();
            }
        } catch (Exception ignored) {
            // 解析失败原样返回
        }
        return arguments;
    }

    /** 把攒着的工具结果合并成一条 ToolResponseMessage 加入历史，并清空缓冲 */
    private void flushTool(List<Message> messages, List<ToolResponseMessage.ToolResponse> pending) {
        if (!pending.isEmpty()) {
            messages.add(ToolResponseMessage.builder().responses(new ArrayList<>(pending)).build());
            pending.clear();
        }
    }

    /** 还原一条 assistant 消息：文字 + tool_calls（JSON 反序列化回 ToolCall 列表） */
    private AssistantMessage toAssistant(MessageEntity row) {
        String content = nullToEmpty(row.getContent());
        String toolCallsJson = row.getToolCalls();
        if (toolCallsJson == null || toolCallsJson.isBlank()) {
            return new AssistantMessage(content);
        }
        try {
            List<AssistantMessage.ToolCall> calls = objectMapper.readValue(
                    toolCallsJson, new TypeReference<List<AssistantMessage.ToolCall>>() {});
            return AssistantMessage.builder().content(content).toolCalls(calls).build();
        } catch (Exception ex) {
            // 反序列化失败：退化成纯文字 assistant，至少保住对话连续性
            log.warn("还原 tool_calls 失败，退化为纯文字 sessionId={}: {}", row.getSessionId(), ex.getMessage());
            return new AssistantMessage(content);
        }
    }

    private static String nullToEmpty(String s) {
        return s == null ? "" : s;
    }
}
