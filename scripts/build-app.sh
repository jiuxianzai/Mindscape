#!/usr/bin/env bash
# 不装 Xcode 的开发构建：swiftc 直接产出可双击运行的 .app。
#
# 和 `make run` 的区别：
#   make run      → xcodegen + xcodebuild，需要完整 Xcode
#   scripts/build-app.sh → swiftc + 手写 Info.plist，只需要 Command Line Tools 15+
#
# 不做的部分：Asset catalog 编译（没有 actool，app 图标是通用图标）、XCTest、通用二进制。
# 做开发调试够用。
set -euo pipefail
cd "$(dirname "$0")/.."

# 这个工程用 @Observable，需要 Swift 5.9+；CLT 16 自带 Swift 6。
if ! xcrun swiftc --version 2>/dev/null | head -1 | grep -qE 'Swift version (5\.9|[6-9])'; then
  echo "需要 Swift 5.9+（Command Line Tools 15 及以上），当前是：" >&2
  xcrun swiftc --version 2>&1 | head -1 >&2
  echo '安装：sudo softwareupdate -i "Command Line Tools for Xcode-16.2"' >&2
  exit 1
fi

ARCH=$(uname -m)
APP="build/no-xcode/Mindscape.app"
BIN="$APP/Contents/MacOS/Mindscape"
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
VERSION=${VERSION:-0.5.3}

echo "swiftc: $(xcrun swiftc --version | head -1)"
echo "sdk:    $(xcrun --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

FILES=$(find Mindscape -name '*.swift' | sort)
# shellcheck disable=SC2086
xcrun swiftc \
  -O \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "${ARCH}-apple-macos14.0" \
  -swift-version 5 \
  -lsqlite3 \
  -o "$BIN" \
  $FILES

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>Mindscape</string>
    <key>CFBundleIdentifier</key>
    <string>com.youyanping.mindscape</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mindscape</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Mindscape</string>
</dict>
</plist>
PLIST

if [ -d Mindscape/en.lproj ]; then
  cp -R Mindscape/en.lproj "$APP/Contents/Resources/"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc 签名失败，通常不影响本机运行"

echo "built: $APP"
if [ "${1:-}" != "--no-open" ]; then
  open "$APP"
fi
