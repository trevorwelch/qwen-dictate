# QwenDictate

macOS menu-bar dictation app powered by [Qwen3-ASR 1.7B](https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-8bit) via MLX on Apple Silicon. Speak, and transcribed text is pasted into the focused app.

## Features

- **Push-to-talk**: double-tap Right Option to start recording, tap again to stop and transcribe
- **"Hey Claude" mode**: always-on VAD listens for "Hey Claude" wake word, then transcribes and pastes the rest of the utterance
- **Auto-paste**: transcribed text is injected into the frontmost app via clipboard + Cmd+V (clipboard is restored afterward)
- **Menu bar app**: lives in the menu bar with dynamic icon (mic/recording/transcribing/listening)
- **Floating HUD**: optional window showing transcript and status
- Runs entirely on-device — no cloud API, no internet required after first model download (~3 GB)

## Requirements

- macOS 15.0+
- Apple Silicon (M1 or later)
- [speech-swift](https://github.com/soniqo/speech-swift) v0.0.12+ (pulled automatically via SPM)

## Build

```bash
# Clone
git clone https://github.com/trevorwelch/qwen-dictate.git
cd qwen-dictate

# Build the MLX Metal shader library (required once)
git clone https://github.com/soniqo/speech-swift.git /tmp/speech-swift
BUILD_DIR=$(pwd)/.build /tmp/speech-swift/scripts/build_mlx_metallib.sh debug

# Build the app
swift build

# Run
.build/debug/DictateDemo
```

## Permissions

The app requires these macOS permissions (prompted on first launch):

| Permission | Why |
|---|---|
| **Microphone** | Audio capture |
| **Accessibility** | Synthetic Cmd+V to paste text |
| **Input Monitoring** | Global hotkey (Right Option) |

Open System Settings > Privacy & Security to grant these. The Preferences panel has shortcut buttons.

## Usage

1. **Launch** — the model downloads automatically on first run (~3 GB)
2. **Push-to-talk**: double-tap Right Option to start recording. Speak. Tap Right Option again to stop — text is transcribed and pasted into the focused app.
3. **"Hey Claude" mode**: toggle the ear icon in the menu bar popover. Say "Hey Claude, [your message]" — the wake word is stripped and the rest is pasted.
4. **Auto-paste**: enabled by default. Disable in Preferences to use copy-to-clipboard instead.

## Architecture

```
DictateDemoApp (SwiftUI @main)
├── MenuBarExtra (icon + popover)
│   └── DictateMenuView (controls, transcript)
├── Window (floating HUD)
│   └── DictateHUDView (status, transcript)
├── Settings
│   └── PreferencesView (auto-paste toggle, permissions)
└── DictateViewModel (@MainActor, ObservableObject)
    ├── Qwen3ASRModel (batch transcription)
    ├── SileroVADModel (voice activity detection)
    ├── StreamingRecorder (AVAudioEngine, 16kHz mono)
    ├── HotkeyManager (double-tap Right Option toggle)
    ├── Push-to-talk: accumulate audio → transcribe on stop
    └── Always-on: VAD timer → wake word detection → auto-paste
```

## Acknowledgments

Derived from the DictateDemo example in [speech-swift](https://github.com/soniqo/speech-swift) by soniqo.

## License

Apache 2.0 — see [LICENSE](LICENSE).
