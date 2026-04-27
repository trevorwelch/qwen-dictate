# QwenDictate — macOS Menu Bar Dictation with Qwen3-ASR

## Overview

A macOS menu-bar dictation app: hold a hotkey, speak, release, transcribed text is typed into the focused text field. Uses Qwen3-ASR (0.6B or 1.7B) via MLX on Apple Silicon.

## Key Decisions

### Fork DictateDemo from speech-swift

Don't build from scratch. The [speech-swift](https://github.com/soniqo/speech-swift) package includes a `DictateDemo` example app that already has menu bar presence, AVAudioEngine mic capture, VAD, and CGEvent text injection. Currently uses Parakeet — swap to Qwen3ASR.

### Batch mode, not streaming

Qwen3ASR is batch-only (give it a complete audio buffer, get back complete text). This actually simplifies the architecture vs. the current DictateDemo streaming approach: record everything while key is held, transcribe on release.

### Text injection via clipboard + Cmd+V

Save clipboard → set our text → synthesize Cmd+V via CGEvent → restore clipboard after 300ms. Works in virtually every app. The DictateDemo already has `pasteToFrontApp()` doing most of this.

### Disable App Sandbox

Required for `NSEvent.addGlobalMonitorForEvents` and `CGEvent.post`. Fine for personal use outside the App Store.

## Architecture

```
QwenDictateApp (SwiftUI @main)
├── MenuBarExtra (icon + popover)
│   └── DictateMenuView (controls, transcript, preferences link)
├── Settings scene
│   └── PreferencesView (model picker, hotkey config, language)
└── DictateViewModel (@MainActor, ObservableObject)
    ├── asrModel: Qwen3ASRModel
    ├── vad: SileroVADModel (speech detection visual feedback)
    ├── recorder: StreamingRecorder (AVAudioEngine)
    ├── audioBuffer: [Float] (accumulated during recording)
    ├── startRecording() / stopRecordingAndTranscribe()
    └── injectText(_:) (clipboard + CGEvent Cmd+V)
HotkeyManager (NSEvent global/local monitors)
    ├── keyDown → ViewModel.startRecording()
    └── keyUp → ViewModel.stopRecordingAndTranscribe()
```

## Phases

### Phase 0: Project Setup (15 min)

1. Clone `speech-swift` to `~/coding/speech-swift`
2. Copy `Examples/DictateDemo` to `~/coding/qwen-dictate`
3. Update `Package.swift`:
   - Change dependency from `.package(path: "../..")` to `.package(url: "https://github.com/soniqo/speech-swift", from: "<latest-tag>")`
   - Replace `ParakeetStreamingASR` with `Qwen3ASR`
   - Keep `SpeechVAD` and `AudioCommon`
4. Update entitlements: set `com.apple.security.app-sandbox` to `false`
5. Keep `LSUIElement = true` and `NSMicrophoneUsageDescription` in Info.plist

### Phase 1: Swap ASR Engine (1-2 hours) — the hard part

**Rewrite `DictateViewModel.swift`:**

1. Replace `import ParakeetStreamingASR` with `import Qwen3ASR`
2. Remove `ASRProcessor` class entirely (tightly coupled to Parakeet streaming)
3. Replace `model: ParakeetStreamingASRModel?` with `asrModel: Qwen3ASRModel?`
4. Rewrite `loadModels()`:
   ```swift
   asrModel = try await Qwen3ASRModel.fromPretrained(
       modelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
   )
   ```
5. Simplify recording flow:
   - `startRecording()`: start `AVAudioEngine` via `StreamingRecorder`, accumulate audio chunks into a single `[Float]` buffer. No timer, no ASR during recording.
   - `stopRecordingAndTranscribe()`: stop recorder, run `asrModel.transcribe(audio:sampleRate:)` on background queue, inject text on completion
6. Add `@Published var isTranscribing = false` for UI state during inference
7. Gate transcription on VAD — if no speech detected, skip entirely

**`StreamingRecorder.swift`** — keep as-is, the existing `onChunk` callback already lets us accumulate audio.

**Key files to reference:**
- `Sources/Qwen3ASR/Qwen3ASR.swift` — `Qwen3ASRModel`, `fromPretrained()`, `transcribe()`, `Qwen3DecodingOptions`
- `Sources/Qwen3ASR/StreamingASR.swift` — reference for VAD-guided segmentation if needed later

### Phase 2: Global Hotkey (1-2 hours)

