/// Agent 事件 —— 对外流式输出的带类型事件流。
/// 移植自 TS 版 events.ts（再上游 Java AgentEvent）。
///
/// 为什么用带类型事件而不是纯字符串流：运维 Agent 输出有多种语义——模型在说话、
/// 要调命令、命令出结果、命令被拦、任务完成。UI 据此区别渲染。语义色是记忆点核心，
/// 与 Web 版 / 终端端必须对齐。
library;

/// 所有 Agent 事件的密封基类（对应 TS 的 discriminated union）
sealed class AgentEvent {
  const AgentEvent();
}

/// 模型增量输出的一段文本 token
class TokenEvent extends AgentEvent {
  final String text;
  const TokenEvent(this.text);
}

/// 模型思考过程增量（GLM reasoning_content）
class ReasoningEvent extends AgentEvent {
  final String text;
  const ReasoningEvent(this.text);
}

/// 模型决定调用某个工具
class ToolCallEvent extends AgentEvent {
  final String name;
  final String args;
  const ToolCallEvent(this.name, this.args);
}

/// 工具执行结果（executed=false 表示被拦截/拒绝，未真正执行）
class ToolResultEvent extends AgentEvent {
  final String name;
  final String summary;
  final bool executed;
  const ToolResultEvent(this.name, this.summary, this.executed);
}

/// 命令被安全门禁拦截 / 用户拒绝
class BlockedEvent extends AgentEvent {
  final String command;
  final String reason;
  const BlockedEvent(this.command, this.reason);
}

/// 任务完成，带最终结论文本
class DoneEvent extends AgentEvent {
  final String finalText;
  const DoneEvent(this.finalText);
}

/// 出错
class ErrorEvent extends AgentEvent {
  final String message;
  const ErrorEvent(this.message);
}

/// ASK 态命令的人工确认入口：返回 true 放行，false 拒绝
typedef Confirmer = Future<bool> Function(String command, String reason);
