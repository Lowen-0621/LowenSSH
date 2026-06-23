/**
 * 顶层应用状态机。
 *
 * 三阶段：
 *   select  —— 选主机（或提示先去加主机）
 *   connect —— 正在 SSH 连接
 *   chat    —— 对话流，跑 agent loop
 *
 * Confirmer 桥：agent loop 在 ASK 态需要用户 y/n，但 loop 是异步 generator，
 * 不能直接读键盘。这里用一个 pending Promise 把 loop 的"等确认"和 UI 的按键解耦——
 * loop 调 confirmer() 拿到 Promise 并挂起，UI 渲染确认框，用户按键 resolve 这个 Promise。
 */
import { useState, useRef, useCallback } from 'react'
import { Box, Text } from 'ink'
import type { Host, AppConfig } from '../core/config.js'
import { getHostPassword } from '../core/config.js'
import { GlmClient } from '../core/glm.js'
import { SshClient } from '../core/ssh.js'
import type { Confirmer } from '../core/events.js'
import { HostSelect } from './HostSelect.js'
import { Chat } from './Chat.js'
import { ConfirmPrompt, type PendingConfirm } from './ConfirmPrompt.js'

type Stage = 'select' | 'connect' | 'chat' | 'fatal'

export interface AppProps {
  config: AppConfig
}

export function App({ config }: AppProps) {
  const [stage, setStage] = useState<Stage>('select')
  const [error, setError] = useState<string | null>(null)
  const [host, setHost] = useState<Host | null>(null)

  // 连接产物：连上后才有 ssh / llm 实例
  const sshRef = useRef<SshClient | null>(null)
  const llmRef = useRef<GlmClient | null>(null)

  // 当前挂起的确认请求（ASK 态）；null 表示没有待确认
  const [pendingConfirm, setPendingConfirm] = useState<PendingConfirm | null>(null)

  /** Confirmer：被 agent loop 调用，返回一个 Promise，UI 按键后 resolve */
  const confirmer = useCallback<Confirmer>((command, reason) => {
    return new Promise<boolean>((resolve) => {
      setPendingConfirm({ command, reason, resolve })
    })
  }, [])

  /** 用户在确认框按了 y/n */
  const onConfirm = useCallback((approved: boolean) => {
    setPendingConfirm((cur) => {
      cur?.resolve(approved)
      return null
    })
  }, [])

  /** 选定主机后建立连接 */
  const onPickHost = useCallback(
    async (picked: Host) => {
      setHost(picked)
      setStage('connect')
      try {
        const password = getHostPassword(picked)
        if (!password) {
          setError(`主机 ${picked.host} 未保存密码，请先在配置里补充。`)
          setStage('fatal')
          return
        }
        const ssh = new SshClient()
        await ssh.connect(picked.host, picked.port, picked.user, password)
        sshRef.current = ssh
        llmRef.current = new GlmClient(config.llm)
        setStage('chat')
      } catch (e) {
        setError(`连接失败: ${(e as Error).message}`)
        setStage('fatal')
      }
    },
    [config.llm],
  )

  if (stage === 'fatal') {
    return (
      <Box flexDirection="column" padding={1}>
        <Text color="red">✗ {error}</Text>
        <Text dimColor>按 Ctrl+C 退出。</Text>
      </Box>
    )
  }

  if (stage === 'select') {
    return <HostSelect hosts={config.hosts} onPick={onPickHost} />
  }

  if (stage === 'connect') {
    return (
      <Box padding={1}>
        <Text color="cyan">◇ 正在连接 {host?.host} …</Text>
      </Box>
    )
  }

  // chat
  return (
    <Box flexDirection="column">
      <Chat
        host={host!}
        ssh={sshRef.current!}
        llm={llmRef.current!}
        confirmer={confirmer}
        inputLocked={pendingConfirm !== null}
      />
      {pendingConfirm && <ConfirmPrompt pending={pendingConfirm} onAnswer={onConfirm} />}
    </Box>
  )
}
