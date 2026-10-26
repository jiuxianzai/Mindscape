#!/usr/bin/env bash
# AI 桥接的无 UI 测试：转换器 + 校验规则，不需要 Xcode 工程。
set -euo pipefail
cd "$(dirname "$0")/.."

# 这个工程用 @Observable，需要 Swift 5.9+；CLT 16 自带 Swift 6。
if ! xcrun swiftc --version 2>/dev/null | head -1 | grep -qE 'Swift version (5\.9|[6-9])'; then
  echo "需要 Swift 5.9+（Command Line Tools 15 及以上），当前是：" >&2
  xcrun swiftc --version 2>&1 | head -1 >&2
  echo '安装：sudo softwareupdate -i "Command Line Tools for Xcode-16.2"' >&2
  exit 1
fi

OUT=$(mktemp -d)/ai-bridge-tests
xcrun swiftc -O \
  -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -o "$OUT" \
  Mindscape/Models/MapLayout.swift \
  Mindscape/Models/MindNode.swift \
  Mindscape/Models/MindMap.swift \
  Mindscape/Models/MapTheme.swift \
  Mindscape/Support/NSColor+Hex.swift \
  Mindscape/Support/AIInboxFormat.swift \
  tests/ai_inbox_format/main.swift

"$OUT"
