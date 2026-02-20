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
            if usedCutFallback {
                _ = textController.replaceCurrentInputViaPasteFallback(originalText)
            }
            lastStatus = "输入为空，未执行翻译"
            return
        }

        let normalizedInput = inputWithoutTrigger.translationCacheKey
        if let pairTarget = pairToggleTarget(for: normalizedInput) {
            let replaced: Bool
            if usedCutFallback {
                replaced = textController.replaceCurrentInputViaPasteFallback(pairTarget)
            } else {
                replaced = textController.replaceFocusedText(with: pairTarget)
            }

            if replaced {
                cacheTranslationPair(source: inputWithoutTrigger, target: pairTarget)
                lastTranslationPair = (left: inputWithoutTrigger, right: pairTarget)
                lastAppliedOutputText = pairTarget
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
            let replaced: Bool
            if usedCutFallback {
                replaced = textController.replaceCurrentInputViaPasteFallback(cachedText)
            } else {
                replaced = textController.replaceFocusedText(with: cachedText)
            }

            if replaced {
                cacheTranslationPair(source: inputWithoutTrigger, target: cachedText)
                lastTranslationPair = (left: inputWithoutTrigger, right: cachedText)
                lastAppliedOutputText = cachedText
                lastStatus = "已从最近翻译记录切换回对应文本"
            } else {
                if usedCutFallback {
                    _ = textController.replaceCurrentInputViaPasteFallback(originalText)
                }
                lastStatus = "切换失败：当前输入框不支持替换"
            }
            return
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
            lastAppliedOutputText = translated

            let replaced: Bool
            if usedCutFallback {
                replaced = textController.replaceCurrentInputViaPasteFallback(translated)
            } else {
                replaced = textController.replaceFocusedText(with: translated)
            }

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

        let leftNorm = pair.left.translationCacheKey
        let rightNorm = pair.right.translationCacheKey

        // Prefer alternating from the last applied output to tolerate stale text reads from some editors.
        if let lastApplied = lastAppliedOutputText?.translationCacheKey {
            if looksEquivalent(lastApplied, leftNorm),
               looksEquivalent(currentInput, leftNorm) || looksEquivalent(currentInput, rightNorm) {
                return pair.right
            }
            if looksEquivalent(lastApplied, rightNorm),
               looksEquivalent(currentInput, leftNorm) || looksEquivalent(currentInput, rightNorm) {
                return pair.left
            }
        }

        if looksEquivalent(currentInput, leftNorm) {
            return pair.right
        }
        if looksEquivalent(currentInput, rightNorm) {
            return pair.left
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
