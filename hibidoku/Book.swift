import Foundation
import SwiftData

enum BookSource: String, Codable {
    case imported
    case aozora
}

@Model
final class Book {
    var title: String
    var fullText: String
    var source: BookSource
    var importedAt: Date
    var readingProgress: Double
    var author: String?

    init(title: String, fullText: String, source: BookSource = .imported, author: String? = nil) {
        self.title = title
        self.fullText = fullText
        self.source = source
        self.importedAt = Date()
        self.readingProgress = 0.0
        self.author = author
    }
}
