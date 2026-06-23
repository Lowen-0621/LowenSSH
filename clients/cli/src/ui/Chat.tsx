/**
 * 对话主界面。输入任务 → 跑 agent loop → 流式渲染 6 类事件。
 *
 * 事件语义色（记忆点核心，与后端 SSE / App 端保持一致）：
 *   token      默认色，模型正文，逐字累积
 *   reasoning  灰显，模型思考过程
 *   tool_call  青色，要执行的工具（命令折叠成一行）
 *   tool_result 暗灰，工具结果摘要
 *   blocked    红色高亮，被门禁/用户拦截
 *   done       正文收尾
 *   error      红色，异常
 */
import { useState, useCallback } from 'react'
import { Box, Text } from 'ink'
import TextInput from 'ink-text-input'
import type { Host } from '../core/config.js'
import type { SshClient } from '../core/ssh.js'
import type { GlmClient, ChatMessage } from '../core/glm.js'
import type { Confirmer } from '../core/events.js'
import { runAgent } from '../core/agent.js'

/** 屏幕上的一条消息块（按语义渲染） */
interface Line {
  kind: 'user' | 'token' | 'reasoning' | 'tool_call' | 'tool_result' | 'blocked' | 'error'
  text: string
}

export interface ChatProps {
  host: Host
  ssh: SshClient
  llm: GlmClient
  confirmer: Confirmer
  /** ASK 确认框弹出时锁住输入，避免按键串进 TextInput */
  inputLocked: boolean
}

export function Chat({ host, ssh, llm, confirmer, inputLocked }: ChatProps) {
  const [lines, setLines] = useState<Line[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  // 多轮续聊历史：loop 之间累积（system 由 agent 内部加，这里只存 user/assistant/tool）
  const [history, setHistory] = useState<ChatMessage[]>([])

  const push = useCallback((line: Line) => {
    setLines((prev) => [...prev, line])
  }, [])

  /** 把流式 token 累积到最后一条 token 行，避免每个字一行 */
  const appendToken = useCallback((kind: 'token' | 'reasoning', text: string) => {
    setLines((prev) => {
      const last = prev[prev.length - 1]
      if (last && last.kind === kind) {
        const copy = prev.slice(0, -1)
        copy.push({ kind, text: last.text + text })
        return copy
      }
      return [...prev, { kind, text }]
    })
  }, [])

  const onSubmit = useCallback(async () => {
    const task = input.trim()
    if (!task || busy) return
    setInput('')
    setBusy(true)
    push({ kind: 'user', text: task })

    try {
      for await (const ev of runAgent(task, { llm, ssh, confirmer, history })) {
        switch (ev.type) {
          case 'token':
            appendToken('token', ev.text)
            break
          case 'reasoning':
            appendToken('reasoning', ev.text)
            break
          case 'tool_call':
            push({ kind: 'tool_call', text: `${ev.name}(${shorten(ev.args)})` })
            break
          case 'tool_result':
            push({ kind: 'tool_result', text: oneLine(ev.summary) })
            break
          case 'blocked':
            push({ kind: 'blocked', text: `⛔ 已拦截: ${ev.command}  —— ${ev.reason}` })
            break
          case 'done':
            // 最终结论作为一条 token 行收尾（若正文已流式输出过，done 文本可能与其重复，仍补一条确保完整）
            push({ kind: 'token', text: '\n' + ev.finalText })
            break
          case 'error':
            push({ kind: 'error', text: `✗ ${ev.message}` })
            break
        }
      }
      // 续聊：把本轮 user 追进历史（assistant/tool 由下一轮 agent 内部 messages 重建，
      // 这里保留 user 提问让模型有上下文）
      setHistory((h) => [...h, { role: 'user', content: task }])
    } catch (e) {
      push({ kind: 'error', text: `✗ ${(e as Error).message}` })
    } finally {
      setBusy(false)
    }
  }, [input, busy, llm, ssh, confirmer, history, push, appendToken])

  return (
    <Box flexDirection="column" padding={1}>
      <Text color="cyan">▰ {host.alias ?? host.host}</Text>
      <Box flexDirection="column" marginTop={1}>
        {lines.map((l, i) => (
          <LineView key={i} line={l} />
        ))}
      </Box>
      <Box marginTop={1}>
        {busy ? (
          <Text color="cyan">◇ 处理中…</Text>
        ) : (
          <>
            <Text color="cyan">❯ </Text>
            <TextInput
              value={input}
              onChange={setInput}
              onSubmit={onSubmit}
              focus={!inputLocked}
              placeholder="描述要排查/执行的任务，回车发送"
            />
          </>
        )}
      </Box>
    </Box>
  )
}

/** 单行渲染：按语义上色 */
function LineView({ line }: { line: Line }) {
  switch (line.kind) {
    case 'user':
      return <Text color="green">❯ {line.text}</Text>
    case 'token':
      return <Text>{line.text}</Text>
    case 'reasoning':
      return <Text dimColor>{line.text}</Text>
    case 'tool_call':
      return <Text color="cyan">⚙ {line.text}</Text>
    case 'tool_result':
      return <Text dimColor>↳ {line.text}</Text>
    case 'blocked':
      return <Text color="red">{line.text}</Text>
    case 'error':
      return <Text color="red">{line.text}</Text>
  }
}

/** 工具参数 JSON 折叠成短文本 */
function shorten(argsJson: string): string {
  const s = argsJson.replace(/\s+/g, ' ')
  return s.length > 80 ? s.slice(0, 80) + '…' : s
}

/** 多行摘要压成一行展示 */
function oneLine(text: string): string {
  const s = text.replace(/\n+/g, ' ┊ ')
  return s.length > 120 ? s.slice(0, 120) + '…' : s
}
