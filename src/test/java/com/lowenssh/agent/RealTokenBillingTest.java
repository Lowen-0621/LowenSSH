package com.lowenssh.agent;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * 真实账单 token 测试 —— 直连 GLM API 读 usage.prompt_tokens（真实计费 token）。
 *
 * 与离线 benchmark 的区别：这里把「截断前 / 截断后」两版上下文分别真发给 GLM，
 * 读回真实的 prompt_tokens 做对比，是真实账单口径，不是字符估算。
 *
 * 用 ContextManager 做截断（项目真实逻辑）。内容用带变化的拟真运维输出
 * （变化的时间戳/IP/PID），避免重复串被 BPE 分词压没导致数字失真。
 *
 * 仅在设置了 GLM_API_KEY 环境变量时运行，避免 CI 空跑。
 */
@EnabledIfEnvironmentVariable(named = "GLM_API_KEY", matches = ".+")
class RealTokenBillingTest {

    private static final String API = "https://open.bigmodel.cn/api/paas/v4/chat/completions";
    private static final String MODEL = "glm-4.7";
    private final HttpClient http = HttpClient.newHttpClient();
    private final Random rnd = new Random(42);

    /** 生产同款配置（对齐 application.yml）：近区 3000 / 旧区 800 / 保留最近 4 条 */
    private ContextManager prod() {
        return new ContextManager(null, 3000, 800, 12000, 4, 3);
    }

    private ToolResponseMessage toolMsg(String id, String data) {
        return ToolResponseMessage.builder()
                .responses(List.of(new ToolResponseMessage.ToolResponse(id, "execCommand", data)))
                .build();
    }

    /** 拟真 nginx 访问日志（每行不同：IP/时间/路径/状态码都变化，分词有代表性） */
    private String fakeNginxLog(int lines) {
        StringBuilder sb = new StringBuilder();
        String[] paths = {"/api/user/login", "/api/order/list", "/static/app.js", "/health", "/api/pay/callback"};
        for (int i = 0; i < lines; i++) {
            sb.append(String.format("%d.%d.%d.%d - - [%02d/Jun/2026:%02d:%02d:%02d +0800] \"GET %s HTTP/1.1\" %d %d\n",
                    rnd.nextInt(255), rnd.nextInt(255), rnd.nextInt(255), rnd.nextInt(255),
                    rnd.nextInt(28) + 1, rnd.nextInt(24), rnd.nextInt(60), rnd.nextInt(60),
                    paths[rnd.nextInt(paths.length)], new int[]{200, 200, 404, 500, 302}[rnd.nextInt(5)],
                    rnd.nextInt(50000)));
        }
        return sb.toString();
    }

    /** 拟真 ps aux 进程列表 */
    private String fakePs(int lines) {
        StringBuilder sb = new StringBuilder("USER  PID %CPU %MEM    VSZ   RSS TTY STAT START   TIME COMMAND\n");
        String[] procs = {"nginx", "java -jar app.jar", "mysqld", "sshd", "redis-server", "python3 worker.py"};
        for (int i = 0; i < lines; i++) {
            sb.append(String.format("root %5d %.1f %.1f %7d %6d ?  Ss %02d:%02d %d:%02d %s\n",
                    rnd.nextInt(30000), rnd.nextDouble() * 100, rnd.nextDouble() * 20,
                    rnd.nextInt(2000000), rnd.nextInt(500000), rnd.nextInt(24), rnd.nextInt(60),
                    rnd.nextInt(100), rnd.nextInt(60), procs[rnd.nextInt(procs.length)]));
        }
        return sb.toString();
    }

    /** 仿真 N 轮运维对话，命令输出是拟真日志/进程列表 */
    private List<Message> opsConversation(int rounds) {
        List<Message> msgs = new ArrayList<>();
        msgs.add(new SystemMessage("你是 SSH 智能运维助手，可调用 execCommand 执行命令排查服务器问题。"));
        for (int i = 0; i < rounds; i++) {
            msgs.add(new UserMessage("第" + (i + 1) + "步：检查服务状态"));
            String cmd = i % 2 == 0 ? "tail -n 300 access.log" : "ps aux";
            msgs.add(AssistantMessage.builder().content("执行 " + cmd)
                    .toolCalls(List.of(new AssistantMessage.ToolCall(
                            "c" + i, "function", "execCommand", "{\"command\":\"" + cmd + "\"}")))
                    .build());
            String out = i % 2 == 0 ? fakeNginxLog(300) : fakePs(200);
            msgs.add(toolMsg("c" + i, out));
        }
        return msgs;
    }

