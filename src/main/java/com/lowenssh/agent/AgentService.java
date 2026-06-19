package com.lowenssh.agent;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.agent.guard.CommandGuard;
import com.lowenssh.agent.guard.ConfirmationHandler;
import com.lowenssh.persistence.AuditService;
import com.lowenssh.persistence.MessageService;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.MessageAggregator;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.model.tool.ToolCallingManager;
import org.springframework.ai.model.tool.ToolExecutionResult;
import org.springframework.ai.openai.OpenAiChatModel;
import org.springframework.ai.openai.OpenAiChatOptions;
import org.springframework.ai.support.ToolCallbacks;
import org.springframework.ai.tool.ToolCallback;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;

/**
 * Agent 核心 —— 手写的 agentic loop + 安全门禁。
 *
 * 为什么手写而不用 Spring AI 的自动循环：自动循环把 tool_call 在框架内部执行掉，
 * 我们插不进"执行前人工确认 / 危险命令拦截"这一刀。关键开关：
 * options.internalToolExecutionEnabled(false) —— 关掉自动执行，让 tool_call
 * 回到我们手里，先过门禁、再由 ToolCallingManager.executeToolCalls 显式执行。
 *
 * 循环结构（Claude Code 同款状态机思路）：
 *   请求 → 模型返回 → 有 tool_call？
 *     有 → 门禁预检 → 全放行才执行工具 → 结果回灌 → 带新历史再请求
 *            任一被拒 → 不执行，手动回灌"拒绝"作为工具结果 → loop 继续让模型换方案
 *     无 → 模型给出最终结论，循环结束
 * 加最大轮数上限防死循环。
 *
 * 安全是独立代码路径：门禁不写进工具方法、不靠模型自觉，越狱也绕不过。
 */
@Service
public class AgentService {

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(AgentService.class);

    /** 最大循环轮数，防止模型反复调工具停不下来。可配置：xwssh.agent.max-rounds */
    private final int maxRounds;

    /** 只对这个工具的命令做门禁；其余（读文件/看日志）天然只读，放行 */
    private static final String EXEC_TOOL = "execCommand";

    private static final String SYSTEM_PROMPT = """
            你是 LowenSSH，一个 AI 运维助手，可以通过工具在目标 Linux 服务器上执行命令、读文件、看日志。
            请根据用户的运维任务，自主决定调用哪些工具、分几步完成，每步拿到结果后判断下一步。
            如果某条命令被安全门禁拒绝执行，请换一个更安全的方式达成目标，不要重复同一条被拒命令。
            完成任务后用中文给出清晰的结论，不要只罗列命令输出。
            """;

    private final OpenAiChatModel chatModel;
    private final ToolCallingManager toolCallingManager;
    private final CommandGuard guard;
    private final AuditService auditService;
    private final MessageService messageService;
    private final ContextManager contextManager;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // OpenAiChatModel 和 ToolCallingManager 都由 starter 自动配置好，直接注入
    public AgentService(OpenAiChatModel chatModel, ToolCallingManager toolCallingManager,
                        CommandGuard guard, AuditService auditService, MessageService messageService,
                        ContextManager contextManager,
                        @org.springframework.beans.factory.annotation.Value("${xwssh.agent.max-rounds:40}") int maxRounds) {
        this.chatModel = chatModel;
        this.toolCallingManager = toolCallingManager;
        this.guard = guard;
        this.auditService = auditService;
        this.messageService = messageService;
        this.contextManager = contextManager;
        this.maxRounds = maxRounds;
    }

