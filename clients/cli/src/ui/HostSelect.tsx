/**
 * 主机选择界面。上下键移动光标，回车连接。
 * 没有主机时提示去配置文件加主机（内置版主机簿在 ~/.lowenssh/config.json）。
 */
import { useState } from 'react'
import { Box, Text, useInput } from 'ink'
import type { Host } from '../core/config.js'
import { CONFIG_FILE } from '../core/config.js'

export interface HostSelectProps {
  hosts: Host[]
  onPick: (host: Host) => void
}

export function HostSelect({ hosts, onPick }: HostSelectProps) {
  const [cursor, setCursor] = useState(0)

  useInput((input, key) => {
    if (hosts.length === 0) return
    if (key.upArrow || input === 'k') {
      setCursor((c) => (c - 1 + hosts.length) % hosts.length)
    } else if (key.downArrow || input === 'j') {
      setCursor((c) => (c + 1) % hosts.length)
    } else if (key.return) {
      onPick(hosts[cursor]!)
    }
  })

  return (
    <Box flexDirection="column" padding={1}>
      <Text color="cyan">▰ LowenSSH</Text>
      <Text dimColor>选择要连接的主机（↑↓ 移动，回车连接，Ctrl+C 退出）</Text>
      <Box marginTop={1} flexDirection="column">
        {hosts.length === 0 ? (
          <Box flexDirection="column">
            <Text color="yellow">还没有主机。</Text>
            <Text dimColor>请编辑配置文件添加：{CONFIG_FILE}</Text>
          </Box>
        ) : (
          hosts.map((h, i) => {
            const active = i === cursor
            const label = h.alias ? `${h.alias} (${h.user}@${h.host}:${h.port})` : `${h.user}@${h.host}:${h.port}`
            return (
              <Text key={h.id} color={active ? 'cyan' : undefined}>
                {active ? '❯ ' : '  '}
                {label}
              </Text>
            )
          })
        )}
      </Box>
    </Box>
  )
}
