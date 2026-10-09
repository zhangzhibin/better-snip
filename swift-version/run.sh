#!/usr/bin/env bash
# 编译 Swift 项目并包装为 .app 运行（解决屏幕录制权限问题）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Simple Snip"
BINARY_NAME="MacScreenshot"
BUILD_DIR=".build/release"
APP_DIR=".build/${APP_NAME}.app"
PLIST="${APP_DIR}/Contents/Info.plist"
MACOS_DIR="${APP_DIR}/Contents/MacOS"

echo ">> Building ${APP_NAME}..."
swift build -c release 2>&1

echo ">> Packaging as .app..."
mkdir -p "${MACOS_DIR}" "${APP_DIR}/Contents/Resources/Licenses"
cp "${BUILD_DIR}/${BINARY_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp App/Info.plist "${PLIST}"
cp App/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp App/PrivacyInfo.xcprivacy "${APP_DIR}/Contents/Resources/PrivacyInfo.xcprivacy"
cp App/Licenses/COPYING App/Licenses/PATENTS "${APP_DIR}/Contents/Resources/Licenses/"

# 关闭之前的实例
pkill -x "${BINARY_NAME}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.3

echo ">> Launching ${APP_DIR}..."
open "${APP_DIR}"
echo ">> Done. Check the menu bar for the tray icon."
