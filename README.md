# LowenSSH

AI 驱动的 SSH 智能运维 Agent。给它一个运维目标和一台服务器，它会像工程师一样一步步排查：自己决定跑什么命令、读结果、调整思路，直到给出结论。危险命令会被安全门禁实时拦截。

核心看点是「看得见 AI 在干什么，也看得见安全护栏起作用」——整个 agentic loop 是从零手写的，不套用任何编排框架。

## 三种形态

同一套「Agent loop + 安全门禁 + 上下文管理」理念，落地为三个独立实现，按需选用：

| 形态 | 目录 | 技术栈 | 说明 |
|------|------|--------|------|
| **后端服务** | `src/` | Java 17 · Spring Boot 3.4 · Spring AI | REST + SSE API，参考实现，逻辑最完整 |
| **桌面客户端** | `clients/app/` | Flutter（macOS / Windows） | 独立桌面应用，内置全套逻辑，直连大模型 |
| **CLI 客户端** | `clients/cli/` | Node 20 · Ink（TUI） | 终端里跑，类 Claude Code 的交互，内置全套逻辑 |

三者**互不依赖**：桌面端和 CLI 各自内置 SSH + Agent loop + 门禁 + 大模型调用，不需要先起后端。门禁规则与事件语义在三端手动对齐。

> 想了解手写 agentic loop、安全门禁、上下文管理的设计取舍，见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 能力

- **手写 Agentic Loop**：不依赖 LangChain 之类的编排框架，自己实现「模型决策 → 调工具 → 喂回结果 → 再决策」的循环，逻辑完全可控、可读。
- **安全门禁三态**：每条命令在执行前经过 `deny / ask / allow` 判定。`rm -rf`、`find -delete` 等高危操作直接拦截，模型被拦后会自主改用安全方式。
- **流式可视化**：实时推送多类事件（模型 token、要跑的命令、命令结果、被拦截、最终结论、错误），逐字渲染整个排查过程。
- **上下文管理**：多轮对话爆 context 时，自动做大工具结果截断 + 全量 LLM 摘要，复用消息表持久化。
- **全程审计**：每次连接、每条命令、每个拦截决策都落库，可追溯。

## 技术栈

**后端**：Java 17 · Spring Boot 3.4 · Spring AI 1.1 · JSch（SSH）· MyBatis-Plus · MySQL · GLM-4.6（OpenAI 兼容协议，可换任意兼容模型）

**桌面端**：Flutter · Dart（macOS / Windows 桌面）

**CLI**：Node 20 · TypeScript · Ink · ssh2 · openai SDK

## 快速开始（后端服务）

后端提供 REST + SSE API。客户端的运行方式见各自目录的 README（[桌面端](clients/app/README.md) · [CLI](clients/cli/README.md)）。

### 方式一：Docker 一键启动（推荐）

需要 Docker。两个密钥走环境变量，不写进任何文件：

```bash
export MYSQL_PASSWORD='给MySQL容器设的root密码'
export GLM_API_KEY='你的智谱AI key'      # https://open.bigmodel.cn 申请
docker compose up --build
```

compose 会自动起 MySQL（建库 + 执行 schema.sql 建表）、构建后端、等 DB 就绪后启动应用。API 监听 http://localhost:8081。

### 方式二：本地手动启动

#### 1. 准备环境变量

应用读取两个环境变量，源码里不含任何明文密钥：

```bash
export MYSQL_PASSWORD='你的MySQL密码'   # 本机 MySQL root 密码，空密码则设为 ''
export GLM_API_KEY='你的智谱AI key'      # https://open.bigmodel.cn 申请
```

> 不设这两个变量，启动会因连不上 MySQL（500）或鉴权失败（401）而报错。

#### 2. 初始化数据库

先建库，再执行建表脚本：

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS lowenssh DEFAULT CHARSET utf8mb4;"
mysql -u root -p lowenssh < src/main/resources/schema.sql
```

#### 3. 启动后端

项目自带 Maven Wrapper，无需预装 Maven：

```bash
./mvnw spring-boot:run        # Windows 用 mvnw.cmd
```

API 监听 http://localhost:8081。

## 项目结构

```
LowenSSH/
├── src/main/java/com/lowenssh/
│   ├── agent/          # Agent 核心：loop、SSE 事件、上下文管理、安全门禁
│   ├── ssh/            # JSch SSH 执行
│   └── ...
├── src/main/resources/
│   ├── application.yml # 配置（密钥走环境变量）
│   └── schema.sql      # 建表脚本
├── clients/
│   ├── app/            # Flutter 桌面客户端（见 clients/app/README.md）
│   └── cli/            # Node CLI 客户端（见 clients/cli/README.md）
└── DESIGN.md           # 设计规范
```

## 安全说明

- 所有密钥走环境变量，源码无任何明文凭据。
- 客户端密码字段不写入明文持久化（AES-GCM 加密落库），不打印到控制台。
- 安全门禁的高危命令规则（含 `rm -rf`、`find -delete` 等变体）是真实防护，请勿在生产前移除。
- 这是一个运维 Agent，会真实在目标服务器执行命令。请只连接你有权操作的服务器。

## License

[MIT](LICENSE)
