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
}
