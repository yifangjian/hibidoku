import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.importedAt, order: .reverse) private var books: [Book]
    @State private var showAddBook = false
    @State private var showAozoraLibrary = false

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ContentUnavailableView(
                        "まだ本がありません",
                        systemImage: "book",
                        description: Text("右上の＋ボタンで文章を追加、\n左上のボタンで青空文庫から作品を選びましょう")
                    )
                } else {
                    List {
                        ForEach(books) { book in
                            NavigationLink(value: book) {
                                BookRowView(book: book)
                            }
                        }
                        .onDelete(perform: deleteBooks)
                    }
                }
            }
            .navigationTitle("日々読")
            .navigationDestination(for: Book.self) { book in
                ReadingView(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAozoraLibrary = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddBook = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
            .sheet(isPresented: $showAozoraLibrary) {
                AozoraLibraryView()
            }
        }
    }

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(books[index])
        }
    }
}

// MARK: - Book Row

struct BookRowView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.headline)
            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if book.source == .aozora {
                    Text("青空文庫")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                Text(book.importedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if book.readingProgress > 0 {
                    Text("\(Int(book.readingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
