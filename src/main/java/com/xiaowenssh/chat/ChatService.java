package com.xiaowenssh.chat;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;

/**
 * 对话服务 —— 封装 Spring AI 的 ChatClient
 * M1 第一步：先跑通非流式对话，验证模型链路。流式和 agentic loop 后续再加。
 */
@Service
public class ChatService {

    private final ChatClient chatClient;

    // ChatClient.Builder 由 spring-ai starter 自动注入
    public ChatService(ChatClient.Builder builder) {
        this.chatClient = builder.build();
    }

    /**
     * 发送一条消息，同步拿回完整回复（非流式）
     */
    public String chat(String message) {
        return chatClient.prompt()
                .user(message)
                .call()
                .content();
    }
}
