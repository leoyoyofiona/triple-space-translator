import Foundation

extension String {
    var containsChinese: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,      // CJK Extension A
                 0x4E00...0x9FFF,      // CJK Unified Ideographs
                 0xF900...0xFAFF,      // CJK Compatibility Ideographs
                 0x20000...0x2A6DF,    // CJK Extension B
                 0x2A700...0x2B73F,    // CJK Extension C
                 0x2B740...0x2B81F,    // CJK Extension D
                 0x2B820...0x2CEAF:    // CJK Extension E/F
                return true
            default:
                return false
            }
        }
    }

    var chineseCharacterCount: Int {
        unicodeScalars.reduce(into: 0) { count, scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
                count += 1
            default:
                break
            }
        }
    }

    var englishLetterCount: Int {
        unicodeScalars.reduce(into: 0) { count, scalar in
            guard scalar.isASCII else { return }
            switch scalar.value {
            case 65...90, 97...122:
                count += 1
            default:
                break
            }
        }
    }

    var preferredTranslationDirection: TranslationDirection? {
        let zhCount = chineseCharacterCount
        let enCount = englishLetterCount

        if zhCount == 0 && enCount == 0 {
            return nil
        }

        return zhCount >= enCount ? .zhToEn : .enToZh
    }

    func removingTrailingAsciiSpaces(_ count: Int) -> String {
        guard count > 0 else { return self }
        var result = self
        var removed = 0

        while removed < count, result.last == " " {
            result.removeLast()
            removed += 1
        }

        return removed == count ? result : self
    }

    var translationCacheKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var translationLooseKey: String {
        let trimmed = translationCacheKey
        guard !trimmed.isEmpty else { return "" }

        let filteredScalars = trimmed.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        let normalized = String(String.UnicodeScalarView(filteredScalars))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized
    }
}
