import AppKit
import ApplicationServices
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import SpeechVAD

@MainActor
final class DictateViewModel: ObservableObject {
    @Published var sentences: [String] = []
    @Published var partialText = ""
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var errorMessage: String?
    @Published var statusMessage = "Ready"
    @Published var alwaysListening = false
    @Published var isSpeechActive = false

    private var asrModel: Qwen3ASRModel?
    private var vad: SileroVADModel?
    private var audioBuffer: [Float] = []
    private let recorder = StreamingRecorder()
    private let inferenceQueue = DispatchQueue(label: "dictate.inference")
    private let hotkeyManager = HotkeyManager()

    // Always-on VAD state (accessed only on inferenceQueue)
    private var speechActive = false
    private var silenceChunkCount = 0
    private var speechBuffer: [Float] = []
    private var pendingChunks: [Float] = []
    private let chunkLock = NSLock()
    private var targetApp: NSRunningApplication?
    private var vadTimer: DispatchSourceTimer?
    private let silenceThreshold = 30 // ~960ms of silence before speech-end

    var modelLoaded: Bool { asrModel != nil && vad != nil }
    var audioLevel: Float { recorder.audioLevel }

    var wordCount: Int {
        let all = sentences.joined(separator: " ") + (partialText.isEmpty ? "" : " " + partialText)
        return all.split(separator: " ").count
    }

    var fullText: String {
        let committed = sentences.joined(separator: "\n")
        if committed.isEmpty { return partialText }
        if partialText.isEmpty { return committed }
        return committed + "\n" + partialText
    }

    init() {
        UserDefaults.standard.register(defaults: ["autoInject": true])
        Task { await loadModels() }
        hotkeyManager.onRecordStart = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onRecordStop = { [weak self] in
            Task { @MainActor in self?.stopRecordingAndTranscribe() }
        }
        hotkeyManager.setup()
    }

    func loadModels() async {
        guard asrModel == nil else { return }
        isLoading = true
        loadingStatus = "Downloading ASR model..."

        do {
            asrModel = try await Qwen3ASRModel.fromPretrained(
                modelId: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit",
                progressHandler: { [weak self] progress, status in
                    DispatchQueue.main.async {
                        self?.loadingStatus = status.isEmpty
                            ? "Downloading... \(Int(progress * 100))%"
                            : "\(status) (\(Int(progress * 100))%)"
                    }
                }
            )

            loadingStatus = "Loading VAD..."
            vad = try await SileroVADModel.fromPretrained(engine: .coreml)
            loadingStatus = ""
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
            loadingStatus = ""
        }
        isLoading = false
    }

    // MARK: - Push-to-talk

    func toggleRecording() {
        if isRecording { stopRecordingAndTranscribe() } else { startRecording() }
    }

    func startRecording() {
        guard modelLoaded, !isTranscribing else { return }
        captureTargetApp()
        errorMessage = nil
        statusMessage = "Recording..."
        partialText = ""
        audioBuffer.removeAll()

        if alwaysListening {
            stopVADTimer()
            speechActive = false
            silenceChunkCount = 0
            speechBuffer.removeAll()
        }

        isRecording = true

        if !recorder.isRecording {
            recorder.start { [weak self] chunk in
                self?.routeAudioChunk(chunk)
            }
        }
    }

    func stopRecordingAndTranscribe() {
        isRecording = false

        if !alwaysListening {
            recorder.stop()
        }

        DispatchQueue.main.async { [weak self] in
            self?.transcribeRecordedAudio()
        }
    }

