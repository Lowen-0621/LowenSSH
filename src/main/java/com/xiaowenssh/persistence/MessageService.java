package com.xiaowenssh.persistence;

import com.xiaowenssh.persistence.entity.MessageEntity;
import com.xiaowenssh.persistence.mapper.MessageMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

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
}
