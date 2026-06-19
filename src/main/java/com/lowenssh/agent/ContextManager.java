package com.lowenssh.agent;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.openai.OpenAiChatModel;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * 上下文管理 —— 防止 agentic loop 多轮滚下来把模型上下文撑爆。
 *
 * 抄 Claude Code 的思路，只做两层（其余 cache_edits / session memory 是为 prompt cache
 * 做的精细活，DeepSeek/GLM 场景 ROI 低，不做）：
 *
 *  Layer 0 —— 大工具结果截断：单条工具结果（cat 大文件、tail 海量日志）超阈值就截掉中段，
 *             只留头尾 + 一行截断提示。注意：完整内容我们本来就落了 t_message，
 *             截断只作用于"回灌给模型的副本"，落库的仍是完整内容，可还原。
 *
 *  Layer 4 —— 历史压缩：整段 messages 估算 token 超阈值时，把较早的对话丢给 LLM 摘要成一条，
 *             保留 system + 最近 K 条原文。硬约束：assistant 的 tool_call 和它的
 *             tool_result 必须成对，切割点不能落在中间，否则 GLM 直接报错。
 *             摘要 LLM 连续失败到熔断阈值就停止压缩、裸跑兜底，避免摘要本身挂了拖死主流程。
 *
 * 阈值全部可配置（application 配置项 xwssh.context.*），方便联调时调小快速触发验证。
 * token 用字符数粗估：中英混合约 2.5 字符 / token，不引 tokenizer 依赖。
 */
@Component
public class ContextManager {

    private static final Logger log = LoggerFactory.getLogger(ContextManager.class);

    /** 字符数到 token 的粗估系数：中英混合约 2.5 字符 = 1 token */
    private static final double CHARS_PER_TOKEN = 2.5;

    private final OpenAiChatModel chatModel;

    /** Layer 0：单条工具结果保留的最大字符数，超出截断中段 */
    private final int toolResultMaxChars;
    /** Layer 4：整段上下文估算 token 超过此值触发压缩 */
    private final int maxContextTokens;
    /** Layer 4：压缩时保留最近多少条消息原文（不进摘要） */
    private final int keepRecentMessages;
    /** Layer 4：摘要 LLM 连续失败达到此次数后熔断，不再压缩 */
    private final int circuitLimit;