    private func transcribeRecordedAudio() {
        let audio = audioBuffer
        audioBuffer.removeAll()

        guard !audio.isEmpty else {
            statusMessage = "No audio captured"
            if alwaysListening { resumeAlwaysOn() }
            return
        }

        isTranscribing = true
        statusMessage = "Transcribing..."
        let model = asrModel!
        let vad = vad!

        inferenceQueue.async { [weak self] in
            // VAD gate
            vad.resetState()
            var maxProb: Float = 0
            var offset = 0
            while offset + 512 <= audio.count {
                let prob = vad.processChunk(Array(audio[offset..<offset + 512]))
                maxProb = max(maxProb, prob)
                offset += 512
            }

            guard maxProb >= 0.3 else {
                DispatchQueue.main.async {
                    self?.isTranscribing = false
                    self?.statusMessage = "No speech detected"
                    if self?.alwaysListening == true { self?.resumeAlwaysOn() }
                }
                return
            }

            let text = model.transcribe(
                audio: audio,
                sampleRate: 16000,
                options: Qwen3DecodingOptions(repetitionPenalty: 1.15)
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                guard let self else { return }
                self.isTranscribing = false
                if !text.isEmpty {
                    self.sentences.append(text)
                    if UserDefaults.standard.bool(forKey: "autoInject") {
                        self.statusMessage = "Pasting..."
                        self.pasteToFrontApp(text: text)
                    } else {
                        self.statusMessage = "Transcribed"
                    }
                } else {
                    self.statusMessage = "Empty transcription"
                }
                if self.alwaysListening { self.resumeAlwaysOn() }
            }
        }
    }

    // MARK: - Always-on listening

    func toggleAlwaysListening() {
        if alwaysListening { stopAlwaysListening() } else { startAlwaysListening() }
    }

    func startAlwaysListening() {
        guard modelLoaded, !isRecording else { return }
        alwaysListening = true
        resumeAlwaysOn()
    }

    func stopAlwaysListening() {
        alwaysListening = false
        stopVADTimer()
        speechActive = false
        speechBuffer.removeAll()
        if !isRecording { recorder.stop() }
    }

    private func resumeAlwaysOn() {
        speechActive = false
        silenceChunkCount = 0
        speechBuffer.removeAll()
        chunkLock.lock()
        pendingChunks.removeAll()
        chunkLock.unlock()

        if !recorder.isRecording {
            recorder.start { [weak self] chunk in
                self?.routeAudioChunk(chunk)
            }
        }

        startVADTimer()
    }

    // MARK: - Audio routing

    private func routeAudioChunk(_ chunk: [Float]) {
        if isRecording {
            DispatchQueue.main.async { [weak self] in
                self?.audioBuffer.append(contentsOf: chunk)
            }
        } else if alwaysListening {
            chunkLock.lock()
            pendingChunks.append(contentsOf: chunk)
            chunkLock.unlock()
        }
    }

    // MARK: - VAD processing (runs on inferenceQueue)

    private func startVADTimer() {
        stopVADTimer()
        let timer = DispatchSource.makeTimerSource(queue: inferenceQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.processVADChunks()
        }
        timer.resume()
        vadTimer = timer
    }

    private func stopVADTimer() {
        vadTimer?.cancel()
        vadTimer = nil
    }

    private func processVADChunks() {
        chunkLock.lock()
        let chunks = pendingChunks
        pendingChunks.removeAll(keepingCapacity: true)
        chunkLock.unlock()

        guard !chunks.isEmpty, let vad else { return }

        var offset = 0
        while offset + 512 <= chunks.count {
            let chunk = Array(chunks[offset..<offset + 512])
            let prob = vad.processChunk(chunk)

            if prob >= 0.5 {
                if !speechActive {
                    speechActive = true
                    print("[VAD] Speech started")
                    DispatchQueue.main.async {
                        self.isSpeechActive = true
                        self.captureTargetApp()
                    }
                }
                silenceChunkCount = 0
            } else {
                silenceChunkCount += 1
            }

            if speechActive {
                speechBuffer.append(contentsOf: chunk)
            }

            if speechActive && silenceChunkCount >= silenceThreshold {
                speechActive = false
                let audio = speechBuffer
                speechBuffer.removeAll()
                silenceChunkCount = 0
                print("[VAD] Speech ended, \(audio.count) samples (\(String(format: "%.1f", Float(audio.count) / 16000))s)")
                DispatchQueue.main.async { self.isSpeechActive = false }

                if !audio.isEmpty {
                    transcribeForWakeWord(audio: audio)
                    return
                }
            }

            offset += 512
        }

        // Stash leftover samples for next tick
        if offset < chunks.count {
            chunkLock.lock()
            pendingChunks.insert(contentsOf: chunks[offset...], at: 0)
            chunkLock.unlock()
        }
    }

