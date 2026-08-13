import SwiftUI
import SwiftData

@main
struct hibidokuApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: Book.self)
    }
}
