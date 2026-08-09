/**
 * LowenSSH CLI 入口。读配置 → 渲染 TUI。
 * apiKey 缺失时给出明确提示（环境变量 GLM_API_KEY 或写进配置文件），不静默失败。
 */
import { render, Box, Text } from 'ink'
import { loadConfig, CONFIG_FILE } from './core/config.js'
import { App } from './ui/App.js'
import { AddHost } from './ui/AddHost.js'

const command = process.argv[2]

// 子命令：add-host —— 加主机不依赖 apiKey，单独路由
if (command === 'add-host') {
  render(<AddHost />)
} else {
  const config = loadConfig()

  if (!config.llm.apiKey || config.llm.apiKey.trim() === '') {
    render(
      <Box flexDirection="column" padding={1}>
        <Text color="red">✗ 缺少 GLM API Key</Text>
        <Text dimColor>设置环境变量 GLM_API_KEY，或填进配置文件：</Text>
        <Text dimColor>{CONFIG_FILE}</Text>
      </Box>,
    )
  } else {
    render(<App config={config} />)
  }
}
