package com.xiaowenssh.agent;

/**
 * Agent 事件 —— 对外流式输出的带类型事件流。
 *
 * 为什么用带类型事件而不是纯 Flux<String>：运维 Agent 的输出有多种语义——
 * 模型在说话、模型要调命令、命令出结果、命令被拦、任务完成。前端要据此区别渲染
 * （token 追加、工具调用展开、拦截高亮、完成收尾）。纯字符串流分不出这些。
 *
 * sealed + record（Java 17）：限定子类集合，消费方 switch 表达式时编译器保证穷尽，
 * 加事件类型不会漏处理。
 */
public sealed interface AgentEvent {

    /** 模型增量输出的一段文本 token */
    record Token(String text) implements AgentEvent {}

    /** 模型决定调用某个工具 */
    record ToolCall(String name, String args) implements AgentEvent {}

    /** 工具执行结果（executed=false 表示被拦截/拒绝，未真正执行） */
    record ToolResult(String name, String summary, boolean executed) implements AgentEvent {}

    /** 命令被安全门禁拦截 / 用户拒绝 */
    record Blocked(String command, String reason) implements AgentEvent {}

    /** 任务完成，带最终结论文本 */
    record Done(String finalText) implements AgentEvent {}

    /** 出错 */
    record Error(String message) implements AgentEvent {}

    /** 事件类型名，用作 SSE 的 event 字段，方便前端按类型监听 */
    default String type() {
        if (this instanceof Token) return "token";
        if (this instanceof ToolCall) return "tool_call";
        if (this instanceof ToolResult) return "tool_result";
        if (this instanceof Blocked) return "blocked";
        if (this instanceof Done) return "done";
        if (this instanceof Error) return "error";
        return "unknown";
    }
}
