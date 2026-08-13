import Foundation

struct FuriganaToken {
    let surface: String
    let reading: String?
}

enum JapaneseTokenizer {

    static func tokenize(_ text: String) -> [FuriganaToken] {
        guard !text.isEmpty else { return [] }

        let nsText = text as NSString
        let cfText = text as CFString
        let length = nsText.length

        let locale = Locale(identifier: "ja") as CFLocale

        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            CFRangeMake(0, length),
            kCFStringTokenizerUnitWordBoundary,
            locale
        )

        var tokens: [FuriganaToken] = []
        var currentIndex = 0

        var tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType.rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)

            // Capture any gap before this token (punctuation, whitespace, etc.)
            if range.location > currentIndex {
                let gapRange = NSRange(location: currentIndex, length: range.location - currentIndex)
                let gapText = nsText.substring(with: gapRange)
                tokens.append(FuriganaToken(surface: gapText, reading: nil))
            }

            let surfaceRange = NSRange(location: range.location, length: range.length)
            let surface = nsText.substring(with: surfaceRange)

            var reading: String? = nil
            if containsKanji(surface),
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                   tokenizer, kCFStringTokenizerAttributeLatinTranscription
               ) as? String {
                let mutable = NSMutableString(string: latin)
                CFStringTransform(mutable, nil, "Latin-Hiragana" as CFString, false)
                reading = mutable as String
            }

            tokens.append(FuriganaToken(surface: surface, reading: reading))
            currentIndex = range.location + range.length

            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // Capture any trailing text after the last token
        if currentIndex < length {
            let trailingRange = NSRange(location: currentIndex, length: length - currentIndex)
            let trailingText = nsText.substring(with: trailingRange)
            tokens.append(FuriganaToken(surface: trailingText, reading: nil))
        }

        return tokens
    }

    /// Split text into sentences by Japanese sentence terminators (。！？) and newlines.
    static func splitSentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if "。！？\n".contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }
        return sentences
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
