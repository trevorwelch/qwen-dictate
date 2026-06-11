#!/bin/bash
set -euo pipefail

APP_NAME="QwenDictate"
BUNDLE_ID="app.qwendictate.qwen-dictate"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP_DIR="${APP_DIR:-/Applications/${APP_NAME}.app}"
SKIP_OPEN="${SKIP_OPEN:-0}"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing required command: $1" >&2
        echo "Install Xcode Command Line Tools with: xcode-select --install" >&2
        exit 1
    fi
}

validate_app_dir() {
    if [ -z "${APP_DIR}" ]; then
        echo "error: APP_DIR must not be empty." >&2
        exit 1
    fi

    case "${APP_DIR}" in
        *.app) ;;
        *)
            echo "error: APP_DIR must end in .app: ${APP_DIR}" >&2
            exit 1
            ;;
    esac

    case "${APP_DIR}" in
        "/"|"."|".."|"${HOME}"|"${HOME}/")
            echo "error: refusing unsafe APP_DIR: ${APP_DIR}" >&2
            exit 1
            ;;
    esac
}

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: QwenDictate currently installs only on macOS." >&2
    exit 1
fi

if [ "$(uname -m)" != "arm64" ]; then
    echo "error: QwenDictate requires Apple Silicon (arm64)." >&2
    exit 1
fi

require_command swift
require_command xcrun
require_command codesign
validate_app_dir

cd "${ROOT_DIR}"

echo "Quitting any running ${APP_NAME}..."
osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
sleep 1

echo "Building release binary..."
swift build -c release --arch arm64

METALLIB_SCRIPT=".build/checkouts/speech-swift/scripts/build_mlx_metallib.sh"
if [ ! -x "${METALLIB_SCRIPT}" ]; then
    echo "error: missing ${METALLIB_SCRIPT}" >&2
    echo "Try rerunning: swift package resolve" >&2
    exit 1
fi

echo "Building MLX Metal shader library..."
BUILD_DIR="${ROOT_DIR}/.build" "${METALLIB_SCRIPT}" release

BINARY=$(swift build -c release --arch arm64 --show-bin-path)/QwenDictate

echo "Creating app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${CONTENTS}/Resources"

cp "${BINARY}" "${MACOS}/${APP_NAME}"

# MLX Swift needs mlx.metallib colocated with binary
METALLIB=$(dirname "${BINARY}")/mlx.metallib
if [ ! -f "${METALLIB}" ]; then
    echo "error: mlx.metallib was not created at ${METALLIB}" >&2
    echo "If the error mentions Metal Toolchain, run: xcodebuild -downloadComponent MetalToolchain" >&2
    exit 1
fi
cp "${METALLIB}" "${MACOS}/mlx.metallib"

cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>QwenDictate</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
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

# Ad-hoc signing works for local installs. Set CODE_SIGN_IDENTITY to use a
# stable local or Developer ID certificate.
codesign --force --deep --sign "${CODE_SIGN_IDENTITY}" --entitlements QwenDictate/QwenDictate.entitlements "${APP_DIR}"

echo ""
echo "✓ Installed to ${APP_DIR}"
echo ""
if [ "${SKIP_OPEN}" = "1" ]; then
    echo "SKIP_OPEN=1 set; not launching the app."
else
    open "${APP_DIR}"
    echo "✓ App launched. Enable 'Launch at login' in Settings (menu bar → gear icon)."
fi

echo ""
echo "If this is a fresh install, grant these permissions in System Settings → Privacy:"
echo "  • Accessibility"
echo "  • Microphone"
echo "Also approve the Automation (System Events) prompt on first paste."
