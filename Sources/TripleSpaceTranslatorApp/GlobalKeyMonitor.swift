import AppKit
import Foundation

private let triggerSpaceKeyCode: UInt16 = 49

final class GlobalKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var recentSpacePresses: [CFAbsoluteTime] = []
    private let triggerWindowSeconds: CFAbsoluteTime = 0.5

    var onTripleSpace: (() -> Void)?

    var isRunning: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    func start() -> Bool {
        guard !isRunning else { return true }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.processKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.processKeyEvent(event)
            return event
        }

        return isRunning
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        recentSpacePresses.removeAll()
    }

    private func processKeyEvent(_ event: NSEvent) {
        guard event.keyCode == triggerSpaceKeyCode else { return }
        guard !event.isARepeat else { return }

        let now = CFAbsoluteTimeGetCurrent()
        recentSpacePresses.append(now)
        recentSpacePresses.removeAll { now - $0 > triggerWindowSeconds }

        if recentSpacePresses.count >= 3 {
            recentSpacePresses.removeAll()
            onTripleSpace?()
        }
    }
}
