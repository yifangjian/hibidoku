import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.importedAt, order: .reverse) private var books: [Book]
    @State private var showAddBook = false
    @State private var showAozoraLibrary = false
    @State private var bookToDelete: Book?
    @State private var isPreloading = false
    @State private var preloadFailed = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyStateView
                } else {
                    bookGridView
                }
            }
            .navigationTitle("日々読")
            .navigationDestination(for: Book.self) { book in
                ReadingView(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            hapticLight()
                            showAozoraLibrary = true
                        } label: {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(.indigo)
                        }
                        NavigationLink {
                            VocabularyListView()
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        hapticLight()
                        showAddBook = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
            .sheet(isPresented: $showAozoraLibrary) {
                AozoraLibraryView()
            }
            .task { await preloadSampleBookIfNeeded() }
            .alert("この本を削除しますか？", isPresented: .init(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let book = bookToDelete {
                        hapticMedium()
                        withAnimation(.spring(duration: 0.3)) {
                            modelContext.delete(book)
                        }
                    }
                    bookToDelete = nil
                }
                Button("キャンセル", role: .cancel) {
                    bookToDelete = nil
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            if isPreloading {
                // Downloading sample book
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    VStack(spacing: 6) {
                        Text("サンプル書籍をダウンロード中…")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("夏目漱石「吾輩は猫である」")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            } else {
                Image(systemName: "books.vertical.circle")
                    .font(.system(size: 72))
                    .foregroundStyle(.indigo.opacity(0.5))
                VStack(spacing: 8) {
                    Text("まだ本がありません")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("青空文庫から作品を選ぶか、\n自分の文章を追加しましょう")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if preloadFailed {
                    Text("サンプルのダウンロードに失敗しました")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack(spacing: 16) {
                    Button {
                        hapticLight()
                        showAozoraLibrary = true
                    } label: {
                        Label("青空文庫", systemImage: "books.vertical.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.indigo)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    Button {
                        hapticLight()
                        showAddBook = true
                    } label: {
                        Label("テキスト追加", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Book Grid

    private var bookGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(books) { book in
                    NavigationLink(value: book) {
                        BookCardView(book: book) {
                            bookToDelete = book
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Haptics

    private func hapticLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func hapticMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Preload Sample Book

    private func preloadSampleBookIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "didPreloadSample") else { return }

        let count = (try? modelContext.fetchCount(FetchDescriptor<Book>())) ?? 0
        guard count == 0 else {
            UserDefaults.standard.set(true, forKey: "didPreloadSample")
            return
        }

        withAnimation { isPreloading = true }

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
            modelContext.insert(book)
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: "didPreloadSample")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            withAnimation { preloadFailed = true }
        }

        withAnimation { isPreloading = false }
    }
}

// MARK: - Book Card

struct BookCardView: View {
    @Bindable var book: Book
    var onDelete: () -> Void

    @State private var showColorPicker = false

    private var coverColor: Color {
        book.resolvedColor
    }

    private var coverGradient: LinearGradient {
        LinearGradient(
            colors: [coverColor, coverColor.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover area
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(coverGradient)
                    .frame(height: 160)
                    .overlay(alignment: .topTrailing) {
                        if book.source == .aozora {
                            Text("青空")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(10)
                        }
                    }

                // Title on cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }
                }
                .padding(14)
            }

            // Progress bar + info
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 5)
                        Capsule()
                            .fill(coverColor)
                            .frame(width: geo.size.width * book.readingProgress, height: 5)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text("\(Int(book.readingProgress * 100))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(book.readingProgress > 0 ? coverColor : .secondary)
                    Spacer()
                    Text(book.importedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .contextMenu {
            // Color picker section
            Section("カラータグ") {
                ForEach(BookColorTag.allCases) { tag in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(duration: 0.3)) {
                            book.colorTag = tag
                        }
                    } label: {
                        Label {
                            Text(tag.label)
                        } icon: {
                            Image(systemName: book.colorTag == tag ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(tag.color)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("空書庫") {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
}

#Preview("有書") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, configurations: config)
    let ctx = container.mainContext

    let book1 = Book(title: "羅生門", fullText: "下人の行方は、誰も知らない。", source: .aozora, author: "芥川龍之介")
    book1.readingProgress = 0.35
    book1.colorTag = .purple
    ctx.insert(book1)

    let book2 = Book(title: "我輩は猫である", fullText: "吾輩は猫である。名前はまだ無い。", source: .aozora, author: "夏目漱石")
    book2.colorTag = .teal
    ctx.insert(book2)

    let book3 = Book(title: "日本語メモ", fullText: "今日の勉強ノート", source: .imported)
    book3.readingProgress = 0.8
    book3.colorTag = .orange
    ctx.insert(book3)

    let book4 = Book(title: "坊っちゃん", fullText: "親譲りの無鉄砲で小供の時から損ばかりしている。", source: .aozora, author: "夏目漱石")
    book4.readingProgress = 0.62
    book4.colorTag = .indigo
    ctx.insert(book4)

    let book5 = Book(title: "走れメロス", fullText: "メロスは激怒した。", source: .aozora, author: "太宰治")
    book5.readingProgress = 1.0
    book5.colorTag = .green
    ctx.insert(book5)

    return LibraryView()
        .modelContainer(container)
}
