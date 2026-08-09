/**
 * 交互式添加主机表单（`lowenssh add-host`）。
 *
 * 逐字段填写，回车进下一项：alias → host → port → user → password。
 * - host 必填，空则停留当前字段
 * - port 默认 22，user 默认 root（直接回车用默认值）
 * - password 用 mask 隐藏输入；存库时由 config.addHost 走 AES-GCM 加密，绝不存明文
 * 全部填完保存到 ~/.lowenssh/config.json 并退出。
 */
import { useState } from 'react'
import { Box, Text, useApp } from 'ink'
import TextInput from 'ink-text-input'
import { addHost } from '../core/config.js'

/** 表单字段定义：按 steps 顺序逐个填写 */
interface FieldDef {
  key: 'alias' | 'host' | 'port' | 'user' | 'password'
  label: string
  placeholder: string
  mask?: boolean
  required?: boolean
}

const FIELDS: FieldDef[] = [
  { key: 'alias', label: '别名（可选）', placeholder: '如 生产-web01，可留空' },
  { key: 'host', label: '主机地址', placeholder: 'IP 或域名', required: true },
  { key: 'port', label: '端口', placeholder: '22' },
  { key: 'user', label: '用户名', placeholder: 'root' },
  { key: 'password', label: '密码（可选）', placeholder: '留空则连接时不带密码', mask: true },
]

export function AddHost() {
  const { exit } = useApp()
  const [step, setStep] = useState(0)
  const [value, setValue] = useState('')
  const [draft, setDraft] = useState<Record<string, string>>({})
  const [saved, setSaved] = useState<string | null>(null)

  const onSubmit = () => {
    const field = FIELDS[step]!
    const v = value.trim()
    // 必填字段空则不放行
    if (field.required && v === '') return

    const nextDraft = { ...draft, [field.key]: v }
    setDraft(nextDraft)
    setValue('')

    if (step < FIELDS.length - 1) {
      setStep(step + 1)
      return
    }

    // 最后一项：保存
    const host = addHost({
      alias: nextDraft.alias || undefined,
      host: nextDraft.host!,
      port: nextDraft.port ? Number(nextDraft.port) : 22,
      user: nextDraft.user || 'root',
      password: nextDraft.password || undefined,
    })
    const label = host.alias ? `${host.alias} (${host.user}@${host.host}:${host.port})` : `${host.user}@${host.host}:${host.port}`
    setSaved(label)
    // 渲染成功提示后退出
    setTimeout(() => exit(), 50)
  }

  if (saved) {
    return (
      <Box flexDirection="column" padding={1}>
        <Text color="green">✓ 已添加主机：{saved}</Text>
        <Text dimColor>密码已加密存入 ~/.lowenssh/config.json，直接运行 lowenssh 即可连接。</Text>
      </Box>
    )
  }

  const field = FIELDS[step]!
  return (
    <Box flexDirection="column" padding={1}>
      <Text color="cyan">▰ 添加主机（回车下一项，Ctrl+C 取消）</Text>
      {/* 已填字段回显 */}
      <Box flexDirection="column" marginTop={1}>
        {FIELDS.slice(0, step).map((f) => (
          <Text key={f.key} dimColor>
            {f.label}：{f.mask ? maskValue(draft[f.key]) : draft[f.key] || '（默认）'}
          </Text>
        ))}
      </Box>
      {/* 当前字段输入 */}
      <Box marginTop={step > 0 ? 1 : 0}>
        <Text color="cyan">{field.label}：</Text>
        <TextInput
          value={value}
          onChange={setValue}
          onSubmit={onSubmit}
          placeholder={field.placeholder}
          mask={field.mask ? '*' : undefined}
        />
      </Box>
    </Box>
  )
}

/** 密码回显成等长星号，空值显示"（无）" */
function maskValue(v?: string): string {
  if (!v) return '（无）'
  return '*'.repeat(v.length)
}
