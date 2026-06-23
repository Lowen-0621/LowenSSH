/**
 * GLM 接入 —— OpenAI 兼容协议封装，支持 function calling + streaming + reasoning_content。
 * 替代 Java 版 Spring AI 的 OpenAiChatModel + ToolCallingManager。
 *
 * 模型无关设计：换模型只改 baseURL / model（GLM / 通义 / DeepSeek 都走 OpenAI 兼容协议）。
 * GLM 端点是 .../paas/v4/chat/completions，openai sdk 的 baseURL 指到 .../paas/v4 即可。
 */
import OpenAI from 'openai'
import type { LlmConfig } from './config.js'

/** 对话消息（OpenAI chat 格式子集，够 agent loop 用） */
export type ChatMessage =
  | { role: 'system'; content: string }
  | { role: 'user'; content: string }
  | { role: 'assistant'; content: string | null; tool_calls?: ToolCall[] }
  | { role: 'tool'; tool_call_id: string; content: string }

/** 一次工具调用 */
export interface ToolCall {
  id: string
  type: 'function'
  function: { name: string; arguments: string }
}

/** 工具定义（function schema） */
export interface ToolDef {
  type: 'function'
  function: {
    name: string
    description: string
    parameters: Record<string, unknown>
  }
}

/** 一次模型响应聚合结果 */
export interface ChatResult {
  /** 模型正文文本 */
  text: string
  /** 本轮发起的工具调用（无则空数组） */
  toolCalls: ToolCall[]
  /** token 用量（用于缓存命中测量） */
  usage?: {
    promptTokens?: number
    completionTokens?: number
    totalTokens?: number
    cachedTokens?: number
  }
}

/** 流式回调：边收边推 */
export interface StreamHandlers {
  onToken?: (text: string) => void
  onReasoning?: (text: string) => void
}

export class GlmClient {
  private client: OpenAI
  private model: string

  constructor(cfg: LlmConfig) {
    this.client = new OpenAI({ baseURL: cfg.baseURL, apiKey: cfg.apiKey })
    this.model = cfg.model
  }

  /**
   * 一次流式调用：透传 token / reasoning 增量，聚合成完整结果返回。
   * 关闭框架自动工具执行——工具调用聚合后交回上层 loop 过门禁再执行。
   */
  async stream(
    messages: ChatMessage[],
    tools: ToolDef[],
    handlers: StreamHandlers,
  ): Promise<ChatResult> {
    const stream = await this.client.chat.completions.create({
      model: this.model,
      messages: messages as OpenAI.Chat.ChatCompletionMessageParam[],
      tools: tools.length > 0 ? (tools as OpenAI.Chat.ChatCompletionTool[]) : undefined,
      stream: true,
      stream_options: { include_usage: true },
    })

    let text = ''
    // tool_calls 在流式下分片到达，按 index 累积
    const toolAcc = new Map<number, { id: string; name: string; args: string }>()
    let usage: ChatResult['usage']

    for await (const chunk of stream) {
      const choice = chunk.choices[0]
      if (choice) {
        const delta = choice.delta as {
          content?: string | null
          reasoning_content?: string | null
          tool_calls?: Array<{
            index: number
            id?: string
            function?: { name?: string; arguments?: string }
          }>
        }

        // GLM 思考阶段：reasoning_content 增量，单独推
        if (delta.reasoning_content) {
          handlers.onReasoning?.(delta.reasoning_content)
        }
        if (delta.content) {
          text += delta.content
          handlers.onToken?.(delta.content)
        }
        if (delta.tool_calls) {
          for (const tc of delta.tool_calls) {
            const cur = toolAcc.get(tc.index) ?? { id: '', name: '', args: '' }
            if (tc.id) cur.id = tc.id
            if (tc.function?.name) cur.name = tc.function.name
            if (tc.function?.arguments) cur.args += tc.function.arguments
            toolAcc.set(tc.index, cur)
          }
        }
      }
      // usage 通常在最后一个 chunk（include_usage）
      if (chunk.usage) {
        const u = chunk.usage as OpenAI.Completions.CompletionUsage & {
          prompt_tokens_details?: { cached_tokens?: number }
        }
        usage = {
          promptTokens: u.prompt_tokens,
          completionTokens: u.completion_tokens,
          totalTokens: u.total_tokens,
          cachedTokens: u.prompt_tokens_details?.cached_tokens ?? 0,
        }
      }
    }

    const toolCalls: ToolCall[] = [...toolAcc.entries()]
      .sort((a, b) => a[0] - b[0])
      .map(([, v]) => ({
        id: v.id,
        type: 'function' as const,
        function: { name: v.name, arguments: v.args },
      }))

    return { text, toolCalls, usage }
  }

  /** 非流式调用：用于上下文压缩的摘要请求（纯文本进出，不带工具） */
  async complete(messages: ChatMessage[]): Promise<string> {
    const resp = await this.client.chat.completions.create({
      model: this.model,
      messages: messages as OpenAI.Chat.ChatCompletionMessageParam[],
      stream: false,
    })
    return resp.choices[0]?.message?.content ?? ''
  }
}
