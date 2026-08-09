# 贡献指南

感谢你对 LowenSSH 的兴趣。远程仓库当前仅维护 [`clients/app/`](clients/app/) 下的 Flutter 桌面客户端。

## 本地开发环境

需要 Flutter SDK 3.12+。macOS 构建需要 Xcode；Windows 构建需要 Visual Studio，并安装“使用 C++ 的桌面开发”工作负载。

```bash
cd clients/app
flutter pub get
flutter run -d macos      # 或 flutter run -d windows
flutter analyze
flutter test
```

完整运行、打包和模型配置说明见 [`clients/app/README.md`](clients/app/README.md)。

## 代码约定

- 注释使用中文，标识符使用英文。
- 优先可读性，不重构与当前任务无关的代码。
- Widget 保持职责清晰，可复用动画和组件放入对应封装文件。
- 修改安全门禁、凭据保存或 SSH 执行逻辑时，必须补充相应测试。
- 不提交 API Key、密码、`.env`、本机构建产物和日志。

## 提交前检查

```bash
cd clients/app
flutter analyze
flutter test
flutter build macos --debug   # Windows 使用对应构建命令
```

## 提交与 Pull Request

1. 从 `main` 创建功能分支，不直接提交到 `main`。
2. 一个提交只处理一类问题，提交信息使用简洁中文。
3. 推送分支后创建 PR，目标分支为 `main`。
4. PR 说明应包含改动内容、原因、验证方式和安全影响。

## 安全问题

安全门禁和凭据保护属于真实防护。发现可导致未授权命令执行、凭据泄露或安全规则绕过的问题时，请先通过私下渠道联系维护者，不要直接公开利用细节。
