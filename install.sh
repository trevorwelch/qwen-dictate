#!/bin/bash
set -euo pipefail

APP_NAME="QwenDictate"
BUNDLE_ID="com.tw.qwen-dictate"
APP_DIR="/Applications/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"

echo "Quitting any running ${APP_NAME}..."
osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
sleep 1

echo "Building release binary..."
swift build -c release --arch arm64 2>&1 | tail -5

BINARY=$(swift build -c release --arch arm64 --show-bin-path)/DictateDemo

echo "Creating app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${CONTENTS}/Resources"

cp "${BINARY}" "${MACOS}/${APP_NAME}"

# MLX Swift needs mlx.metallib colocated with binary
METALLIB=$(dirname "${BINARY}")/mlx.metallib
if [ ! -f "${METALLIB}" ]; then
    echo "metallib not in release dir, building debug to get it..."
    swift build --arch arm64 2>&1 | tail -3
    METALLIB="$(swift build --arch arm64 --show-bin-path)/mlx.metallib"
fi
cp "${METALLIB}" "${MACOS}/mlx.metallib"

cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>QwenDictate</string>
    <key>CFBundleIdentifier</key>
    <string>com.tw.qwen-dictate</string>
    <key>CFBundleName</key>
    <string>QwenDictate</string>
    <key>CFBundleDisplayName</key>
    <string>Qwen Dictate</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>QwenDictate needs microphone access for voice dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>QwenDictate uses System Events to paste transcribed text into the active app.</string>
</dict>
</plist>
PLIST

# Sign so macOS trusts it for accessibility/input monitoring
codesign --force --deep --sign "QwenDictateLocalSign" --entitlements DictateDemo/DictateDemo.entitlements "${APP_DIR}"

echo ""
echo "✓ Installed to ${APP_DIR}"
echo ""
echo "Registering as login item..."

# Open the app — SMAppService.register() runs on first launch from PreferencesView
open "${APP_DIR}"

echo "✓ App launched. Enable 'Launch at login' in Settings (menu bar → gear icon)."
echo ""
echo "If this is a fresh install, grant these permissions in System Settings → Privacy:"
echo "  • Accessibility"
echo "  • Input Monitoring"
echo "  • Microphone"