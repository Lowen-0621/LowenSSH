#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$APP_DIR/build/macos/Build/Products/Release/LowenSSH.app"

cd "$APP_DIR"
flutter test --no-pub
flutter build macos --release --no-pub

# 本机单用户版本使用 ad-hoc 签名；覆盖 Flutter 原生资源的嵌套签名后再校验。
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "构建完成：$APP_BUNDLE"
