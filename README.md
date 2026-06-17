# XiaowenSSH

AI 驱动的 SSH 智能运维 Agent。给它一个运维目标和一台服务器，它会像工程师一样一步步排查：自己决定跑什么命令、读结果、调整思路，直到给出结论。危险命令会被安全门禁实时拦截。

> 这是一个面试项目，演示如何从零手写一个 agentic loop，而不是套用现成框架。核心看点是「看得见 AI 在干什么，也看得见安全护栏起作用」。

## 能力

- **手写 Agentic Loop**：不依赖 LangChain 之类的编排框架，自己实现「模型决策 → 调工具 → 喂回结果 → 再决策」的循环，逻辑完全可控、可读。
- **安全门禁三态**：每条命令在执行前经过 `deny / ask / allow` 判定。`rm -rf`、`find -delete` 等高危操作直接拦截，模型被拦后会自主改用安全方式。
- **流式可视化**：SSE 实时推送 6 类事件（模型 token、要跑的命令、命令结果、被拦截、最终结论、错误），前端逐字渲染整个排查过程。
- **上下文管理**：多轮对话爆 context 时，自动做大工具结果截断 + 全量 LLM 摘要，复用消息表持久化。
- **双前端**：图形版（产品形态）和终端版（工具形态），同一套会话状态，两种界面随时切换。
- **全程审计**：每次连接、每条命令、每个拦截决策都落库，可追溯。

## 技术栈

**后端**：Java 17 · Spring Boot 3.4 · Spring AI 1.1 · JSch（SSH）· MyBatis-Plus · MySQL · GLM-4.6

**前端**：Vite 6 · Vue 3.5（Composition API）· vue-router 4

## 快速开始

### 1. 准备环境变量

应用读取两个环境变量，源码里不含任何明文密钥：

```bash
export MYSQL_PASSWORD='你的MySQL密码'   # 本机 MySQL root 密码，空密码则设为 ''
export GLM_API_KEY='你的智谱AI key'      # https://open.bigmodel.cn 申请
```

> 不设这两个变量，启动会因连不上 MySQL（500）或鉴权失败（401）而报错。

### 2. 初始化数据库

先建库,再执行建表脚本:

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS xiaowenssh DEFAULT CHARSET utf8mb4;"
mysql -u root -p xiaowenssh < src/main/resources/schema.sql
```

### 3. 构建前端

```bash
cd frontend
npm install
npm run build      # 产物输出到 ../src/main/resources/static/，由后端直接托管
```

### 4. 启动后端

```bash
mvn spring-boot:run
```

访问 http://localhost:8081 即可使用（前端和 API 同端口）。

### 开发模式（前后端分离调试）

```bash
cd frontend && npm run dev    # dev server 在 5173，/api 自动代理到后端 8081
```

## 项目结构

```
xiaowenssh/
├── src/main/java/com/xiaowenssh/
│   ├── agent/          # Agent 核心：loop、SSE 事件、上下文管理、安全门禁
│   ├── ssh/            # JSch SSH 执行
│   └── ...
├── src/main/resources/
│   ├── application.yml # 配置（密钥走环境变量）
│   ├── schema.sql      # 建表脚本
│   └── static/         # 前端构建产物（npm run build 生成）
├── frontend/           # Vite + Vue3 双界面前端（见 frontend/README.md）
└── DESIGN.md           # 前端设计规范
```

## 安全说明

- 所有密钥走环境变量，源码无任何明文凭据。
- 前端密码字段不写入 localStorage/sessionStorage，不打印到控制台。
- 安全门禁的高危命令规则（含 `rm -rf`、`find -delete` 等变体）是真实防护，请勿在生产前移除。
- 这是一个运维 Agent，会真实在目标服务器执行命令。请只连接你有权操作的服务器。

## License

MIT
