/**
 * 上下文管理 —— 防止 agentic loop 多轮滚下来把模型上下文撑爆。
 * 移植自 Java 版 ContextManager，只做两层（抄 Claude Code 思路）：
 *
 *  Layer 0 —— 大工具结果截断：单条工具结果超阈值截掉中段，留头尾 + 提示。
 *             分级：最近 K 条用大阈值保细节，更早的用小阈值大力收紧 →
 *             token 不随轮数线性膨胀，且按"距末尾距离"判定，跨轮稳定不破坏缓存前缀。
 *
 *  Layer 4 —— 历史压缩：整段估算 token 超阈值，把较早对话丢给 LLM 摘要成一条，
 *             保留 system + 最近 K 条原文。成对约束：保留区不能以孤儿 tool 消息开头。
 *             摘要连续失败到熔断阈值就停止压缩、裸跑兜底。
 *
 * token 用字符数粗估：中英混合约 2.5 字符/token，不引 tokenizer。
 */
import type { ChatMessage } from './glm.js'
import type { GlmClient } from './glm.js'

const CHARS_PER_TOKEN = 2.5
const TRUNCATE_MARKER = '完整结果见历史记录'

export interface ContextOptions {
  toolResultMaxChars: number //    Layer 0 近区阈值
  oldToolResultMaxChars: number // Layer 0 旧区阈值
  maxContextTokens: number //      Layer 4 触发压缩阈值
  keepRecentMessages: number //    Layer 4 保留最近条数
  circuitLimit: number //          摘要连续失败熔断次数
}

export const DEFAULT_CONTEXT_OPTIONS: ContextOptions = {
  toolResultMaxChars: 8000,
  oldToolResultMaxChars: 800,
  maxContextTokens: 32000,
  keepRecentMessages: 6,
  circuitLimit: 3,
}

const SUMMARY_PROMPT = `你是上下文压缩器。下面是一段 AI 运维助手与目标服务器之间的历史对话（含用户任务、助手发起的命令调用、命令执行结果）。
请把它压缩成简洁的中文摘要，必须保留以下信息，丢弃冗长的原始命令输出（只留结论）：
1. 用户的原始运维目标；
2. 已执行过的关键命令及其结果结论（例如磁盘占用多少、进程是否存活、配置是否正确）；
3. 已发现的问题或系统状态；
4. 被安全门禁拦截的危险操作（如果有）。
只输出摘要正文，不要解释你在做什么。`

export class ContextManager {
  private opts: ContextOptions
  private llm: GlmClient
  private consecutiveFailures = 0

  constructor(llm: GlmClient, opts: ContextOptions = DEFAULT_CONTEXT_OPTIONS) {
    this.llm = llm
    this.opts = opts
  }

  // ===================== Layer 0：工具结果截断 =====================

  /**
   * 对历史里所有工具结果做截断（幂等）。返回新数组，不改原数组。
   * 分级：距末尾 keepRecentMessages 条内用大阈值，更早用小阈值。
   */
  truncateToolResponses(messages: ChatMessage[]): ChatMessage[] {
    const size = messages.length
    return messages.map((msg, i) => {
      if (msg.role !== 'tool') return msg
      const recent = size - i <= this.opts.keepRecentMessages
      const limit = recent ? this.opts.toolResultMaxChars : this.opts.oldToolResultMaxChars
      return { ...msg, content: this.truncateText(msg.content, limit) }
    })
  }

  /** 截掉中段，保留头 60% / 尾 40%，中间塞提示。幂等：含哨兵跳过。 */
  private truncateText(text: string, limit: number): string {
    if (!text || text.length <= limit) return text
    if (text.includes(TRUNCATE_MARKER)) return text
    const headLen = Math.floor(limit * 0.6)
    const tailLen = limit - headLen
    const cut = text.length - headLen - tailLen
    const head = text.slice(0, headLen)
    const tail = text.slice(text.length - tailLen)
    return `${head}\n...[已截断 ${cut} 字符，${TRUNCATE_MARKER}]...\n${tail}`
  }

  // ===================== Layer 4：历史压缩 =====================

  /** 估算超阈值时压缩历史，否则原样返回。 */
  async compressIfNeeded(messages: ChatMessage[]): Promise<ChatMessage[]> {
    if (this.consecutiveFailures >= this.opts.circuitLimit) return messages
    if (this.estimateTokens(messages) <= this.opts.maxContextTokens) return messages
    if (messages.length <= this.opts.keepRecentMessages + 1) return messages

    let cutIndex = messages.length - this.opts.keepRecentMessages
    // 保留区不能以孤儿 tool 消息开头（它的 tool_call 在 assistant 上，会被切走）
    while (cutIndex > 1 && messages[cutIndex]?.role === 'tool') {
      cutIndex--
    }
    if (cutIndex <= 1) return messages

    const summaryRegion = messages.slice(1, cutIndex)
    const summary = await this.summarize(summaryRegion)
    if (summary === null) {
      this.consecutiveFailures++
      return messages
    }
    this.consecutiveFailures = 0

    return [
      messages[0]!, // system
      { role: 'user', content: '以下是早先对话的摘要，供你继续任务时参考：\n' + summary },
      ...messages.slice(cutIndex),
    ]
  }

  /** 调摘要 LLM 把一段历史压成结论文本；失败返回 null */
  private async summarize(region: ChatMessage[]): Promise<string | null> {
    try {
      const rendered = this.renderRegion(region)
      const text = await this.llm.complete([
        { role: 'system', content: SUMMARY_PROMPT },
        { role: 'user', content: rendered },
      ])
      return text && text.trim() !== '' ? text : null
    } catch {
      return null
    }
  }

  /** 把一段消息渲染成纯文本喂给摘要 LLM */
  private renderRegion(region: ChatMessage[]): string {
    const lines: string[] = []
    for (const msg of region) {
      if (msg.role === 'user') {
        lines.push('用户: ' + msg.content)
      } else if (msg.role === 'assistant') {
        if (msg.content) lines.push('助手: ' + msg.content)
        for (const call of msg.tool_calls ?? []) {
          lines.push(`助手调用工具 ${call.function.name}: ${call.function.arguments}`)
        }
      } else if (msg.role === 'tool') {
        lines.push(`工具结果: ${msg.content}`)
      }
    }
    return lines.join('\n')
  }

  // ===================== 工具方法 =====================

  /** 估算整段消息的 token 数（字符数粗估） */
  estimateTokens(messages: ChatMessage[]): number {
    let chars = 0
    for (const msg of messages) {
      if (msg.role === 'assistant') {
        chars += msg.content?.length ?? 0
        for (const call of msg.tool_calls ?? []) {
          chars += call.function.arguments?.length ?? 0
        }
      } else {
        chars += msg.content?.length ?? 0
      }
    }
    return Math.floor(chars / CHARS_PER_TOKEN)
  }
}