    /**
     * 跑一轮 agent 任务。
     *
     * @param sessionId   本次会话 id（审计落库用）
     * @param task        用户的运维任务
     * @param tools       会话级工具集（已绑定连好的 SSH 会话）
     * @param confirmer   ask 态命令的人工确认入口（控制台真人 / REST 自动放行）
     * @return 模型的最终结论文本
     */
    public String run(Long sessionId, String task, SshTools tools, ConfirmationHandler confirmer) {
        ToolCallback[] callbacks = ToolCallbacks.from(tools);

        // 关键：internalToolExecutionEnabled(false) 关掉框架自动执行工具
        OpenAiChatOptions options = OpenAiChatOptions.builder()
                .toolCallbacks(callbacks)
                .internalToolExecutionEnabled(false)
                .build();

        List<Message> messages = new ArrayList<>();
        messages.add(new SystemMessage(SYSTEM_PROMPT));
        messages.addAll(messageService.loadHistory(sessionId));  // 还原历史，支持多轮续聊
        messages.add(new UserMessage(task));
        messageService.saveUser(sessionId, task);   // 落用户任务

        for (int round = 1; round <= maxRounds; round++) {
            // 进模型前整理上下文：Layer 0 截断大工具结果 + Layer 4 历史超阈值则压缩
            messages = contextManager.truncateToolResponses(messages);
            messages = contextManager.compressIfNeeded(messages);

            Prompt prompt = new Prompt(messages, options);
            ChatResponse response = chatModel.call(prompt);

            // 没有 tool_call 了，模型给出最终结论，结束
            if (!response.hasToolCalls()) {
                String text = response.getResult().getOutput().getText();
                // 兜底：模型可能给出空结论（尤其命令被反复拦截后），别返回空串误导调用方
                if (text == null || text.isBlank()) {
                    text = "模型暂时没有返回内容，请重试。";
                    messageService.saveAssistant(sessionId, text, null);
                    return text;
                }
                messageService.saveAssistant(sessionId, text, null);   // 落最终结论
                return text;
            }

            AssistantMessage assistant = response.getResult().getOutput();
            persistAssistant(sessionId, assistant);   // 落 assistant（文字 + tool_calls）

            // —— 门禁预检：逐个 tool_call 判定，收集被拒的 ——
            List<ToolResponseMessage.ToolResponse> rejected = screen(sessionId, assistant, confirmer, null);

            if (!rejected.isEmpty()) {
                // 有被拒的：不调框架执行（executeToolCalls 是整批执行，没法只跑一部分）。
                // 手动把 assistant 的 tool_call 消息 + 拒绝结果回灌，loop 继续让模型换方案。
                messages.add(assistant);
                messages.add(ToolResponseMessage.builder().responses(rejected).build());
                persistToolResponses(sessionId, rejected);   // 落拒绝结果（还原"想跑啥被拦了"）
                continue;
            }

            // 全放行：交给框架执行，拿回灌后的完整历史
            ToolExecutionResult execResult = toolCallingManager.executeToolCalls(prompt, response);
            persistLastToolResponses(sessionId, execResult);   // 落本轮工具执行结果
            messages = new ArrayList<>(execResult.conversationHistory());
        }

        return "已达到最大循环轮数（" + maxRounds + "），任务可能未完成。请拆分任务后重试。";
    }

