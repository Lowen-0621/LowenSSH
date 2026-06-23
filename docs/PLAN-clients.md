# LowenSSH 多端客户端实施计划（App 端 + 终端端）

## 目标
在现有 Web 版（Vue + Spring Boot，单端口 8081）之外，新增两个**独立客户端**，各自**内置逻辑**（不依赖 Spring Boot 后端，自己实现 SSH + Agent loop + 门禁 + 调 GLM）：

- **App 端** = 独立桌面应用程序（非网页），适配 macOS + Windows，体验优先 → **Flutter Desktop**
- **终端端** = 在 terminal 里跑、类似 Claude Code 的 CLI/TUI，适配 macOS + Windows → **Node.js + Ink**

代码复用策略：**各自独立实现**。终端端用 TS 一套核心，App 端用 Dart 一套核心。门禁规则与 6 类事件语义两端手动对齐。

## 必须从现有 Java 后端移植的核心逻辑（已读透）
1. **Agent loop**（AgentService）：手写 agentic 循环。关闭框架自动执行工具 → 拿到 tool_call → 门禁预检 → 全放行才执行 → 结果回灌 → 带新历史再请求；任一被拒则回灌"拒绝"结果让模型换方案。最大轮数上限防死循环（默认 40）。
2. **门禁三态**（CommandGuard）：DENY/ASK/ALLOW，纯函数。先 deny 再 ask 后 allow；复合命令按 `&& || | ; 换行` 拆段取最严。DENY/ASK 正则名单需 1:1 移植（rm -rf、mkfs、dd、shutdown、find -delete 等）。
3. **6 类 SSE 事件语义**（AgentEvent）：token / reasoning / tool_call / tool_result / blocked / done / error / session_ready / session_expired。语义色是记忆点核心，两端对齐。
4. **SSH 执行**（SshClient）：长连接复用，exec 收集 stdout/stderr/exitCode；SFTP 列目录/删/建/移。
5. **上下文管理**（ContextManager）：Layer 0 工具结果分级截断 + Layer 4 历史超阈值 LLM 摘要压缩（带熔断）。
6. **GLM 接入**：OpenAI 兼容协议，base-url `https://open.bigmodel.cn/api/paas/v4`，completions-path `/chat/completions`，model `glm-4.6/4.7`，需支持 function calling + streaming + reasoning_content。
7. **密码加密**（CryptoUtil）：AES-256-GCM，密文 = Base64(iv[12]+ct+tag[16])，密钥 SHA-256 派生。

## 安全要点（内置带来的）
- API key 与主机密码改为**本地存储**：App 端用系统钥匙串（macOS Keychain / Windows Credential Manager），终端端用本地配置文件（`~/.lowenssh/config`，权限 600）+ 复用 AES-GCM 加密。
- 绝不把密码/key 回显或上报。门禁是独立代码路径，不写进工具、不靠模型自觉。

---

## 阶段划分

### 阶段 1：终端端（Node.js + Ink）—— 先做，验证核心逻辑
工程独立放在 `clients/cli/`。

1.1 脚手架：TS + Ink + ink 相关库；`bin` 入口；`tsup`/`esbuild` 打包；目标 `npx lowenssh` 或全局安装。
1.2 核心库 `src/core/`（纯逻辑，无 UI，可单测）：
   - `guard.ts` — 门禁三态（1:1 移植正则）
   - `ssh.ts` — SSH 执行（用 `ssh2` 库）
   - `glm.ts` — OpenAI 兼容 client（用官方 openai sdk 指 base-url，或 fetch 手写）
   - `agent.ts` — 手写 loop，对外吐 6 类事件（EventEmitter / async generator）
   - `context.ts` — 上下文截断 + 压缩
   - `crypto.ts` — AES-GCM
   - `config.ts` — 本地配置读写（host 簿、API key）
1.3 TUI 层 `src/ui/`：主机选择 → 对话流（token 流式渲染、tool_call 折叠、blocked 红色高亮、reasoning 灰显）→ ASK 态命令交互式确认（y/n）。
1.4 验证：单测门禁；真机连一台测试机跑通"查磁盘/查进程"。

### 阶段 2：App 端（Flutter Desktop）—— 体验优先
工程独立放在 `clients/app/`。

2.1 脚手架：Flutter desktop（macos + windows enable）；Riverpod 状态管理（你熟）；分层 data/domain/ui。
2.2 核心库 `lib/core/`（Dart 重写同一套逻辑）：
   - 门禁（移植正则）、SSH（用 `dartssh2`）、GLM（dio + SSE 解析）、loop、context、crypto（pointycastle）、安全存储（flutter_secure_storage）
2.3 UI：复刻并提升现有 HUD 指挥中心视觉（深空底 + 青色辉光 #2dd4bf），五个区：主机簿 / 对话 / 终端流 / 文件(SFTP) / 监控。
2.4 验证：mac 跑通；门禁单测；真机连测试机。

### 阶段 3：打磨与分发
- 终端端：发 npm（或单文件可执行）。
- App 端：mac `.dmg` + win 安装包；签名按需。
- 两端门禁规则集中成一份"规则清单"文档，保证一致。

---

## 建议先做哪一个
**建议先做终端端（阶段 1）**：工作量小、最快跑通核心 loop，验证门禁/事件/GLM 对接无误后，再把同一套逻辑用 Dart 重写进 App 端，风险最低。

## 待确认
- 先做哪个？（建议终端端先行）
- App 端 UI 是完全复刻现有 HUD 风格，还是借机做新设计？
- 是否需要两端都连同一个本地主机簿（共享配置文件），还是各存各的？
</content>
