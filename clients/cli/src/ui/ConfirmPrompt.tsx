/**
 * ASK 态确认框：危险但可控的命令（rm / kill / chmod 等）执行前弹出，等用户 y/n。
 * 命令文本完整展示，让用户看清要批准什么再决定。
 */
import { Box, Text, useInput } from 'ink'

/** 一个挂起的确认请求：loop 提供 command/reason 和待 resolve 的回调 */
export interface PendingConfirm {
  command: string
  reason: string
  resolve: (approved: boolean) => void
}

export interface ConfirmPromptProps {
  pending: PendingConfirm
  onAnswer: (approved: boolean) => void
}

export function ConfirmPrompt({ pending, onAnswer }: ConfirmPromptProps) {
  useInput((input, key) => {
    if (input === 'y' || input === 'Y') {
      onAnswer(true)
    } else if (input === 'n' || input === 'N' || key.escape) {
      onAnswer(false)
    }
  })

  return (
    <Box flexDirection="column" borderStyle="round" borderColor="yellow" paddingX={1} marginTop={1}>
      <Text color="yellow">⚠ 需要确认 —— {pending.reason}</Text>
      <Text>
        <Text dimColor>$ </Text>
        <Text color="white">{pending.command}</Text>
      </Text>
      <Text dimColor>执行？ [y] 批准 / [n] 拒绝</Text>
    </Box>
  )
}
