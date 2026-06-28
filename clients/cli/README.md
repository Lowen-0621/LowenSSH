# LowenSSH CLI

LowenSSH 的命令行形态，在终端里跑的 AI SSH 运维 Agent，交互体验类似 Claude Code。基于 Node + Ink（TUI）。

内置全套逻辑——SSH 连接、手写 Agent loop、安全门禁、上下文管理、直连大模型——**不依赖项目的 Java 后端**，独立运行。

## 环境要求

- Node.js 20+

## 安装依赖

```bash
cd clients/cli
npm install
```

## 大模型配置

CLI 需要大模型 API Key（默认接入 GLM，走 OpenAI 兼容协议）。两种方式，环境变量优先：

```bash
export GLM_API_KEY='你的智谱AI key'      # https://open.bigmodel.cn 申请
```

或写进配置文件 `~/.lowenssh/config.json`（文件权限 600）。缺 Key 时启动会给出明确提示，不会静默失败。

## 运行

开发模式（直接跑 TS 源码）：

```bash
npm run dev              # 启动交互式 TUI
npm run dev add-host     # 添加主机（无需 API Key）
```

构建后作为命令安装：

```bash
npm run build            # 产物输出到 dist/
npm link                 # 注册全局命令 lowenssh
lowenssh                 # 启动
lowenssh add-host        # 添加主机
```

## 开发

```bash
npm test                 # vitest 跑单测（门禁、加密）
npm run typecheck        # tsc 类型检查
```

## 安全说明

- 主机密码 AES-GCM 加密后落盘，配置文件权限 600，不存明文。
- 环境变量注入的 API Key 不会被写回配置文件。
- 安全门禁的高危命令规则与后端、桌面端对齐，是真实防护。
- 这是一个运维 Agent，会真实在目标服务器执行命令。请只连接你有权操作的服务器。