    /**
     * 流式版本：把同步 run() 的执行过程拆成带类型事件流对外推送（SSE 用）。
     *
     * 架构（混合线程）：
     *  - 对外用 Sinks.Many 造一条 Flux<AgentEvent>，方法立刻返回，不阻塞。
     *  - 真正的 agentic loop 是命令式 while，放到独立线程里跑（loop 内部有 block 调用，
     *    不能跑在 reactor 调度线程上）。
     *  - 每轮 chatModel.stream 拿到 token 流，用 MessageAggregator 边推 Token 事件、
     *    边把碎片聚合成完整 ChatResponse（含 tool_call），聚合完再走门禁/执行。
     *
     * 注意：SSH 连接的关闭由调用方在 Flux.doFinally 里做——这里是异步的，方法返回时 loop 还没跑完，
     * 不能用 try-with-resources。
     */
    public Flux<AgentEvent> runStream(Long sessionId, String task, SshTools tools, ConfirmationHandler confirmer) {
        Sinks.Many<AgentEvent> sink = Sinks.many().unicast().onBackpressureBuffer();

        Thread worker = new Thread(() -> {
            try {
                ToolCallback[] callbacks = ToolCallbacks.from(tools);
                OpenAiChatOptions options = OpenAiChatOptions.builder()
                        .toolCallbacks(callbacks)
                        .internalToolExecutionEnabled(false)
                        .build();

                List<Message> messages = new ArrayList<>();
                messages.add(new SystemMessage(SYSTEM_PROMPT));
                messages.addAll(messageService.loadHistory(sessionId));  // 还原历史，支持多轮续聊
                messages.add(new UserMessage(task));
                messageService.saveUser(sessionId, task);   // 落用户任务

                for (int round = 1; round <= maxRounds; round++) {
                    // 进模型前整理上下文：Layer 0 截断大工具结果 + Layer 4 历史超阈值则压缩
                    messages = contextManager.truncateToolResponses(messages);
                    messages = contextManager.compressIfNeeded(messages);

                    Prompt prompt = new Prompt(messages, options);

                    // 一次流式模型调用：边推 token 边聚合，返回完整 ChatResponse
                    ChatResponse response = streamOnce(prompt, sink);

                    // 没有 tool_call：模型给出最终结论，结束
                    if (response == null || !response.hasToolCalls()) {
                        String text = response == null ? null : response.getResult().getOutput().getText();
                        // 空响应可能是模型偶发抖动（返回空 choice），重试一次再判定
                        if (text == null || text.isBlank()) {
                            log.warn("模型返回空结论，重试一次 sessionId={} round={}", sessionId, round);
                            response = streamOnce(prompt, sink);
                            text = response == null ? null : response.getResult().getOutput().getText();
                            // 重试后又冒出 tool_call，回主循环正常处理
                            if (response != null && response.hasToolCalls()) {
                                AssistantMessage retried = response.getResult().getOutput();
                                persistAssistant(sessionId, retried);
                                for (AssistantMessage.ToolCall call : retried.getToolCalls()) {
                                    sink.tryEmitNext(new AgentEvent.ToolCall(call.name(), call.arguments()));
                                }
                                List<ToolResponseMessage.ToolResponse> rj =
                                        screen(sessionId, retried, confirmer, sink::tryEmitNext);
                                if (!rj.isEmpty()) {
                                    messages.add(retried);
                                    messages.add(ToolResponseMessage.builder().responses(rj).build());
                                    persistToolResponses(sessionId, rj);
                                    continue;
                                }
                                Prompt retryPrompt = new Prompt(messages, options);
                                ToolExecutionResult er = toolCallingManager.executeToolCalls(retryPrompt, response);
                                emitToolResults(er, sink);
                                persistLastToolResponses(sessionId, er);
                                messages = new ArrayList<>(er.conversationHistory());
                                continue;
                            }
                        }
                        if (text == null || text.isBlank()) {
                            // 重试仍空：中性文案，不再误导为"被安全策略阻止"
                            text = "模型暂时没有返回内容，请重试。";
                        }
                        messageService.saveAssistant(sessionId, text, null);   // 落最终结论
                        sink.tryEmitNext(new AgentEvent.Done(text));
                        sink.tryEmitComplete();
                        return;
                    }

                    AssistantMessage assistant = response.getResult().getOutput();
                    persistAssistant(sessionId, assistant);   // 落 assistant（文字 + tool_calls）
                    // 先把本轮要调的工具吐出去，让前端看到"准备执行什么"
                    for (AssistantMessage.ToolCall call : assistant.getToolCalls()) {
                        sink.tryEmitNext(new AgentEvent.ToolCall(call.name(), call.arguments()));
                    }

                    // 门禁预检：DENY/用户拒绝会通过 onBlocked 推 Blocked 事件
                    List<ToolResponseMessage.ToolResponse> rejected =
                            screen(sessionId, assistant, confirmer, sink::tryEmitNext);

                    if (!rejected.isEmpty()) {
                        // 有被拒：整批不执行，把 assistant + 拒绝结果回灌，让模型换方案
                        messages.add(assistant);
                        messages.add(ToolResponseMessage.builder().responses(rejected).build());
                        persistToolResponses(sessionId, rejected);   // 落拒绝结果
                        continue;
                    }

                    // 全放行：交框架执行，并把每个工具结果摘要吐给前端
                    ToolExecutionResult execResult = toolCallingManager.executeToolCalls(prompt, response);
                    emitToolResults(execResult, sink);
                    persistLastToolResponses(sessionId, execResult);   // 落本轮工具执行结果
                    messages = new ArrayList<>(execResult.conversationHistory());
                }

                sink.tryEmitNext(new AgentEvent.Done(
                        "已达到最大循环轮数（" + maxRounds + "），任务可能未完成。请拆分任务后重试。"));
                sink.tryEmitComplete();
            } catch (Exception e) {
                log.warn("流式 agent 执行异常 sessionId={}", sessionId, e);
                sink.tryEmitNext(new AgentEvent.Error(e.getMessage() == null ? e.toString() : e.getMessage()));
                sink.tryEmitComplete();
            }
        }, "agent-stream-" + sessionId);
        worker.setDaemon(true);
        worker.start();

        return sink.asFlux();
    }

