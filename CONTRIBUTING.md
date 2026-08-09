# 贡献指南

感谢你对 LowenSSH 的兴趣。这份指南帮你快速上手本地开发、了解项目约定与提交流程。

## 项目结构速览

LowenSSH 是「同一套理念、三种独立形态」的项目，三端互不依赖：

| 形态 | 目录 | 技术栈 |
|------|------|--------|
| 后端服务 | `src/` | Java 17 · Spring Boot 3.4 · Spring AI |
| 桌面客户端 | `clients/app/` | Flutter（macOS / Windows） |
| CLI 客户端 | `clients/cli/` | Node 20 · Ink（TUI） |

核心理念（手写 Agent loop + Deny/Ask/Allow 安全门禁 + 上下文管理）在三端各自实现，**门禁规则与事件语义需手动对齐**。改动涉及核心逻辑时，请留意是否需要同步到其他端。

设计取舍详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 本地开发环境

### 后端（`src/`）

需要 JDK 17。项目自带 Maven Wrapper，无需预装 Maven。

```bash
export MYSQL_PASSWORD='你的MySQL密码'
export GLM_API_KEY='你的智谱AI key'   # https://open.bigmodel.cn 申请

# 初始化数据库
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS lowenssh DEFAULT CHARSET utf8mb4;"
mysql -u root -p lowenssh < src/main/resources/schema.sql

./mvnw spring-boot:run        # Windows 用 mvnw.cmd
```

运行测试：

```bash
./mvnw test
```

### 桌面端（`clients/app/`）

需要 Flutter SDK 3.12+。详见 [clients/app/README.md](clients/app/README.md)。

```bash
cd clients/app
flutter pub get
flutter run -d macos      # 或 -d windows
flutter analyze           # 提交前确保零问题
```

### CLI（`clients/cli/`）

需要 Node 20+。详见 [clients/cli/README.md](clients/cli/README.md)。

## 代码约定

- **注释用中文，标识符（变量/函数/类名）用英文**。
- 优先可读性，不做过度优化；改动范围尽量小，不顺手重构无关代码。
- 后端 Java 用 Java 17 语法，不用过时写法。
- Flutter 优先 Composition 风格的 Widget 拆分，复用动画/组件放对应封装文件。
- 涉及安全门禁规则改动，必须补充或更新对应单元测试。

## 提交前检查

- 后端：`./mvnw test` 全绿。
- 桌面端：`flutter analyze` 零问题，`flutter build macos --debug`（或 windows）可编译。
- CLI：按 `clients/cli/README.md` 的检查方式验证。
- 不提交任何明文密钥、`.env` 文件、本地构建产物。

## 提交信息规范

- 用简洁的中文描述「做了什么」，必要时补充「为什么」。
- 前缀标明影响范围，例如 `app:`、`cli:`、`backend:`、`docs:`。
- 一个提交聚焦一件事，避免把无关改动混在一起。

示例：

```
app: 修复切主题时终端不变色

终端配色从冻结的顶层 final 改为按当前 palette 实时计算。
```

## Pull Request 流程

1. 从 `main` 切出 feature 分支（如 `feature/xxx`、`fix/xxx`），**不要直接提交到 main**。
2. 完成开发并通过提交前检查。
3. 推送分支并发起 PR，目标分支为 `main`。
4. PR 描述请包含：改了什么、为什么、如何测试、是否涉及多端对齐。
5. 等待 review，合并后删除 feature 分支。

## 安全相关改动

本项目的安全门禁（高危命令拦截）是真实防护，不是演示。涉及以下改动请在 PR 中重点说明：

- 修改 deny / ask 规则名单。
- 调整命令拆段、正则匹配逻辑。
- 改动密码加密、密钥读取、审计落库相关代码。

发现安全漏洞请不要直接提 public issue，先通过私下渠道联系维护者。

## 报告问题

提 issue 时请尽量包含：复现步骤、预期与实际行为、运行环境（操作系统、形态、版本）、相关日志或截图。
