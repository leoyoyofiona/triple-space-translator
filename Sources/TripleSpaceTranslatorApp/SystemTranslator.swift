import Foundation
@preconcurrency import Translation

enum TranslationDirection {
    case zhToEn
    case enToZh
}

@MainActor
final class SystemTranslator {
    private let zhHansLanguage = Locale.Language(identifier: "zh-Hans")
    private let enLanguage = Locale.Language(identifier: "en")

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        let sourceLanguage: Locale.Language
        let targetLanguage: Locale.Language

        switch direction {
        case .zhToEn:
            sourceLanguage = zhHansLanguage
            targetLanguage = enLanguage
        case .enToZh:
            sourceLanguage = enLanguage
            targetLanguage = zhHansLanguage
        }

        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        let response = try await session.translate(text)
        return response.targetText
    }
}
