import Foundation
@preconcurrency import Translation

@MainActor
final class SystemTranslator {
    private let sourceLanguage = Locale.Language(identifier: "zh-Hans")
    private let targetLanguage = Locale.Language(identifier: "en")

    func translateToEnglish(_ text: String) async throws -> String {
        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        let response = try await session.translate(text)
        return response.targetText
    }
}
