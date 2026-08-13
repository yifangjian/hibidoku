import SwiftUI
import SwiftData

struct AozoraLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var authors: [AozoraService.Author] = []
    @State private var searchedWorks: [AozoraService.Work] = []
    @State private var searchedAuthors: [AozoraService.Author] = []
    @State private var selectedAuthor: AozoraService.Author?
    @State private var authorWorks: [AozoraService.Work] = []
    @State private var downloadingWorkId: Int?
    @State private var errorMessage: String?

    private let service = AozoraService.shared

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    topAuthorsView
                } else {
                    searchResultsView
                }
            }
            .navigationTitle("青空文庫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "搜尋作品名或作者名")
            .onChange(of: searchText) { _, newValue in
                performSearch(newValue)
            }
            .navigationDestination(item: $selectedAuthor) { author in
                authorWorksView(author)
            }
            .alert("下載失敗", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("確定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { loadTopAuthors() }
        }
    }

    // MARK: - Top Authors

    private var topAuthorsView: some View {
        List(authors) { author in
            Button {
                selectedAuthor = author
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(author.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if let reading = author.nameReading {
                            Text(reading)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(author.workCount) 作品")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        List {
            if !searchedAuthors.isEmpty {
                Section("作者") {
                    ForEach(searchedAuthors) { author in
                        Button {
                            selectedAuthor = author
                        } label: {
                            HStack {
                                Text(author.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(author.workCount) 作品")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !searchedWorks.isEmpty {
                Section("作品") {
                    ForEach(searchedWorks) { work in
                        workRow(work)
                    }
                }
            }
            if searchedAuthors.isEmpty && searchedWorks.isEmpty {
                ContentUnavailableView("找不到結果", systemImage: "magnifyingglass")
            }
        }
    }

    // MARK: - Author Works

    private func authorWorksView(_ author: AozoraService.Author) -> some View {
        List(authorWorks) { work in
            workRow(work)
        }
        .navigationTitle(author.name)
        .onAppear {
            authorWorks = service.works(byAuthorId: author.id)
        }
    }

    // MARK: - Work Row

    private func workRow(_ work: AozoraService.Work) -> some View {
        Button {
            downloadWork(work)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(work.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if downloadingWorkId == work.id {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(downloadingWorkId != nil)
    }

    // MARK: - Actions

    private func loadTopAuthors() {
        if authors.isEmpty {
            authors = service.topAuthors(limit: 50)
        }
    }

    private func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchedWorks = []
            searchedAuthors = []
            return
        }
        searchedAuthors = service.searchAuthors(query: trimmed)
        searchedWorks = service.searchWorks(query: trimmed)
    }

    private func downloadWork(_ work: AozoraService.Work) {
        downloadingWorkId = work.id
        Task {
            do {
                let text = try await service.downloadText(for: work)
                let book = Book(
                    title: work.title,
                    fullText: text,
                    source: .aozora,
                    author: work.authorName
                )
                modelContext.insert(book)
                try modelContext.save()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                downloadingWorkId = nil
            }
        }
    }
}

// MARK: - Hashable conformance for navigation

extension AozoraService.Author: Hashable {
    static func == (lhs: AozoraService.Author, rhs: AozoraService.Author) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
