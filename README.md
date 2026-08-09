# LowenSSH

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-macOS%20%7C%20Windows-02569B.svg)](https://flutter.dev)
[![CI](https://github.com/Lowen-0621/LowenSSH/actions/workflows/ci.yml/badge.svg)](https://github.com/Lowen-0621/LowenSSH/actions/workflows/ci.yml)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

AI 驱动的 SSH 智能运维 Agent。用户给出运维目标和目标服务器后，Agent 会自主选择工具、读取执行结果并持续调整方案；危险命令在实际执行前经过安全门禁。

## 仓库范围

公开仓库仅维护 Flutter 桌面客户端，代码位于 [`clients/app/`](clients/app/)。客户端内置 SSH 连接、Agent loop、安全门禁、上下文管理和大模型调用能力，可以独立运行。

Java 后端与 Node CLI 为本地实现，不再包含在远程仓库当前版本中。

## 核心能力

- **手写 Agent Loop**：实现“模型决策 → 工具调用 → 结果回灌 → 再决策”的循环。
- **安全门禁**：命令执行前进行 `deny / ask / allow` 判定，高风险操作需要人工确认。
- **流式过程展示**：区分模型输出、工具调用、工具结果、安全拦截和最终结论。
- **上下文治理**：对大工具结果进行截断，并在历史过长时生成摘要。
- **SSH 工具集**：支持命令执行、日志读取、文件管理、监控和端口转发。

## 技术栈

Flutter · Dart · Riverpod · dartssh2 · Dio · PointyCastle · Secure Storage · xterm · docking

## 本地启动

### 1. 准备环境

- Flutter SDK 3.12+（Dart 3.12+）
- macOS：安装 Xcode
- Windows：安装 Visual Studio，并勾选“使用 C++ 的桌面开发”

```bash
flutter doctor
```

### 2. 安装依赖

```bash
cd clients/app
flutter pub get
```

### 3. 配置大模型

启动后可以在“设置”中填写 API Key、模型名称和 OpenAI 兼容接口地址。也可以通过环境变量临时注入默认 GLM Key：

macOS / Linux：

```bash
export GLM_API_KEY='你的 API Key'
```

Windows PowerShell：

```powershell
$env:GLM_API_KEY='你的 API Key'
```

环境变量只在当前进程中使用，不会被写回配置文件。

### 4. 运行桌面端

```bash
cd clients/app
flutter run -d macos      # macOS
flutter run -d windows    # Windows
```

### 5. 检查与打包

```bash
cd clients/app
flutter analyze
flutter test
flutter build macos --release       # macOS
flutter build windows --release     # Windows
```

更多模型配置和产物目录说明见 [`clients/app/README.md`](clients/app/README.md)。

## 项目结构

```text
LowenSSH/
├── clients/app/          # Flutter 桌面客户端
├── docs/                 # 架构与项目文档
├── DESIGN.md             # 设计规范
└── CONTRIBUTING.md       # 贡献指南
```

## 安全说明

- 主机密码经 AES-GCM 加密后保存，不记录明文。
- 端口转发默认只绑定 `127.0.0.1`。
- 危险命令执行前必须经过安全策略和人工确认。
- 本项目会在目标服务器执行真实操作，请只连接你有权管理的服务器。

## 贡献

欢迎提交 Issue 和 PR。开发环境、代码约定和提交流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)
