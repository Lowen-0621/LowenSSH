/**
 * Agent 事件 —— 对外流式输出的带类型事件流。
 * 移植自 Java 版 AgentEvent（sealed interface → discriminated union）。
 *
 * 为什么用带类型事件而不是纯字符串流：运维 Agent 输出有多种语义——模型在说话、
 * 要调命令、命令出结果、命令被拦、任务完成。UI 据此区别渲染。语义色是记忆点核心，
 * 与 Web 版 / App 端必须对齐。
 */

/** 模型增量输出的一段文本 token */
export interface TokenEvent {
  type: 'token'
  text: string
}

/** 模型思考过程增量（GLM reasoning_content） */
export interface ReasoningEvent {
  type: 'reasoning'
  text: string
}

/** 模型决定调用某个工具 */
export interface ToolCallEvent {
  type: 'tool_call'
  name: string
  args: string
}

/** 工具执行结果（executed=false 表示被拦截/拒绝，未真正执行） */
export interface ToolResultEvent {
  type: 'tool_result'
  name: string
  summary: string
  executed: boolean
}

/** 命令被安全门禁拦截 / 用户拒绝 */
export interface BlockedEvent {
  type: 'blocked'
  command: string
  reason: string
}

/** 任务完成，带最终结论文本 */
export interface DoneEvent {
  type: 'done'
  finalText: string
}

/** 出错 */
export interface ErrorEvent {
  type: 'error'
  message: string
}

export type AgentEvent =
  | TokenEvent
  | ReasoningEvent
  | ToolCallEvent
  | ToolResultEvent
  | BlockedEvent
  | DoneEvent
  | ErrorEvent

/** ASK 态命令的人工确认入口：返回 true 放行，false 拒绝 */
export type Confirmer = (command: string, reason: string) => Promise<boolean>
