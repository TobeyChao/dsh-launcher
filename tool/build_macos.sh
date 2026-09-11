#!/bin/bash
# 构建 DSH 启动器(macOS)。
#
# 前置:Flutter SDK(可用 FLUTTER 环境变量指定,默认自动探测)、Xcode。
# 产物:build/macos/Build/Products/Release/dsh_launcher.app
set -euo pipefail
cd "$(dirname "$0")/.."

# Flutter 定位:环境变量优先,其次 PATH,最后常见安装位置。
FLUTTER_BIN=""
if [ -n "${FLUTTER:-}" ]; then
  # 允许写成 SDK 根目录,自动补 bin/flutter。
  if [ -d "$FLUTTER" ] && [ -x "$FLUTTER/bin/flutter" ]; then
    FLUTTER_BIN="$FLUTTER/bin/flutter"
  else
    FLUTTER_BIN="$FLUTTER"
  fi
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  for candidate in \
    "$HOME/development/flutter/bin/flutter" \
    "$HOME/flutter/bin/flutter" \
    "$HOME/fvm/default/bin/flutter" \
    "$HOME/.puro/shared/flutter/bin/flutter" \
    "/opt/homebrew/bin/flutter" \
    "/usr/local/bin/flutter"; do
    if [ -x "$candidate" ]; then
      FLUTTER_BIN="$candidate"
      break
    fi
  done
fi

if [ -z "$FLUTTER_BIN" ] || [ ! -x "$FLUTTER_BIN" ]; then
  echo "[error] 未找到 Flutter SDK。请安装后重试,或用 FLUTTER=/path/to/flutter/bin/flutter 指定。" >&2
  exit 1
fi

echo "[1/2] 构建 macOS launcher(flutter build macos --release)..."
echo "      flutter: $FLUTTER_BIN"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build macos --release

APP="build/macos/Build/Products/Release/dsh_launcher.app"
if [ ! -d "$APP" ]; then
  echo "[error] 产物缺失: $PWD/$APP" >&2
  exit 1
fi

echo "[2/2] 完成: $PWD/$APP"
echo "      (替换 /Applications:先退出旧实例,再同路径覆盖,否则单实例锁会让新副本静默退出)"
