#!/usr/bin/env bash
# 编译 Swift 项目并包装为 .app 运行（解决屏幕录制权限问题）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacScreenshot"
BUILD_DIR=".build/release"
APP_DIR=".build/${APP_NAME}.app"
PLIST="${APP_DIR}/Contents/Info.plist"
MACOS_DIR="${APP_DIR}/Contents/MacOS"

echo ">> Building ${APP_NAME}..."
swift build -c release 2>&1

echo ">> Packaging as .app..."
mkdir -p "${MACOS_DIR}"
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-10.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.cloudcr.macscreenshot</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

# 关闭之前的实例
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.3

echo ">> Launching ${APP_DIR}..."
open "${APP_DIR}"
echo ">> Done. Check the menu bar for the tray icon."
