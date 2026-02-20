import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var hasAccessibilityPermission = false
    @Published var hasInputMonitoringPermission = false
    @Published var monitorEnabled = true
    @Published var isTranslating = false
    @Published var lastStatus = "等待触发：在任意输入框里连按三次空格（中英互译）"

    private let permissionManager = PermissionManager()
    private let keyMonitor = GlobalKeyMonitor()
    private let textController = FocusedElementTextController()
    private let translator = SystemTranslator()
    private let maxTranslationCacheEntries = 200
    private var translationCache: [String: String] = [:]
    private var translationCacheKeyOrder: [String] = []
    private var lastTranslationPair: (left: String, right: String)?
    private var lastAppliedOutputText: String?
    private var lastAppliedAt: Date?
    private var lastAppliedBundleID: String?

    init() {
        keyMonitor.onTripleSpace = { [weak self] in
            Task { @MainActor in
                await self?.handleTrigger()
            }
        }

        refreshPermissions()
        updateMonitorState()
    }

    func refreshPermissions() {
        hasAccessibilityPermission = permissionManager.hasAccessibilityPermission
        hasInputMonitoringPermission = permissionManager.hasInputMonitoringPermission
    }

    func requestAccessibilityPermission() {
        permissionManager.requestAccessibilityPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshPermissions()
            self?.updateMonitorState()
        }
    }

    func requestInputMonitoringPermission() {
        permissionManager.requestInputMonitoringPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshPermissions()
            self?.updateMonitorState()
        }
    }

    func setMonitorEnabled(_ enabled: Bool) {
        monitorEnabled = enabled
        updateMonitorState()
    }

    private func updateMonitorState() {
        let canRun = monitorEnabled && hasAccessibilityPermission

        if canRun {
            if keyMonitor.start() {
                lastStatus = "监听中：0.5 秒内三次空格会自动中英互译"
            } else {
                lastStatus = "监听启动失败：请确认已授权 Input Monitoring，并重启应用"
            }
        } else {
            keyMonitor.stop()
            if !hasAccessibilityPermission {
                lastStatus = "等待权限：请开启 Accessibility"
            } else {
                lastStatus = "监听已关闭"
            }
        }
    }

    private func handleTrigger() async {
        guard monitorEnabled else { return }
        guard hasAccessibilityPermission else {
            lastStatus = "未授权：请先开启 Accessibility"
            return
        }
        lastStatus = "已检测到三空格，正在处理..."
        guard !isTranslating else { return }
        let usedCutFallback: Bool
        let originalText: String
        if let text = textController.readFocusedText() {
            usedCutFallback = false
            originalText = text
        } else if let text = textController.captureTextViaSelectAllCutFallback() {
            usedCutFallback = true
            originalText = text
            lastStatus = "已检测到三空格，正在处理（兼容模式）..."
        } else {
            lastStatus = "未检测到可编辑输入框"
            return
        }

        let inputWithoutTrigger = originalText.removingTrailingAsciiSpaces(3)

        guard !inputWithoutTrigger.isEmpty else {
            if let forcedTarget = forcedRecentToggleTarget(for: inputWithoutTrigger, allowUnrelatedInput: true) {
                let replaced = replaceCurrentInput(with: forcedTarget, usedCutFallback: usedCutFallback)
                if replaced {
                    recordAppliedOutput(forcedTarget)
                    lastStatus = "已按最近结果反向切换"
                    return
                }
            }
            if usedCutFallback {
                _ = textController.replaceCurrentInputViaPasteFallback(originalText)
            }
            lastStatus = "输入为空，未执行翻译"
            return
        }

        let normalizedInput = inputWithoutTrigger.translationCacheKey
        if let pairTarget = pairToggleTarget(for: inputWithoutTrigger) {
            let replaced = replaceCurrentInput(with: pairTarget, usedCutFallback: usedCutFallback)

            if replaced {
                cacheTranslationPair(source: inputWithoutTrigger, target: pairTarget)
                lastTranslationPair = (left: inputWithoutTrigger, right: pairTarget)
                recordAppliedOutput(pairTarget)
                lastStatus = "已切换回上一轮对应文本"
            } else {
                if usedCutFallback {
                    _ = textController.replaceCurrentInputViaPasteFallback(originalText)
                }
                lastStatus = "切换失败：当前输入框不支持替换"
            }
            return
        }

        if let cachedText = cachedTranslation(for: normalizedInput) {
            let replaced = replaceCurrentInput(with: cachedText, usedCutFallback: usedCutFallback)

            if replaced {
                cacheTranslationPair(source: inputWithoutTrigger, target: cachedText)
                lastTranslationPair = (left: inputWithoutTrigger, right: cachedText)
                recordAppliedOutput(cachedText)
                lastStatus = "已从最近翻译记录切换回对应文本"
            } else {
                if usedCutFallback {
                    _ = textController.replaceCurrentInputViaPasteFallback(originalText)
                }
                lastStatus = "切换失败：当前输入框不支持替换"
            }
            return
        }

        if let forcedTarget = forcedRecentToggleTarget(for: inputWithoutTrigger, allowUnrelatedInput: false) {
            let replaced = replaceCurrentInput(with: forcedTarget, usedCutFallback: usedCutFallback)
            if replaced {
                cacheTranslationPair(source: inputWithoutTrigger, target: forcedTarget)
                lastTranslationPair = (left: inputWithoutTrigger, right: forcedTarget)
                recordAppliedOutput(forcedTarget)
                lastStatus = "已按最近结果反向切换"
                return
            }
        }

        guard let direction = inputWithoutTrigger.preferredTranslationDirection else {
            if usedCutFallback {
                _ = textController.replaceCurrentInputViaPasteFallback(originalText)
            }
            lastStatus = "当前输入不含可识别的中英文内容，已忽略"
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let targetLanguageLabel: String
            switch direction {
            case .zhToEn:
                lastStatus = "检测到中文，正在翻译为英文..."
                targetLanguageLabel = "英文"
            case .enToZh:
                lastStatus = "检测到英文，正在翻译为中文..."
                targetLanguageLabel = "中文"
            }

            let translated = try await translator.translate(inputWithoutTrigger, direction: direction)
            cacheTranslationPair(source: inputWithoutTrigger, target: translated)
            lastTranslationPair = (left: inputWithoutTrigger, right: translated)
            recordAppliedOutput(translated)

            let replaced = replaceCurrentInput(with: translated, usedCutFallback: usedCutFallback)

            if replaced {
                lastStatus = "翻译完成并已替换为\(targetLanguageLabel)"
            } else {
                if usedCutFallback {
                    _ = textController.replaceCurrentInputViaPasteFallback(originalText)
                }
                lastStatus = "替换失败：当前输入框不支持 AX 值写入"
            }
        } catch {
            if usedCutFallback {
                _ = textController.replaceCurrentInputViaPasteFallback(originalText)
            }
            lastStatus = "翻译失败：\(error.localizedDescription)"
        }
    }

    private func cachedTranslation(for normalizedSource: String) -> String? {
        guard !normalizedSource.isEmpty else { return nil }
        if let direct = translationCache[normalizedSource], direct.translationCacheKey != normalizedSource {
            return direct
        }

        let looseSource = normalizedSource.translationLooseKey
        guard !looseSource.isEmpty else { return nil }

        if let fuzzy = translationCache.first(where: { key, _ in
            key.translationLooseKey == looseSource
        })?.value, fuzzy.translationLooseKey != looseSource {
            return fuzzy
        }

        if let contained = translationCache.first(where: { key, _ in
            looksEquivalent(normalizedSource, key)
        })?.value, !looksEquivalent(contained, normalizedSource) {
            return contained
        }

        return nil
    }

    private func pairToggleTarget(for currentInput: String) -> String? {
        guard !currentInput.isEmpty, let pair = lastTranslationPair else { return nil }
        guard let lastApplied = lastAppliedOutputText else { return nil }

        let leftNorm = pair.left.translationCacheKey
        let rightNorm = pair.right.translationCacheKey
        guard !leftNorm.isEmpty, !rightNorm.isEmpty else { return nil }

        let currentMatchesEither = looksEquivalent(currentInput, leftNorm) || looksEquivalent(currentInput, rightNorm)
        guard currentMatchesEither else { return nil }

        // Keep toggle context bound to recent operation and current app to avoid unrelated text hijacking.
        if let at = lastAppliedAt, Date().timeIntervalSince(at) > 90 {
            return nil
        }
        if let bundle = lastAppliedBundleID?.lowercased(),
           let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased(),
           bundle != currentBundle {
            return nil
        }

        // Core rule: alternate from what we last wrote, not from what we just read.
        if looksEquivalent(lastApplied, leftNorm) {
            return pair.right
        }
        if looksEquivalent(lastApplied, rightNorm) {
            return pair.left
        }

        if looksEquivalent(currentInput, leftNorm) {
            return pair.right
        }
        if looksEquivalent(currentInput, rightNorm) {
            return pair.left
        }
        return nil
    }

    private func forcedRecentToggleTarget(for currentInput: String, allowUnrelatedInput: Bool) -> String? {
        guard let pair = lastTranslationPair, let lastApplied = lastAppliedOutputText else { return nil }
        guard let at = lastAppliedAt, Date().timeIntervalSince(at) <= 12 else { return nil }
        if let bundle = lastAppliedBundleID?.lowercased(),
           let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased(),
           bundle != currentBundle {
            return nil
        }

        let left = pair.left.translationCacheKey
        let right = pair.right.translationCacheKey
        guard !left.isEmpty, !right.isEmpty else { return nil }

        let opposite: String
        if looksEquivalent(lastApplied, left) {
            opposite = pair.right
        } else if looksEquivalent(lastApplied, right) {
            opposite = pair.left
        } else {
            return nil
        }

        if allowUnrelatedInput {
            return opposite
        }

        let currentMatchesEither = looksEquivalent(currentInput, left) || looksEquivalent(currentInput, right)
        if currentMatchesEither {
            return opposite
        }

        // If user triggers triple-space again almost immediately, prefer toggling even if read text drifts.
        if Date().timeIntervalSince(at) <= 2.0 {
            return opposite
        }

        return nil
    }

    private func looksEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.translationCacheKey
        let right = rhs.translationCacheKey
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }

        let leftLoose = left.translationLooseKey
        let rightLoose = right.translationLooseKey
        guard !leftLoose.isEmpty, !rightLoose.isEmpty else { return false }
        if leftLoose == rightLoose { return true }

        let minLen = min(leftLoose.count, rightLoose.count)
        if minLen >= 4 && (leftLoose.contains(rightLoose) || rightLoose.contains(leftLoose)) {
            return true
        }

        return false
    }

    private func recordAppliedOutput(_ output: String) {
        lastAppliedOutputText = output
        lastAppliedAt = Date()
        lastAppliedBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func replaceCurrentInput(with text: String, usedCutFallback: Bool) -> Bool {
        if usedCutFallback {
            return textController.replaceCurrentInputViaPasteFallback(text)
        }
        return textController.replaceFocusedText(with: text)
    }

    private func cacheTranslationPair(source: String, target: String) {
        let sourceKey = source.translationCacheKey
        let targetKey = target.translationCacheKey

        guard !sourceKey.isEmpty, !targetKey.isEmpty, sourceKey != targetKey else {
            return
        }

        upsertTranslationCache(key: sourceKey, value: target)
        upsertTranslationCache(key: targetKey, value: source)
    }

    private func upsertTranslationCache(key: String, value: String) {
        if translationCache[key] == nil {
            translationCacheKeyOrder.append(key)
        }
        translationCache[key] = value

        while translationCacheKeyOrder.count > maxTranslationCacheEntries {
            let removedKey = translationCacheKeyOrder.removeFirst()
            translationCache.removeValue(forKey: removedKey)
        }
    }
}
