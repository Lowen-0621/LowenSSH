# LowenSSH 桌面客户端

LowenSSH 的桌面应用形态，基于 Flutter，支持 macOS 和 Windows。

内置全套逻辑——SSH 连接、手写 Agent loop、安全门禁、上下文管理、直连大模型——**不依赖项目的 Java 后端**，独立运行。

## 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.12+（Dart 3.12+）
- macOS 构建需 Xcode；Windows 构建需 Visual Studio（含「使用 C++ 的桌面开发」工作负载）

确认环境就绪：

```bash
flutter doctor
```

## 运行

```bash
cd clients/app
flutter pub get

flutter run -d macos      # macOS
flutter run -d windows    # Windows
```

## 打包

```bash
flutter build macos       # 产物在 build/macos/Build/Products/Release/
flutter build windows     # 产物在 build/windows/x64/runner/Release/
```

## 大模型配置

首次启动后，在应用内「设置」里填入大模型 API Key（默认接入 GLM，走 OpenAI 兼容协议，可改 baseURL / model 换成任意兼容模型）。

配置保存在 `~/.lowenssh/config.json`。也可通过环境变量 `GLM_API_KEY` 注入，优先级高于配置文件，且不会被写回文件。

## 安全说明

- 主机密码 AES-GCM 加密后落盘，不存明文，不打印到控制台。
- 端口转发隧道默认绑定 `127.0.0.1`，仅本机可访问，不暴露到局域网。
- 这是一个运维 Agent，会真实在目标服务器执行命令。请只连接你有权操作的服务器。
