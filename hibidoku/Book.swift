import Foundation
import SwiftUI
import SwiftData

enum BookSource: String, Codable {
    case imported
    case aozora
}

enum BookColorTag: String, Codable, CaseIterable, Identifiable {
    case red, orange, pink, purple, indigo, blue, teal, mint, green, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:    .red
        case .orange: .orange
        case .pink:   .pink
        case .purple: .purple
        case .indigo: .indigo
        case .blue:   .blue
        case .teal:   .teal
        case .mint:   .mint
        case .green:  .green
        case .gray:   Color(.systemGray)
        }
    }

    var label: String {
        switch self {
        case .red:    "赤"
        case .orange: "橙"
        case .pink:   "桃"
        case .purple: "紫"
        case .indigo: "藍"
        case .blue:   "青"
        case .teal:   "碧"
        case .mint:   "翠"
        case .green:  "緑"
        case .gray:   "灰"
        }
    }

    /// Pick a default color based on a string hash.
    static func fromHash(_ string: String) -> BookColorTag {
        let hash = abs(string.hashValue)
        return BookColorTag.allCases[hash % BookColorTag.allCases.count]
    }
}

@Model
final class Book {
    var title: String
    var fullText: String
    var source: BookSource
    var importedAt: Date
    var readingProgress: Double
    var author: String?
    var colorTag: BookColorTag?

    init(title: String, fullText: String, source: BookSource = .imported, author: String? = nil) {
        self.title = title
        self.fullText = fullText
        self.source = source
        self.importedAt = Date()
        self.readingProgress = 0.0
        self.author = author
        self.colorTag = nil
    }

    /// Resolved color: user-chosen or auto-generated from title.
    var resolvedColor: Color {
        (colorTag ?? BookColorTag.fromHash(title)).color
    }
}
