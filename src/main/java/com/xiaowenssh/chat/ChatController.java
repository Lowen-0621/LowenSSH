package com.xiaowenssh.chat;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 对话测试接口 —— M1 第一步验证链路用
 * 访问 http://localhost:8080/api/chat?msg=你好 即可测试
 */
@RestController
public class ChatController {

    private final ChatService chatService;

    public ChatController(ChatService chatService) {
        this.chatService = chatService;
    }

    @GetMapping("/api/chat")
    public String chat(@RequestParam(defaultValue = "你好，介绍一下你自己") String msg) {
        return chatService.chat(msg);
    }
}
