# QwenDictate

QwenDictate is a macOS menu-bar dictation app for Apple Silicon. It uses
Qwen3-ASR through MLX to transcribe speech locally, then pastes the text into
the app you were using.

After the first model download, dictation runs on-device. No cloud API key is
required.

## What You Need

- A Mac with Apple Silicon: M1, M2, M3, or newer
- macOS 15 or newer
- Xcode Command Line Tools
- About 3 GB of disk space for the speech model
- Terminal access for installation

If Terminal says developer tools are missing, run:

```bash
xcode-select --install
```

## Quick Start

Open Terminal, paste these commands, and press Return:

```bash
git clone https://github.com/trevorwelch/qwen-dictate.git
cd qwen-dictate
./install.sh
```

The installer builds the app, creates `/Applications/QwenDictate.app`, signs it
locally, and launches it.

This is a source install, not a notarized binary release. macOS may ask you to
grant or re-grant permissions after rebuilding or reinstalling the app.

On first launch, macOS will ask for permissions. Grant:

| Permission | Why QwenDictate Needs It |
|---|---|
| Microphone | Records your voice |
| Accessibility | Pastes transcribed text into other apps |
| Input Monitoring | Watches for the Right Option hotkey |

Open System Settings > Privacy & Security if macOS does not show the prompts.

## How To Use

1. Launch QwenDictate from `/Applications` or the menu bar.
2. Wait for the first model download to finish. This can take a while.
3. Double-tap Right Option to start recording.
4. Speak.
5. Tap Right Option again to stop. QwenDictate transcribes and pastes the text.

Optional wake-word mode is available from the menu-bar popover. Toggle the ear
icon, then say `Hey Qwen, ...`; QwenDictate strips the wake phrase and pastes
the rest.

## Agent Install Contract

Use this section when installing from Codex, Claude Code, or another coding
agent.

### Preconditions

- Run on macOS arm64.
- Do not run on Linux or Intel macOS.
- Network is needed for SwiftPM dependencies and the first model download.
- Xcode Command Line Tools must be installed.
- The Metal Toolchain may be required. If metallib compilation fails, run:

```bash
xcodebuild -downloadComponent MetalToolchain
```

### Default Install

```bash
git clone https://github.com/trevorwelch/qwen-dictate.git
cd qwen-dictate
./install.sh
```

Expected result:

- `/Applications/QwenDictate.app` exists.
- The app bundle contains `Contents/MacOS/QwenDictate`.
- The app bundle contains `Contents/MacOS/mlx.metallib`.
- The app is ad-hoc signed unless `CODE_SIGN_IDENTITY` is provided.

### Non-Interactive Build And Bundle

Use this when an agent should build the app but not open it:

```bash
SKIP_OPEN=1 ./install.sh
```

Use a custom install location:

```bash
APP_DIR="$PWD/QwenDictate.app" SKIP_OPEN=1 ./install.sh
```

Use a specific signing identity:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name" ./install.sh
```

### Verify

```bash
swift test
swift build -c release --arch arm64
test -x /Applications/QwenDictate.app/Contents/MacOS/QwenDictate
test -f /Applications/QwenDictate.app/Contents/MacOS/mlx.metallib
codesign --verify --deep --strict /Applications/QwenDictate.app
```

For a custom `APP_DIR`, point the last three commands at that path.

## Development Build

For local development without creating an app bundle:

```bash
swift build
BUILD_DIR="$PWD/.build" .build/checkouts/speech-swift/scripts/build_mlx_metallib.sh debug
.build/debug/QwenDictate
```

Run tests:

```bash
swift test
```

Build a release binary:

```bash
swift build -c release --arch arm64
```

## Troubleshooting

### `missing Metal Toolchain`

Run:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Then rerun:

```bash
./install.sh
```

### App Builds But Does Not Paste

Open System Settings > Privacy & Security, then check:

- Accessibility includes QwenDictate and is enabled.
- Input Monitoring includes QwenDictate and is enabled.
- Microphone includes QwenDictate and is enabled.

If permissions look stale after reinstalling, remove QwenDictate from those
lists, launch it again, and grant permissions again.

### `/Applications` Is Not Writable

Install to a user-writable location:

```bash
APP_DIR="$HOME/Applications/QwenDictate.app" ./install.sh
```

Create `~/Applications` first if needed:

```bash
mkdir -p "$HOME/Applications"
```

### First Launch Is Slow

The speech model is downloaded on first launch. After that, QwenDictate runs
locally.

## Features

- Push-to-talk dictation with Right Option
- Optional wake-word mode
- Automatic paste into the focused app
- Menu-bar controls
- Floating transcript HUD
- Local transcription after the first model download

## Architecture

```text
QwenDictateApp
├── MenuBarExtra
│   └── DictateMenuView
├── Window
│   └── DictateHUDView
├── Settings
│   └── PreferencesView
├── DictateViewModel
│   ├── Qwen3ASRModel
│   ├── SileroVADModel
│   ├── StreamingRecorder
│   └── HotkeyManager
└── QwenDictateCore
    └── WakeWord
```

## Acknowledgments

Derived from the DictateDemo example in
[speech-swift](https://github.com/soniqo/speech-swift) by soniqo.

## License

Apache 2.0. See [LICENSE](LICENSE).
