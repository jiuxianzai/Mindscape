#!/usr/bin/env bash
# MapEditor 忙判定 / applyExternal 的无 UI 测试（不需要 Xcode 工程）。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcrun swiftc --version 2>/dev/null | head -1 | grep -qE 'Swift version (5\.9|[6-9])'; then
  echo "需要 Swift 5.9+" >&2
  exit 1
fi

OUT=$(mktemp -d)/editor-state-tests
xcrun swiftc -O \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macos14.0" \
  -swift-version 5 \
  -o "$OUT" \
  Mindscape/Models/MapLayout.swift \
  Mindscape/Models/MindNode.swift \
  Mindscape/Models/MindMap.swift \
  Mindscape/Models/MapTheme.swift \
  Mindscape/Models/IconCatalog.swift \
  Mindscape/Support/NSColor+Hex.swift \
  Mindscape/Support/AIInboxFormat.swift \
  Mindscape/Storage/SQLiteDatabase.swift \
  Mindscape/Storage/DocumentStore.swift \
  Mindscape/Editor/NodeClipboard.swift \
  Mindscape/Editor/MapEditor.swift \
  tests/editor_state/EditorStateTests.swift

"$OUT"
