/**
 * Agent 核心 —— 手写的 agentic loop + 安全门禁。
 * 移植自 Java 版 AgentService，对外用 async generator 吐 6 类事件。
 *
 * 循环结构（Claude Code 同款状态机）：
 *   请求 → 模型返回 → 有 tool_call？
 *     有 → 门禁预检 → 全放行才执行工具 → 结果回灌 → 带新历史再请求
 *           任一被拒 → 不执行，回灌"拒绝"作为工具结果 → loop 继续让模型换方案
 *     无 → 模型给出最终结论，循环结束
 *   加最大轮数上限防死循环。
 *
 * 安全是独立代码路径：门禁不写进工具、不靠模型自觉，越狱也绕不过。
 */
import { evaluate } from './guard.js'
import type { SshClient } from './ssh.js'
import type { GlmClient, ChatMessage, ToolCall, ToolDef } from './glm.js'
import { ContextManager } from './context.js'
import type { AgentEvent, Confirmer } from './events.js'

const MAX_ROUNDS = 40
const EXEC_TOOL = 'execCommand'

const SYSTEM_PROMPT = `## 身份
你是 LowenSSH，一个面向 Linux 服务器的 SSH/SFTP 智能体。
你帮用户远程排查问题、执行命令、读取文件、查看日志，并在用户授权下完成文件传输等运维操作。
你的能力随工具集扩展——当前可用的工具见工具列表，只调用列表里实际存在的工具，不要臆造工具。

## 环境与安全
你执行的每条命令都会经过一道独立的安全门禁，危险命令会被拦截。
被拦时换一个更安全的方式达成目标，不要重复同一条被拒命令，也不要改用等价的危险命令绕过拦截。

## 工作方式
- 先理解任务目标再决定查什么，每步拿到结果后判断下一步，不要一次堆一堆命令。
- 优先用只读命令探查（df / free / ps / cat / tail），看清现状再动有副作用的操作。
- 命令输出可能被截断（节省 token），抓关键信息即可，需要时再精确查询。

## 输出格式
- 用中文，给出结论，不要只罗列原始命令输出。
- 简单结果用自然语言简短回答，多维度信息才用列表或表格。
- 关键数字（磁盘占用 %、内存、负载等）直接点出来，别让用户自己从输出里找。`

/** 工具集 schema —— 与 Java 版 SshTools 的 @Tool 对齐 */
const TOOLS: ToolDef[] = [
  {
    type: 'function',
    function: {
      name: 'execCommand',
      description:
        '在目标服务器上执行一条 shell 命令，返回标准输出、错误输出和退出码。用于查看系统状态、进程、磁盘等运维操作。',
      parameters: {
        type: 'object',
        properties: {
          command: { type: 'string', description: "要执行的 shell 命令，例如 'df -h'" },
        },
        required: ['command'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'readRemoteFile',
      description: '读取目标服务器上指定路径的文本文件的完整内容。',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: "远程文件绝对路径，例如 '/etc/nginx/nginx.conf'" },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'tailLog',
      description: '读取目标服务器上日志文件的末尾若干行，用于快速查看最新日志。',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: '日志文件绝对路径' },
          lines: { type: 'number', description: '读取末尾的行数，例如 100' },
        },
        required: ['path', 'lines'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'listFiles',
      description: '列出目标服务器上指定目录的文件和子目录。',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: "目录绝对路径，例如 '/var/log'" },
        },
        required: ['path'],
      },
    },
  },
]

/** 执行一个工具调用，返回喂回模型的文本结果。只读工具直接跑；execCommand 已过门禁。 */
async function runTool(ssh: SshClient, name: string, args: Record<string, unknown>): Promise<string> {
  try {
    switch (name) {
      case 'execCommand': {
        const r = await ssh.exec(String(args.command ?? ''))
        return formatExec(r)
      }
      case 'readRemoteFile': {
        const r = await ssh.exec(`cat '${args.path}'`)
        return formatExec(r)
      }
      case 'tailLog': {
        const r = await ssh.exec(`tail -n ${Number(args.lines) || 100} '${args.path}'`)
        return formatExec(r)
      }
      case 'listFiles': {
        const files = await ssh.listDir(String(args.path ?? ''))
        if (files.length === 0) return '（空目录）' + args.path
        const lines = files.map(
          (f) => `${f.isDir ? '[d]' : '[f]'} ${f.name}  ${f.isDir ? '-' : f.size + 'B'}  ${f.perms}`,
        )
        return `目录 ${args.path} 共 ${files.length} 项:\n` + lines.join('\n')
      }
      default:
        return `未知工具: ${name}`
    }
  } catch (e) {
    // 工具内部异常不抛给 loop，作为"工具结果"回灌，让模型知道这步失败
    return `命令执行异常: ${(e as Error).message}`
  }
}

function formatExec(r: { stdout: string; stderr: string; exitCode: number }): string {
  let s = `exitCode=${r.exitCode}\n`
  if (r.stdout) s += `stdout:\n${r.stdout}`
  if (r.stderr) s += `stderr:\n${r.stderr}`
  return s
}

/** 从 tool_call 参数 JSON 取出 command 字段 */
function extractCommand(argsJson: string): string {
  try {
    const obj = JSON.parse(argsJson) as { command?: string }
    return obj.command ?? ''
  } catch {
    return ''
  }
}

