import Foundation

/// Cleans Aozora Bunko formatted text into plain Japanese text.
///
/// Removes ruby annotations (《》), pipe markers (｜), editorial notes (［＃...］),
/// and trims header/footer boilerplate.
enum AozoraTextParser {

    /// Clean raw Aozora text into readable plain text.
    static func clean(_ raw: String) -> String {
        var text = raw

        // Remove header: lines before the first blank line (title/author block)
        text = removeHeader(text)

        // Remove footer: everything from "底本：" onward
        text = removeFooter(text)

        // Remove ［＃...］ editorial annotations (e.g. ［＃３字下げ］)
        text = text.replacingOccurrences(
            of: "［＃[^］]*］",
            with: "",
            options: .regularExpression
        )

        // Remove ruby: 漢字《かな》 → 漢字
        // Also handles ｜漢字《かな》 → 漢字
        text = text.replacingOccurrences(
            of: "《[^》]*》",
            with: "",
            options: .regularExpression
        )

        // Remove ｜ (full-width pipe, ruby start marker)
        text = text.replacingOccurrences(of: "｜", with: "")

        // Normalize whitespace: collapse multiple blank lines into one
        text = text.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove the header block (title, author, blank lines at start).
    /// Aozora files typically start with title line, author line, then a blank line.
    private static func removeHeader(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")

        // Find the first blank line (end of header)
        var headerEnd = 0
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty && i > 0 {
                headerEnd = i + 1
                break
            }
        }

        // Skip additional blank lines after header
        while headerEnd < lines.count &&
              lines[headerEnd].trimmingCharacters(in: .whitespaces).isEmpty {
            headerEnd += 1
        }

        guard headerEnd < lines.count else { return text }
        return lines[headerEnd...].joined(separator: "\n")
    }

    /// Remove footer: everything from "底本：" line onward.
    private static func removeFooter(_ text: String) -> String {
        if let range = text.range(of: "\n底本：") {
            return String(text[text.startIndex..<range.lowerBound])
        }
        return text
    }
}
