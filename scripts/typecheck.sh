#!/usr/bin/env bash
# 全量类型检查：不产出 .app，只验证能否编译。
# 需要 Command Line Tools 15+（Swift 5.9+，macOS 14 SDK）：代码里用了 @Observable。
set -euo pipefail
cd "$(dirname "$0")/.."

# 这个工程用 @Observable，需要 Swift 5.9+；CLT 16 自带 Swift 6。
if ! xcrun swiftc --version 2>/dev/null | head -1 | grep -qE 'Swift version (5\.9|[6-9])'; then
  echo "需要 Swift 5.9+（Command Line Tools 15 及以上），当前是：" >&2
  xcrun swiftc --version 2>&1 | head -1 >&2
  echo '安装：sudo softwareupdate -i "Command Line Tools for Xcode-16.2"' >&2
  exit 1
fi

echo "toolchain: $(xcrun swiftc --version | head -1)"
echo "sdk:       $(xcrun --show-sdk-path)"

FILES=$(find Mindscape -name '*.swift' | sort)
# shellcheck disable=SC2086
xcrun swiftc -typecheck \
  -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  $FILES

echo "typecheck ok ($(echo "$FILES" | wc -l | tr -d ' ') files)"
