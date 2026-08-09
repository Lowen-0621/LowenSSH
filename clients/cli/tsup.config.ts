import { defineConfig } from 'tsup'

// 打包配置：把 TUI 入口和 bin 入口打成 ESM。
// ssh2 含原生依赖，标记 external 不打进 bundle，由 node_modules 提供。
export default defineConfig({
  entry: {
    cli: 'src/cli.tsx',
  },
  format: ['esm'],
  target: 'node20',
  platform: 'node',
  banner: { js: '#!/usr/bin/env node' },
  clean: true,
  external: ['ssh2', 'react', 'ink', 'openai'],
})
