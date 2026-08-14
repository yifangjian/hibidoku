import SwiftUI
import SwiftData

struct VocabularyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWord.savedAt, order: .reverse) private var words: [SavedWord]
    @State private var searchText = ""

    private var filteredWords: [SavedWord] {
        guard !searchText.isEmpty else { return words }
        let query = searchText.lowercased()
        return words.filter { word in
            word.surface.lowercased().contains(query) ||
            (word.reading?.lowercased().contains(query) ?? false) ||
            word.glosses.lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if words.isEmpty {
                emptyState
            } else {
                wordList
            }
        }
        .navigationTitle("生詞帳")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange.opacity(0.4))
            VStack(spacing: 6) {
                Text("まだ単語が保存されていません")
                    .font(.title3.weight(.semibold))
                Text("読書中に単語をタップして\nブックマークアイコンで保存できます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    // MARK: - Word List

    private var wordList: some View {
        List {
            ForEach(filteredWords) { word in
                wordRow(word)
            }
            .onDelete(perform: deleteWords)
        }
        .searchable(text: $searchText, prompt: "単語を検索…")
        .listStyle(.insetGrouped)
    }

    private func wordRow(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.surface)
                    .font(.title3.weight(.bold))
                if let reading = word.reading, !reading.isEmpty {
                    Text(reading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(word.glosses)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(2)

            HStack(spacing: 8) {
                if let pos = word.partsOfSpeech, !pos.isEmpty {
                    Text(posShort(pos))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.indigo.opacity(0.1))
                        .clipShape(Capsule())
                }
                if let book = word.bookTitle, !book.isEmpty {
                    Text(book)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(word.savedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteWords(at offsets: IndexSet) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for index in offsets {
            let word = filteredWords[index]
            modelContext.delete(word)
        }
    }

    private func posShort(_ pos: String) -> String {
        // Take just the first POS if there are multiples
        let first = pos.components(separatedBy: ", ").first ?? pos
        return first
            .replacingOccurrences(of: "noun (common) (futsuumeishi)", with: "名詞")
            .replacingOccurrences(of: "Ichidan verb", with: "一段")
            .replacingOccurrences(of: "Godan verb with", with: "五段 ·")
            .replacingOccurrences(of: "adjective (keiyoushi)", with: "形容詞")
            .replacingOccurrences(of: "na-adjective (keiyodoshi)", with: "形容動詞")
            .replacingOccurrences(of: "adverb (fukushi)", with: "副詞")
    }
}
