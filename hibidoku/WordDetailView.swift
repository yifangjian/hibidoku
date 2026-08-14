import SwiftUI
import SwiftData

struct WordDetailView: View {
    let token: FuriganaToken
    let lookupResult: LookupResult
    var bookTitle: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isSaved = false
    @State private var showSavedCheck = false

    private var entries: [DictEntry] { lookupResult.entries }

    /// Group entries by entry ID so multiple senses of the same word show together.
    private var groupedEntries: [(id: Int, kanji: String?, kana: String, senses: [(pos: String?, glosses: String)])] {
        var groups: [(id: Int, kanji: String?, kana: String, senses: [(pos: String?, glosses: String)])] = []
        var indexMap: [Int: Int] = [:] // entryId → index in groups

        for entry in entries {
            if let idx = indexMap[entry.id] {
                groups[idx].senses.append((pos: entry.partsOfSpeech, glosses: entry.glosses))
            } else {
                indexMap[entry.id] = groups.count
                groups.append((
                    id: entry.id,
                    kanji: entry.kanjiText,
                    kana: entry.kanaText,
                    senses: [(pos: entry.partsOfSpeech, glosses: entry.glosses)]
                ))
            }
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    wordHeader
                    Divider().padding(.horizontal)

                    if entries.isEmpty {
                        emptyState
                    } else {
                        entriesList
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("単語")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !entries.isEmpty {
                        Button {
                            saveWord()
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(isSaved ? .orange : .primary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if showSavedCheck {
                    savedToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onAppear { checkIfSaved() }
    }

    // MARK: - Word Header

    private var wordHeader: some View {
        VStack(spacing: 8) {
            Text(token.surface)
                .font(.system(size: 42, weight: .bold, design: .serif))

            if let reading = token.reading {
                Text(reading)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Show matched form if it differs from surface (deinflection result)
            if let matched = lookupResult.matchedForm,
               matched != token.surface {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(matched)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
    }

    // MARK: - Entries List

    private var entriesList: some View {
        VStack(spacing: 12) {
            ForEach(Array(groupedEntries.enumerated()), id: \.element.id) { index, group in
                VStack(alignment: .leading, spacing: 10) {
                    // Entry header (kanji + kana if different from tapped word)
                    if let kanji = group.kanji, kanji != token.surface {
                        HStack(spacing: 8) {
                            Text(kanji)
                                .font(.headline)
                            Text("【\(group.kana)】")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if group.kana != token.surface && group.kana != token.reading {
                        Text(group.kana)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Senses
                    ForEach(Array(group.senses.enumerated()), id: \.offset) { senseIdx, sense in
                        HStack(alignment: .top, spacing: 10) {
                            // Sense number
                            if group.senses.count > 1 {
                                Text("\(senseIdx + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.indigo)
                                    .clipShape(Circle())
                                    .padding(.top, 1)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let pos = sense.pos, !pos.isEmpty {
                                    Text(posAbbreviation(pos))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.indigo)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(.indigo.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                Text(sense.glosses)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("辞書に見つかりません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Saved Toast

    private var savedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.orange)
            Text(isSaved ? "生詞帳に保存しました" : "生詞帳から削除しました")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 8, y: 4)
        .padding(.top, 8)
    }

    // MARK: - Save / Unsave

    private func checkIfSaved() {
        let surface = token.surface
        let descriptor = FetchDescriptor<SavedWord>(
            predicate: #Predicate { $0.surface == surface }
        )
        isSaved = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func saveWord() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if isSaved {
            // Remove
            let surface = token.surface
            let descriptor = FetchDescriptor<SavedWord>(
                predicate: #Predicate { $0.surface == surface }
            )
            if let existing = try? modelContext.fetch(descriptor) {
                for word in existing { modelContext.delete(word) }
            }
            isSaved = false
        } else {
            // Save the first entry's info
            let glosses = entries.map(\.glosses).joined(separator: "; ")
            let pos = entries.first?.partsOfSpeech
            let word = SavedWord(
                surface: token.surface,
                reading: token.reading ?? entries.first?.kanaText,
                glosses: glosses,
                partsOfSpeech: pos,
                bookTitle: bookTitle
            )
            modelContext.insert(word)
            isSaved = true
        }

        withAnimation(.spring(duration: 0.3)) { showSavedCheck = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSavedCheck = false }
        }
    }

    // MARK: - Helpers

    /// Abbreviate long POS strings for compact display
    private func posAbbreviation(_ pos: String) -> String {
        pos.replacingOccurrences(of: "noun (common) (futsuumeishi)", with: "名詞")
            .replacingOccurrences(of: "noun or participle which takes the aux. verb suru", with: "サ変名詞")
            .replacingOccurrences(of: "Ichidan verb", with: "一段動詞")
            .replacingOccurrences(of: "Godan verb with", with: "五段動詞 ·")
            .replacingOccurrences(of: "expressions (phrases, clauses, etc.)", with: "表現")
            .replacingOccurrences(of: "adverb (fukushi)", with: "副詞")
            .replacingOccurrences(of: "adjective (keiyoushi)", with: "形容詞")
            .replacingOccurrences(of: "na-adjective (keiyodoshi)", with: "形容動詞")
            .replacingOccurrences(of: "intransitive verb", with: "自動詞")
            .replacingOccurrences(of: "transitive verb", with: "他動詞")
            .replacingOccurrences(of: "pre-noun adjectival (rentaishi)", with: "連体詞")
            .replacingOccurrences(of: "conjunction", with: "接続詞")
            .replacingOccurrences(of: "particle", with: "助詞")
            .replacingOccurrences(of: "auxiliary verb", with: "補助動詞")
            .replacingOccurrences(of: "suffix", with: "接尾")
            .replacingOccurrences(of: "prefix", with: "接頭")
            .replacingOccurrences(of: "pronoun", with: "代名詞")
            .replacingOccurrences(of: "counter", with: "助数詞")
            .replacingOccurrences(of: "interjection (kandoushi)", with: "感動詞")
    }
}