**New file: `HotkeyManager.swift`**

```swift
class HotkeyManager {
    func setup() {
        // Global (app not frontmost)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            self.handleEvent(event)
        }
        // Local (app frontmost)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            self.handleEvent(event)
            return event
        }
    }

    func handleEvent(_ event: NSEvent) {
        guard matchesHotkey(event), !event.isARepeat else { return }
        if event.type == .keyDown { onRecordStart() }
        if event.type == .keyUp { onRecordStop() }
    }
}
```

- Default hotkey: `Ctrl+Opt+D` or a function key (unlikely to conflict)
- Store configuration in `UserDefaults`
- Wire to `DictateViewModel.startRecording()` / `stopRecordingAndTranscribe()`

### Phase 3: Text Injection with Clipboard Preservation (30 min)

**Update `pasteToFrontApp()` in `DictateViewModel.swift`:**

```swift
func injectText(_ text: String) {
    let saved = NSPasteboard.general.string(forType: .string)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    // Synthesize Cmd+V (virtual key 0x09 = 'v')
    let src = CGEventSource(stateID: .hidSystemState)
    let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
    kd?.flags = .maskCommand
    let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
    ku?.flags = .maskCommand
    kd?.post(tap: .cghidEventTap)
    ku?.post(tap: .cghidEventTap)

    // Restore clipboard
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NSPasteboard.general.clearContents()
        if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }
}
```

### Phase 4: Preferences (30-45 min)

**New file: `PreferencesView.swift`**

- Model picker: `0.6B-4bit` (fast, 713MB) vs `1.7B-8bit` (accurate, larger)
- Hotkey configuration (record key combo via NSEvent)
- Language hint picker (auto-detect or specific language)
- Auto-inject toggle (paste immediately vs. copy to clipboard only)
- Store everything in `UserDefaults`

Add `Settings` scene to `QwenDictateApp.swift`.

### Phase 5: Permissions (30 min)

| Permission | Why | Grant |
|---|---|---|
| Microphone | Audio capture | `NSMicrophoneUsageDescription` in Info.plist |
| Accessibility | CGEvent posting | System Settings > Privacy > Accessibility |
| Input Monitoring | Global hotkey | System Settings > Privacy > Input Monitoring |
| Network | Model download | Outgoing connections entitlement |

Add first-launch alert explaining required permissions with a button to open System Settings:
```swift
NSWorkspace.shared.open(URL(string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
```

### Phase 6: UI Polish (30-45 min)

- Recording state: pulsing red dot + audio level meter from `StreamingRecorder.audioLevel`
- Transcribing state: spinner or "Transcribing..." text
- Menu bar icon: `mic` → `mic.fill` during recording, color change
- Show selected model name and configured hotkey
- Remove streaming partial UI (not needed for batch mode)

### Phase 7: Testing (1 hour)

| Scenario | What to check |
|---|---|
| Short utterance (<1s) | Transcribes correctly |
| Long dictation (>30s) | Memory ok (60s @ 16kHz = 3.8MB, trivial) |
| Silence / ambient noise | VAD gates transcription, no hallucinated text |
| Rapid re-invocation | `isTranscribing` flag blocks new recording until done |
| Model switch | Disabled during recording, re-downloads if needed |
| Permission denied | Graceful error, re-prompt for grant |

## Gotchas

1. **Qwen3ASR is not thread-safe** — use a single serial `DispatchQueue` for all inference calls
2. **Silence → hallucination** — always gate on VAD, use `Qwen3DecodingOptions(repetitionPenalty: 1.15)`
3. **MenuBarExtra UI updates** — use `ObservableObject`/`@Published`, NOT `@Observable` (known SwiftUI popover bug)
4. **First launch downloads ~713MB** — show download progress in the popover
5. **`MetalBudget.pinMemory()`** — called after model load, keeps model resident in GPU memory

## Models

| Model | Size | Speed | Notes |
|---|---|---|---|
| `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` | 713 MB | ~22x realtime | Default choice |
| `aufklarer/Qwen3-ASR-1.7B-MLX-8bit` | ~3 GB | ~15x realtime | Higher accuracy |
| `mlx-community/Qwen3-ASR-0.6B-4bit` | ~700 MB | ~22x realtime | Alternative quant |
| `mlx-community/Qwen3-ASR-1.7B-8bit` | ~3 GB | ~15x realtime | Alternative quant |

## Estimated Total: 5-8 hours
