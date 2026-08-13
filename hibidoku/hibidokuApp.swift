import SwiftUI
import SwiftData

@main
struct hibidokuApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Book.self)
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .task { await preloadSampleBookIfNeeded() }
        }
        .modelContainer(container)
    }

    /// On first launch, download 「吾輩は猫である」 as a sample book.
    private func preloadSampleBookIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "didPreloadSample") else { return }

        let context = container.mainContext

        // Check if user already has books
        let count = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0
        guard count == 0 else {
            UserDefaults.standard.set(true, forKey: "didPreloadSample")
            return
        }

        // Work ID 789 = 吾輩は猫である by 夏目漱石
        let work = AozoraService.Work(
            id: 789,
            title: "吾輩は猫である",
            titleReading: "わがはいはねこである",
            authorId: 148,
            authorName: "夏目漱石",
            orthography: "新字新仮名",
            textURL: "https://www.aozora.gr.jp/cards/000148/files/789_ruby_5639.zip",
            textEncoding: "ShiftJIS"
        )

        do {
            let text = try await AozoraService.shared.downloadText(for: work)
            let book = Book(title: work.title, fullText: text, source: .aozora, author: work.authorName)
            context.insert(book)
            try context.save()
            UserDefaults.standard.set(true, forKey: "didPreloadSample")
        } catch {
            // Silently fail — user can always download manually
        }
    }
}