    // MARK: - Wake word

    private func transcribeForWakeWord(audio: [Float]) {
        guard let model = asrModel else { return }
        stopVADTimer()

        DispatchQueue.main.async { self.isTranscribing = true }

        let text = model.transcribe(
            audio: audio,
            sampleRate: 16000,
            options: Qwen3DecodingOptions(repetitionPenalty: 1.15)
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let (matched, remainder) = Self.stripWakeWord(text)
        print("[Wake] Transcribed: \"\(text)\" → matched=\(matched), remainder=\"\(remainder)\"")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isTranscribing = false
            if matched && !remainder.isEmpty {
                self.sentences.append(remainder)
                if UserDefaults.standard.bool(forKey: "autoInject") {
                    self.pasteToFrontApp(text: remainder)
                }
            } else if !matched && !text.isEmpty {
                self.partialText = "Heard: \(text)"
            }
            if self.alwaysListening && !self.isRecording {
                self.vad?.resetState()
                self.resumeAlwaysOn()
            }
        }
    }

    nonisolated static func stripWakeWord(_ text: String) -> (matched: Bool, remainder: String) {
        // Match "hey claude" and common misrecognitions
        let pattern = #"^[Hh]ey[,.\s]+[Cc]lau?de?[,.\s]*|^[Hh]ey[,.\s]+[Cc]loud[,.\s]*"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return (false, text)
        }
        let remainder = text[range.upperBound...]
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return (true, remainder)
    }

    // MARK: - Text injection

    private func captureTargetApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        }
    }

    func pasteToFrontApp(text: String? = nil) {
        let textToPaste = text ?? fullText
        guard !textToPaste.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToPaste, forType: .string)
        statusMessage = "Text copied; sending paste"

        if let target = targetApp {
            target.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if self.targetAppIsTerminalLike(), self.typeTextWithUnicodeEvents(textToPaste) {
                self.statusMessage = "Typed text"
            } else if self.insertTextWithAccessibility(textToPaste) {
                self.statusMessage = "Inserted text"
            } else if self.postSystemEventsPaste() {
                self.statusMessage = "Paste sent"
            } else {
                self.postEventTapPaste()
                self.statusMessage = "Paste sent via fallback"
            }
        }
    }

    private func targetAppIsTerminalLike() -> Bool {
        guard let targetApp else { return false }
        let bundleId = targetApp.bundleIdentifier?.lowercased() ?? ""
        let appName = targetApp.localizedName?.lowercased() ?? ""
        return bundleId.contains("ghostty")
            || bundleId.contains("terminal")
            || bundleId.contains("iterm")
            || bundleId.contains("messages")
            || bundleId == "com.apple.MobileSMS".lowercased()
            || appName.contains("ghostty")
            || appName.contains("terminal")
            || appName.contains("iterm")
            || appName.contains("messages")
    }

    private func typeTextWithUnicodeEvents(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            let units = Array(String(character).utf16)
            units.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                keyDown?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyDown?.post(tap: .cghidEventTap)

                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                keyUp?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp?.post(tap: .cghidEventTap)
            }
        }

        return true
    }

    private func insertTextWithAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success,
              let focused = focusedValue,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return false
        }

        let focusedElement = unsafeBitCast(focused, to: AXUIElement.self)
        let selectedResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedResult == .success { return true }

        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &value
        )
        guard valueResult == .success, value is String else {
            return false
        }

        return AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func postSystemEventsPaste() -> Bool {
        let source = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private func postEventTapPaste() {
        for tap in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            kd?.flags = .maskCommand
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            ku?.flags = .maskCommand
            kd?.post(tap: tap)
            ku?.post(tap: tap)
        }
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
        statusMessage = "Copied"
    }

    func clearText() { sentences.removeAll(); partialText = ""; statusMessage = "Ready" }
}