export interface AgentDeps {
  llm: GlmClient
  ssh: SshClient
  confirmer: Confirmer
  /** 历史消息（多轮续聊）。首轮传空数组。loop 结束后调用方可读回更新后的历史。 */
  history?: ChatMessage[]
}

/**
 * 跑一轮 agent 任务，以 async generator 吐事件流。
 * 调用方 for-await 消费事件；事件语义见 events.ts。
 */
export async function* runAgent(task: string, deps: AgentDeps): AsyncGenerator<AgentEvent> {
  const { llm, ssh, confirmer } = deps
  const ctx = new ContextManager(llm)

  let messages: ChatMessage[] = [
    { role: 'system', content: SYSTEM_PROMPT },
    ...(deps.history ?? []),
    { role: 'user', content: task },
  ]

  for (let round = 1; round <= MAX_ROUNDS; round++) {
    // 进模型前整理上下文：Layer 0 截断 + Layer 4 压缩
    messages = ctx.truncateToolResponses(messages)
    messages = await ctx.compressIfNeeded(messages)

    // 一次流式调用：边推 token/reasoning 边聚合
    const pending: AgentEvent[] = []
    const result = await llm.stream(messages, TOOLS, {
      onToken: (t) => pending.push({ type: 'token', text: t }),
      onReasoning: (t) => pending.push({ type: 'reasoning', text: t }),
    })
    // 把流式期间攒的增量事件吐出去
    for (const ev of pending) yield ev

    // 没有 tool_call：模型给出最终结论，结束
    if (result.toolCalls.length === 0) {
      const text = result.text?.trim() || '模型暂时没有返回内容，请重试。'
      yield { type: 'done', finalText: text }
      return
    }

    // 落 assistant（文字 + tool_calls）
    const assistant: ChatMessage = {
      role: 'assistant',
      content: result.text || null,
      tool_calls: result.toolCalls,
    }
    // 先把本轮要调的工具吐出去
    for (const call of result.toolCalls) {
      yield { type: 'tool_call', name: call.function.name, args: call.function.arguments }
    }

    // —— 门禁预检 + 执行 ——
    const toolResponses: ChatMessage[] = []
    let anyRejected = false

    for (const call of result.toolCalls) {
      const reject = await screenAndRun(call, ssh, confirmer, (ev) => pending.push(ev))
      // screenAndRun 把 blocked/tool_result 事件塞进 pending
      toolResponses.push({ role: 'tool', tool_call_id: call.id, content: reject.content })
      if (reject.rejected) anyRejected = true
    }
    // 吐出执行阶段攒的事件（blocked / tool_result）
    for (const ev of pending) yield ev
    pending.length = 0

    // 回灌历史：assistant + 所有 tool 结果（被拒的也回灌"拒绝"文本，让模型换方案）
    messages.push(assistant, ...toolResponses)
    void anyRejected // 拒绝与否都已通过 tool 结果回灌，loop 自然继续
  }

  yield {
    type: 'done',
    finalText: `已达到最大循环轮数（${MAX_ROUNDS}），任务可能未完成。请拆分任务后重试。`,
  }
}

/**
 * 对单个 tool_call 过门禁并执行。
 * 返回 { content, rejected }：content 是回灌给模型的文本，rejected 表示被拒未执行。
 * 通过 emit 推 blocked / tool_result 事件。
 */
async function screenAndRun(
  call: ToolCall,
  ssh: SshClient,
  confirmer: Confirmer,
  emit: (ev: AgentEvent) => void,
): Promise<{ content: string; rejected: boolean }> {
  const name = call.function.name
  let args: Record<string, unknown> = {}
  try {
    args = JSON.parse(call.function.arguments) as Record<string, unknown>
  } catch {
    // 参数解析失败，交给工具自己处理（会报错回灌）
  }

  // 非 execCommand 的工具（读文件/看日志/列目录）只读，直接放行
  if (name !== EXEC_TOOL) {
    const content = await runTool(ssh, name, args)
    emit({ type: 'tool_result', name, summary: summarize(content), executed: true })
    return { content, rejected: false }
  }

  const command = extractCommand(call.function.arguments)
  const verdict = evaluate(command)

  if (verdict.decision === 'DENY') {
    const reason = verdict.reason
    emit({ type: 'blocked', command, reason })
    return {
      content: `命令被安全门禁拒绝执行（${reason}）。请改用更安全的方式。`,
      rejected: true,
    }
  }

  if (verdict.decision === 'ASK') {
    const ok = await confirmer(command, verdict.reason)
    if (!ok) {
      emit({ type: 'blocked', command, reason: '用户拒绝: ' + verdict.reason })
      return { content: '用户拒绝执行该命令。请换一种方式或询问用户。', rejected: true }
    }
  }

  // ALLOW 或 ASK 已批准：执行
  const content = await runTool(ssh, name, args)
  emit({ type: 'tool_result', name, summary: summarize(content), executed: true })
  return { content, rejected: false }
}

/** 工具结果摘要：超 500 字符截断（仅用于事件展示，回灌给模型的是完整内容） */
function summarize(data: string): string {
  return data.length > 500 ? data.slice(0, 500) + '…' : data
}

export { TOOLS, SYSTEM_PROMPT, MAX_ROUNDS }
