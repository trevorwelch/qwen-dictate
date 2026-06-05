# QwenDictate Roadmap

This file tracks public project direction. It avoids local setup notes and
implementation scratch work so the repository stays readable for contributors.

## Current Scope

- macOS menu-bar dictation for Apple Silicon.
- On-device transcription with Qwen3-ASR through MLX.
- Push-to-talk recording with double-tap Right Option.
- Optional wake-word mode.
- Text insertion through the clipboard, accessibility APIs, and event fallbacks.

## Near-Term Improvements

- Rename remaining internal symbols where it improves clarity without creating
  noisy churn.
- Add a first-run permissions checklist inside the app.
- Make model selection configurable in Preferences.
- Improve progress reporting during the first model download.
- Add a lightweight release checklist for manual install testing.

## Test Checklist

Before publishing a release:

| Area | Check |
|---|---|
| Build | `swift build -c release --arch arm64` succeeds |
| Unit tests | `swift test` succeeds |
| Push-to-talk | Double-tap Right Option starts recording; next tap stops |
| Wake word | Wake-word mode ignores unrelated speech and strips the trigger phrase |
| Permissions | Microphone, Accessibility, and Input Monitoring prompts are understandable |
| Text insertion | Text lands in common editors, terminals, chat apps, and browser fields |
| Privacy | No sample transcripts, personal notes, credentials, or local paths are committed |

## Privacy Notes

QwenDictate is designed to run transcription locally after the model is
downloaded. The repository should not include user transcripts, logs, private
session notes, credentials, or machine-specific configuration.
