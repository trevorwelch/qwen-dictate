import AppKit

final class HotkeyManager {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let targetKeyCode: UInt16 = 61 // Right Option
    private let doubleTapInterval: TimeInterval = 0.4
    private var lastTapTime: TimeInterval = 0
    private var isActive = false
    private var rightOptionIsDown = false
    private var ignoreReleaseAfterStart = false
    private var stopOnRelease = false

    func setup() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
    }

    func teardown() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == targetKeyCode else { return }

        let isDown = event.modifierFlags.contains(.option)
        guard isDown != rightOptionIsDown else { return }
        rightOptionIsDown = isDown

        if !isDown {
            if ignoreReleaseAfterStart {
                ignoreReleaseAfterStart = false
            } else if stopOnRelease {
                stopOnRelease = false
                isActive = false
                onRecordStop?()
            }
            return
        }

        if isActive {
            stopOnRelease = true
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastTapTime < doubleTapInterval {
                isActive = true
                ignoreReleaseAfterStart = true
                lastTapTime = 0
                onRecordStart?()
            } else {
                lastTapTime = now
            }
        }
    }

    deinit { teardown() }
}