    /**
     * 一次流式模型调用：透传 chunk 推 Token 事件，聚合成完整 ChatResponse 返回。
     * 抽出来供主循环和空响应重试复用。
     */
    private ChatResponse streamOnce(Prompt prompt, Sinks.Many<AgentEvent> sink) {
        AtomicReference<ChatResponse> aggregatedRef = new AtomicReference<>();
        new MessageAggregator()
                .aggregate(chatModel.stream(prompt), aggregatedRef::set)
                .doOnNext(chunk -> {
                    if (chunk.getResult() == null) {
                        return;
                    }
                    String t = chunk.getResult().getOutput().getText();
                    if (t != null && !t.isEmpty()) {
                        sink.tryEmitNext(new AgentEvent.Token(t));
                    }
                })
                .blockLast();
        return aggregatedRef.get();
    }

    /** 从框架执行后的会话历史里抽取本轮工具结果，逐个推 ToolResult 事件 */
    private void emitToolResults(ToolExecutionResult execResult, Sinks.Many<AgentEvent> sink) {
        List<Message> history = execResult.conversationHistory();
        if (history.isEmpty()) {
            return;
        }
        Message last = history.get(history.size() - 1);
        if (last instanceof ToolResponseMessage trm) {
            for (ToolResponseMessage.ToolResponse resp : trm.getResponses()) {
                String data = unwrapToolData(resp.responseData());
                String summary = data.length() > 500 ? data.substring(0, 500) + "…" : data;
                sink.tryEmitNext(new AgentEvent.ToolResult(resp.name(), summary, true));
            }
        }
    }

