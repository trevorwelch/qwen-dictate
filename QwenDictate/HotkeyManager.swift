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
        globalMonitor.map(NSEvent.removeMonitor)
        localMonitor.map(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == targetKeyCode else { return }

        let isDown = event.modifierFlags.contains(.option)
        guard isDown != rightOptionIsDown else { return }
        rightOptionIsDown = isDown

        if isDown {
            handleOptionPress()
        } else {
            handleOptionRelease()
        }
    }

    private func handleOptionPress() {
        if isActive {
            stopOnRelease = true
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastTapTime < doubleTapInterval {
            isActive = true
            lastTapTime = 0
            onRecordStart?()
        } else {
            lastTapTime = now
        }
    }

    private func handleOptionRelease() {
        guard stopOnRelease else { return }
        stopOnRelease = false
        isActive = false
        onRecordStop?()
    }

    deinit { teardown() }
}
