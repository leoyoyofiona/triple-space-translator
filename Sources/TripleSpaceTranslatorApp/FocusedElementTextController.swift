import ApplicationServices
import AppKit
import Foundation

final class FocusedElementTextController {
    func readFocusedText() -> String? {
        guard let element = focusedElement() else { return nil }
        if let axText = readTextViaAX(from: element) {
            return axText
        }
        if let selectedAXText = readTextViaAXSelectedTextAfterSelectAll(from: element) {
            return selectedAXText
        }
        return readTextViaSelectAllCopyFallback()
    }

    @discardableResult
    func replaceFocusedText(with text: String) -> Bool {
        guard let element = focusedElement() else { return false }

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if setResult == .success {
            // Keep caret at the end after replacing full text.
            var range = CFRange(location: text.utf16.count, length: 0)
            if let selectedRange = AXValueCreate(.cfRange, &range) {
                _ = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    selectedRange
                )
            }
            if verifyReplacementMatchesExpected(text) {
                return true
            }
        }

        if replaceViaAXSelectedTextAfterSelectAll(text, on: element),
           verifyReplacementMatchesExpected(text) {
            return true
        }

        // Fallback for controls like WeChat/WPS editor that do not support AX value write.
        if replaceViaSelectAllPasteFallback(text) {
            return true
        }
        return replaceViaSelectAllTypeFallback(text)
    }

    // Destructive fallback used only when we cannot read focused text by AX/copy path.
    // It performs Cmd+A then Cmd+X and returns the cut content.
    func captureTextViaSelectAllCutFallback() -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboardItems(pasteboard)

        guard postShortcut(keyCode: 0),   // A
              postShortcut(keyCode: 7)    // X
        else {
            restorePasteboard(snapshot, on: pasteboard)
            return nil
        }

        usleep(120_000)
        let cutText = readTextFromPasteboard(pasteboard)
        restorePasteboard(snapshot, on: pasteboard)
        return cutText
    }

    @discardableResult
    func replaceCurrentInputViaPasteFallback(_ text: String) -> Bool {
        if replaceViaSelectAllPasteFallback(text) {
            return true
        }
        return replaceViaSelectAllTypeFallback(text)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        guard result == .success,
              let focusedElement = focusedObject,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    private func readTextViaAX(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard result == .success else { return nil }
        return value as? String
    }

    private func readTextViaAXSelectedTextAfterSelectAll(from element: AXUIElement) -> String? {
        guard postShortcut(keyCode: 0) else { return nil } // A
        usleep(120_000)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )

        guard result == .success else { return nil }
        return value as? String
    }

    private func replaceViaAXSelectedTextAfterSelectAll(_ text: String, on element: AXUIElement) -> Bool {
        guard postShortcut(keyCode: 0) else { return false } // A
        usleep(120_000)

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    private func readTextViaSelectAllCopyFallback() -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboardItems(pasteboard)

        guard postShortcut(keyCode: 0),   // A
              postShortcut(keyCode: 8)    // C
        else {
            restorePasteboard(snapshot, on: pasteboard)
            return nil
        }

        usleep(copyReadDelayMicroseconds())
        let copiedText = readTextFromPasteboard(pasteboard)
        restorePasteboard(snapshot, on: pasteboard)
        return copiedText
    }

    private func replaceViaSelectAllPasteFallback(_ text: String) -> Bool {
        if isWPSForeground() {
            return replaceViaWPSTypeThenPasteFallback(text)
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboardItems(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(snapshot, on: pasteboard)
            return false
        }

        guard postShortcut(keyCode: 0),   // A
              postShortcut(keyCode: 9)    // V
        else {
            restorePasteboard(snapshot, on: pasteboard)
            return false
        }

        // Some editors (notably WPS) consume pasteboard content asynchronously.
        // Delay restoring clipboard so the target app can finish reading text.
        usleep(250_000)
        let delay = clipboardRestoreDelaySeconds()
        Thread.sleep(forTimeInterval: delay)
        restorePasteboard(snapshot, on: pasteboard)
        return verifyReplacementMatchesExpected(text)
    }

    private func replaceViaWPSTypeThenPasteFallback(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return false
        }

        // WPS rich editor is sensitive to timing and IME state.
        _ = postKey(keyCode: 53) // Escape
        guard postShortcut(keyCode: 0),    // A
              postShortcut(keyCode: 7),    // X
              postShortcut(keyCode: 9)     // V
        else {
            return false
        }

        usleep(700_000)
        return verifyReplacementMatchesExpected(text)
    }

    private func replaceViaSelectAllTypeFallback(_ text: String) -> Bool {
        guard postShortcut(keyCode: 0),   // A
              postKey(keyCode: 51)        // Delete
        else {
            return false
        }

        usleep(90_000)
        guard postUnicodeText(text) else { return false }
        return verifyReplacementMatchesExpected(text)
    }

    private func postShortcut(keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        usleep(70_000)
        return true
    }

    private func postKey(keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        usleep(30_000)
        return true
    }

    private func postUnicodeText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let utf16Units = Array(text.utf16)
        for unit in utf16Units {
            var codeUnit = unit
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                return false
            }

            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            usleep(3_000)
        }

        return true
    }

    private func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type] = data
                }
            }
            return map
        }
    }

    private func restorePasteboard(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        on pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        for itemMap in snapshot {
            let item = NSPasteboardItem()
            for (type, data) in itemMap {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    private func readTextFromPasteboard(_ pasteboard: NSPasteboard) -> String? {
        if let direct = pasteboard.string(forType: .string), !direct.isEmpty {
            return direct
        }

        guard let item = pasteboard.pasteboardItems?.first else {
            return nil
        }

        for type in item.types {
            if let value = item.string(forType: type), !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func clipboardRestoreDelaySeconds() -> TimeInterval {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        if bundleID.contains("wps") || bundleID.contains("kingsoft") {
            return 1.2
        }
        return 0.35
    }

    private func copyReadDelayMicroseconds() -> useconds_t {
        isWPSForeground() ? 300_000 : 120_000
    }

    private func isWPSForeground() -> Bool {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        return bundleID.contains("wps") || bundleID.contains("kingsoft")
    }

    private func verifyReplacementMatchesExpected(_ expected: String) -> Bool {
        let normalizedExpected = normalizeText(expected)
        guard !normalizedExpected.isEmpty else { return false }

        let currentText = readCurrentTextForVerification()
        let normalizedCurrent = normalizeText(currentText ?? "")
        guard !normalizedCurrent.isEmpty else { return false }

        return normalizedCurrent == normalizedExpected || normalizedCurrent.contains(normalizedExpected)
    }

    private func readCurrentTextForVerification() -> String? {
        if let element = focusedElement() {
            if let axText = readTextViaAX(from: element), !axText.isEmpty {
                return axText
            }
            if let selected = readTextViaAXSelectedTextAfterSelectAll(from: element), !selected.isEmpty {
                return selected
            }
        }
        return readTextViaSelectAllCopyFallback()
    }

    private func normalizeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