    /** 把 assistant 本轮发起的 tool_call 列表序列化成 JSON 落库；无工具调用返回 null */
    private String toolCallsToJson(AssistantMessage assistant) {
        if (assistant.getToolCalls() == null || assistant.getToolCalls().isEmpty()) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(assistant.getToolCalls());
        } catch (Exception e) {
            // 序列化失败不影响主流程，落个占位串即可
            return "[\"tool_calls 序列化失败\"]";
        }
    }

    /** 落一条 assistant 消息：文字 + 本轮 tool_calls（两者可同时为空/有值） */
    private void persistAssistant(Long sessionId, AssistantMessage assistant) {
        messageService.saveAssistant(sessionId, assistant.getText(), toolCallsToJson(assistant));
    }

    /**
     * 框架的 resp.responseData() 是 JSON 序列化后的字符串（带外层引号、\n 被转义成 \\n）。
     * 推给前端、落库前先反序列化成干净文本，避免截断切掉结尾引号导致前端解析失败。
     */
    private String unwrapToolData(String data) {
        if (data == null) {
            return "";
        }
        if (data.startsWith("\"")) {
            try {
                return objectMapper.readValue(data, String.class);
            } catch (Exception e) {
                // 解析失败就用原文，至少不丢内容
                return data;
            }
        }
        return data;
    }

    /** 把一批工具结果（执行结果 / 拒绝结果）逐条落 t_message */
    private void persistToolResponses(Long sessionId, List<ToolResponseMessage.ToolResponse> responses) {
        for (ToolResponseMessage.ToolResponse resp : responses) {
            messageService.saveToolResult(sessionId, resp.id(), unwrapToolData(resp.responseData()));
        }
    }

    /** 从框架执行后的会话历史末尾抽取本轮工具结果落库（数据源同 emitToolResults） */
    private void persistLastToolResponses(Long sessionId, ToolExecutionResult execResult) {
        List<Message> history = execResult.conversationHistory();
        if (history.isEmpty()) {
            return;
        }
        Message last = history.get(history.size() - 1);
        if (last instanceof ToolResponseMessage trm) {
            persistToolResponses(sessionId, trm.getResponses());
        }
    }

    /**
     * 对本轮所有 tool_call 做门禁预检。
     * 返回被拒绝的 tool_call 对应的"拒绝"工具结果；空列表表示全部放行。
     *
     * 注意：只要有一个被拒，本轮就整批不执行（受框架整批执行限制）。所以这里把
     * 被拒的攒成拒绝结果，放行的不在这里执行——交给外层 executeToolCalls 统一跑。
     */
    private List<ToolResponseMessage.ToolResponse> screen(Long sessionId, AssistantMessage assistant,
                                                          ConfirmationHandler confirmer,
                                                          Consumer<AgentEvent> onBlocked) {
        List<ToolResponseMessage.ToolResponse> rejected = new ArrayList<>();

        for (AssistantMessage.ToolCall call : assistant.getToolCalls()) {
            // 非 execCommand 的工具（读文件/看日志）只读，直接放行
            if (!EXEC_TOOL.equals(call.name())) {
                continue;
            }

            String command = extractCommand(call.arguments());
            CommandGuard.Verdict verdict = guard.evaluate(command);

            switch (verdict.decision()) {
                case DENY -> {
                    // 拦截点审计：模型试图跑危险命令、被门禁拦下——最有价值的审计记录
                    auditService.logBlocked(sessionId, command, true,
                            "DENY: " + verdict.reason());
                    if (onBlocked != null) {
                        onBlocked.accept(new AgentEvent.Blocked(command, verdict.reason()));
                    }
                    rejected.add(reject(call,
                            "命令被安全门禁拒绝执行（" + verdict.reason() + "）。请改用更安全的方式。"));
                }
                case ASK -> {
                    boolean ok = confirmer.confirm(command, verdict.reason());
                    if (!ok) {
                        // 用户拒绝也记一笔（dangerous=true 因为是 ask 态命中副作用规则）
                        auditService.logBlocked(sessionId, command, true,
                                "用户拒绝: " + verdict.reason());
                        if (onBlocked != null) {
                            onBlocked.accept(new AgentEvent.Blocked(command, "用户拒绝: " + verdict.reason()));
                        }
                        rejected.add(reject(call, "用户拒绝执行该命令。请换一种方式或询问用户。"));
                    }
                    // 批准则不加入 rejected，留给外层执行（执行点会在 SshTools 落审计）
                }
                case ALLOW -> { /* 放行 */ }
            }
        }
        return rejected;
    }

    /** 从 tool_call 的 JSON 参数里取出 command 字段 */
    private String extractCommand(String argumentsJson) {
        try {
            var node = objectMapper.readTree(argumentsJson);
            var cmd = node.get("command");
            return cmd == null ? "" : cmd.asText();
        } catch (Exception e) {
            // 解析失败当空命令处理（门禁会放行，但实际执行会报错，模型自己会看到）
            return "";
        }
    }

    /** 构造一条"拒绝"工具结果，id/name 必须和原 tool_call 对上，模型才知道是哪一步被拒 */
    private ToolResponseMessage.ToolResponse reject(AssistantMessage.ToolCall call, String reason) {
        return new ToolResponseMessage.ToolResponse(call.id(), call.name(), reason);
    }
}
