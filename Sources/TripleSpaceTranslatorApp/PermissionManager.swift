import ApplicationServices
import Foundation

final class PermissionManager {
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var hasInputMonitoringPermission: Bool {
        CGPreflightListenEventAccess()
    }

    func requestAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt"
        let options: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoringPermission() {
        _ = CGRequestListenEventAccess()
    }
}