    /** 摘要 LLM 连续失败计数，成功清零；达到 circuitLimit 触发熔断 */
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);

    public ContextManager(
            OpenAiChatModel chatModel,
            @Value("${xwssh.context.tool-result-max-chars:8000}") int toolResultMaxChars,
            @Value("${xwssh.context.max-context-tokens:32000}") int maxContextTokens,
            @Value("${xwssh.context.keep-recent-messages:6}") int keepRecentMessages,
            @Value("${xwssh.context.circuit-limit:3}") int circuitLimit) {
        this.chatModel = chatModel;
        this.toolResultMaxChars = toolResultMaxChars;
        this.maxContextTokens = maxContextTokens;
        this.keepRecentMessages = keepRecentMessages;
        this.circuitLimit = circuitLimit;
    }

    // ============================ Layer 0：工具结果截断 ============================

    /**
     * 对历史里所有工具结果做截断（幂等：已截短的再跑也不变）。
     * 返回新列表，不改原列表。只重建超长的 ToolResponseMessage，其余消息原样保留。
     */
    public List<Message> truncateToolResponses(List<Message> messages) {
        List<Message> result = new ArrayList<>(messages.size());
        for (Message msg : messages) {
            if (msg instanceof ToolResponseMessage trm) {
                result.add(truncateOne(trm));
            } else {
                result.add(msg);
            }
        }
        return result;
    }

    /** 重建一条 ToolResponseMessage：把每个超长的 responseData 截掉中段 */
    private ToolResponseMessage truncateOne(ToolResponseMessage trm) {
        List<ToolResponseMessage.ToolResponse> truncated = new ArrayList<>();
        for (ToolResponseMessage.ToolResponse resp : trm.getResponses()) {
            String data = resp.responseData();
            truncated.add(new ToolResponseMessage.ToolResponse(
                    resp.id(), resp.name(), truncateText(data)));
        }
        return ToolResponseMessage.builder().responses(truncated).build();
    }

    /** 截断提示里的哨兵串：已含此串说明截过了，幂等跳过，避免二次截断 */
    private static final String TRUNCATE_MARKER = "完整结果见 t_message";

    /** 截掉中段，保留头 60% / 尾 40%，中间塞一行提示（指向 t_message 取完整内容） */
    private String truncateText(String text) {
        if (text == null || text.length() <= toolResultMaxChars) {
            return text;
        }
        // 幂等：已经截过的（含哨兵）不再处理，否则头尾+提示可能仍超阈值被反复截
        if (text.contains(TRUNCATE_MARKER)) {
            return text;
        }
        int headLen = (int) (toolResultMaxChars * 0.6);
        int tailLen = toolResultMaxChars - headLen;
        int cut = text.length() - headLen - tailLen;
        String head = text.substring(0, headLen);
        String tail = text.substring(text.length() - tailLen);
        return head
                + "\n...[已截断 " + cut + " 字符，" + TRUNCATE_MARKER + "]...\n"
                + tail;
    }

    // ============================ Layer 4：历史压缩 ============================

    /**
     * 估算上下文超阈值时压缩历史，否则原样返回。
     *
     * 切割策略：messages[0] 是 system，固定保留；尾部保留 keepRecentMessages 条原文；
     * 中间较早的对话渲染成纯文本丢给 LLM 摘要，压成一条 UserMessage 插在 system 之后。
     *
     * 成对约束：保留区开头不能是 ToolResponseMessage（否则它的 tool_call 落在摘要区被切走，
     * 模型见到孤儿 tool_result 会报错）。切割点往前移到对应 assistant，让两者一起进保留区。
     */
    public List<Message> compressIfNeeded(List<Message> messages) {
        // 熔断：摘要 LLM 连续挂了就别再试，裸跑兜底
        if (consecutiveFailures.get() >= circuitLimit) {
            return messages;
        }
        if (estimateTokens(messages) <= maxContextTokens) {
            return messages;
        }
        // 太短没什么可压（至少要有 system + 摘要区 + 保留区）
        if (messages.size() <= keepRecentMessages + 1) {
            return messages;
        }

        int cutIndex = messages.size() - keepRecentMessages;
        // 把切割点往前挪，避免保留区以孤儿 tool_result 开头
        while (cutIndex > 1 && messages.get(cutIndex) instanceof ToolResponseMessage) {
            cutIndex--;
        }
        // 挪到头了说明摘要区为空，没东西可压
        if (cutIndex <= 1) {
            return messages;
        }

        List<Message> summaryRegion = messages.subList(1, cutIndex);
        String summary = summarize(summaryRegion);
        if (summary == null) {
            // 摘要失败：计数 +1，本轮放弃压缩，原样返回
            int fails = consecutiveFailures.incrementAndGet();
            log.warn("历史摘要失败（连续 {} 次），本轮跳过压缩", fails);
            return messages;
        }
        consecutiveFailures.set(0);   // 成功清零

        List<Message> compressed = new ArrayList<>();
        compressed.add(messages.get(0));   // system
        compressed.add(new UserMessage("以下是早先对话的摘要，供你继续任务时参考：\n" + summary));
        compressed.addAll(messages.subList(cutIndex, messages.size()));   // 最近 K 条原文

        log.info("上下文压缩：{} 条 -> {} 条（摘要了 {} 条）",
                messages.size(), compressed.size(), summaryRegion.size());
        return compressed;
    }

    /** 调摘要 LLM 把一段历史压成结论文本；失败返回 null（由调用方走熔断逻辑） */
    private String summarize(List<Message> region) {
        try {
            String rendered = renderRegion(region);
            // 摘要请求不带任何工具，纯文本进纯文本出，避免又触发 tool_call
            List<Message> prompt = List.of(
                    new SystemMessage(SUMMARY_PROMPT),
                    new UserMessage(rendered));
            ChatResponse resp = chatModel.call(new Prompt(prompt));
            if (resp == null || resp.getResult() == null) {
                return null;
            }
            String text = resp.getResult().getOutput().getText();
            return (text == null || text.isBlank()) ? null : text;
        } catch (Exception e) {
            log.warn("摘要 LLM 调用异常: {}", e.getMessage());
            return null;
        }
    }

    private static final String SUMMARY_PROMPT = """
            你是上下文压缩器。下面是一段 AI 运维助手与目标服务器之间的历史对话（含用户任务、助手发起的命令调用、命令执行结果）。
            请把它压缩成简洁的中文摘要，必须保留以下信息，丢弃冗长的原始命令输出（只留结论）：
            1. 用户的原始运维目标；
            2. 已执行过的关键命令及其结果结论（例如磁盘占用多少、进程是否存活、配置是否正确）；
            3. 已发现的问题或系统状态；
            4. 被安全门禁拦截的危险操作（如果有）。
            只输出摘要正文，不要解释你在做什么。
            """;

    /** 把一段消息渲染成纯文本喂给摘要 LLM（按角色标注，工具调用/结果也转成可读文本） */
    private String renderRegion(List<Message> region) {
        StringBuilder sb = new StringBuilder();
        for (Message msg : region) {
            if (msg instanceof UserMessage um) {
                sb.append("用户: ").append(um.getText()).append("\n");
            } else if (msg instanceof AssistantMessage am) {
                if (am.getText() != null && !am.getText().isBlank()) {
                    sb.append("助手: ").append(am.getText()).append("\n");
                }
                if (am.getToolCalls() != null) {
                    for (AssistantMessage.ToolCall call : am.getToolCalls()) {
                        sb.append("助手调用工具 ").append(call.name())
                                .append(": ").append(call.arguments()).append("\n");
                    }
                }
            } else if (msg instanceof ToolResponseMessage trm) {
                for (ToolResponseMessage.ToolResponse resp : trm.getResponses()) {
                    sb.append("工具[").append(resp.name()).append("]结果: ")
                            .append(resp.responseData()).append("\n");
                }
            }
        }
        return sb.toString();
    }

    // ============================ 工具方法 ============================

    /** 估算整段消息的 token 数（字符数粗估，不引 tokenizer） */
    public int estimateTokens(List<Message> messages) {
        long chars = 0;
        for (Message msg : messages) {
            chars += messageChars(msg);
        }
        return (int) (chars / CHARS_PER_TOKEN);
    }

    /** 单条消息的字符量：取其文本 + 工具调用参数 + 工具结果内容 */
    private long messageChars(Message msg) {
        if (msg instanceof ToolResponseMessage trm) {
            long n = 0;
            for (ToolResponseMessage.ToolResponse resp : trm.getResponses()) {
                String d = resp.responseData();
                n += d == null ? 0 : d.length();
            }
            return n;
        }
        if (msg instanceof AssistantMessage am) {
            long n = am.getText() == null ? 0 : am.getText().length();
            if (am.getToolCalls() != null) {
                for (AssistantMessage.ToolCall call : am.getToolCalls()) {
                    n += call.arguments() == null ? 0 : call.arguments().length();
                }
            }
            return n;
        }
        String t = msg.getText();
        return t == null ? 0 : t.length();
    }
}
