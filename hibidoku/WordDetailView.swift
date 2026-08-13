import SwiftUI

struct WordDetailView: View {
    let token: FuriganaToken
    let entries: [DictEntry]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Word header
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(token.surface)
                            .font(.largeTitle)
                        if let reading = token.reading {
                            Text(reading)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Dictionary entries
                if entries.isEmpty {
                    Section {
                        Text("辞書に見つかりません")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("辞書") {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                if let pos = entry.partsOfSpeech, !pos.isEmpty {
                                    Text(pos)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.glosses)
                                    .font(.body)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("単語")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}
