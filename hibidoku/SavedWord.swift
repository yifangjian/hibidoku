import Foundation
import SwiftData

@Model
final class SavedWord {
    var surface: String
    var reading: String?
    var glosses: String
    var partsOfSpeech: String?
    var bookTitle: String?
    var savedAt: Date

    init(surface: String, reading: String?, glosses: String, partsOfSpeech: String?, bookTitle: String?) {
        self.surface = surface
        self.reading = reading
        self.glosses = glosses
        self.partsOfSpeech = partsOfSpeech
        self.bookTitle = bookTitle
        self.savedAt = Date()
    }
}
