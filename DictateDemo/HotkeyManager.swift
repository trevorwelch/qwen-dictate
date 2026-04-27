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
        guard event.modifierFlags.contains(.option) else { return }

        if isActive {
            isActive = false
            onRecordStop?()
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastTapTime < doubleTapInterval {
                isActive = true
                lastTapTime = 0
                onRecordStart?()
            } else {
                lastTapTime = now
            }
        }
    }

    deinit { teardown() }
}