    /** 把 messages 渲染成 GLM chat 请求的 messages JSON（system/user/assistant 都拍平成文本，够测 prompt token） */
    private String toRequestJson(List<Message> msgs) {
        StringBuilder arr = new StringBuilder("[");
        for (int i = 0; i < msgs.size(); i++) {
            Message m = msgs.get(i);
            String role, content;
            if (m instanceof SystemMessage) { role = "system"; content = m.getText(); }
            else if (m instanceof UserMessage) { role = "user"; content = m.getText(); }
            else if (m instanceof ToolResponseMessage trm) {
                role = "user"; // 测 prompt token 用，工具结果拍平成 user 文本即可
                content = "工具结果:\n" + trm.getResponses().get(0).responseData();
            } else if (m instanceof AssistantMessage am) {
                role = "assistant";
                content = am.getText() == null ? "" : am.getText();
            } else { role = "user"; content = m.getText() == null ? "" : m.getText(); }
            if (i > 0) arr.append(",");
            arr.append("{\"role\":\"").append(role).append("\",\"content\":")
               .append(jsonStr(content)).append("}");
        }
        arr.append("]");
        return "{\"model\":\"" + MODEL + "\",\"messages\":" + arr + ",\"max_tokens\":1,\"stream\":false}";
    }

    private String jsonStr(String s) {
        StringBuilder sb = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> sb.append(c);
            }
        }
        return sb.append("\"").toString();
    }

    /** 发一次真实请求，返回 [prompt_tokens, cached_tokens] */
    private int[] callGlm(List<Message> msgs) throws Exception {
        String body = toRequestJson(msgs);
        HttpRequest req = HttpRequest.newBuilder(URI.create(API))
                .header("Authorization", "Bearer " + System.getenv("GLM_API_KEY"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
        HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        String r = resp.body();
        int prompt = extractInt(r, "prompt_tokens");
        int cached = extractCached(r);
        if (prompt < 0) {
            System.out.println("  [警告] 未解析到 prompt_tokens，响应片段: "
                    + r.substring(0, Math.min(300, r.length())));
        }
        return new int[]{prompt, cached};
    }

    private int extractInt(String json, String key) {
        int k = json.indexOf("\"" + key + "\"");
        if (k < 0) return -1;
        int colon = json.indexOf(':', k);
        int end = colon + 1;
        while (end < json.length() && !Character.isDigit(json.charAt(end))) end++;
        int start = end;
        while (end < json.length() && Character.isDigit(json.charAt(end))) end++;
        return start < end ? Integer.parseInt(json.substring(start, end)) : -1;
    }

    /** cached_tokens 在 prompt_tokens_details 里，可能不存在 */
    private int extractCached(String json) {
        int v = extractInt(json, "cached_tokens");
        return v < 0 ? 0 : v;
    }

    @Test
    void 真实账单token截断前后对比() throws Exception {
        ContextManager cm = prod();
        System.out.println("\n==== 真实账单 token 测试（直连 GLM glm-4.7，读 usage.prompt_tokens）====");
        System.out.println("配置：近区 3000 / 旧区 800 / 保留最近 4 条（对齐 application.yml）");
        System.out.printf("%-6s %-18s %-18s %-10s%n", "轮数", "截断前prompt_tokens", "截断后prompt_tokens", "降幅");
        for (int rounds : new int[]{3, 6, 10}) {
            List<Message> raw = opsConversation(rounds);
            List<Message> truncated = cm.truncateToolResponses(raw);
            int before = callGlm(raw)[0];
            Thread.sleep(800); // 避免限流
            int after = callGlm(truncated)[0];
            double cut = before > 0 ? (before - after) * 100.0 / before : 0;
            System.out.printf("%-6d %-18d %-18d %.1f%%%n", rounds, before, after, cut);
            Thread.sleep(800);
        }
        System.out.println("=========================================================\n");
    }

    @Test
    void 真实缓存命中率测试() throws Exception {
        ContextManager cm = prod();
        // 同一份（截断后）上下文连发两次，第二次前缀应命中 GLM 隐式缓存
        List<Message> ctx = cm.truncateToolResponses(opsConversation(8));
        System.out.println("\n==== 真实缓存命中率测试（同上下文连发两次）====");
        int[] first = callGlm(ctx);
        Thread.sleep(1000);
        int[] second = callGlm(ctx);
        System.out.printf("第1次：prompt_tokens=%d cached_tokens=%d 命中率=%.1f%%%n",
                first[0], first[1], first[0] > 0 ? first[1] * 100.0 / first[0] : 0);
        System.out.printf("第2次：prompt_tokens=%d cached_tokens=%d 命中率=%.1f%%%n",
                second[0], second[1], second[0] > 0 ? second[1] * 100.0 / second[0] : 0);
        System.out.println("观察：第2次 cached_tokens 若显著 >0，说明 GLM 隐式缓存命中、前缀稳定策略生效。\n");
    }
}
