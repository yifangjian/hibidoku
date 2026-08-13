import SwiftUI

struct ReaderSettingsPanel: View {
    @Bindable var settings: ReaderSettingsModel
    let book: Book
    var onSpeak: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Book info
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.headline)
                        if let author = book.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 16) {
                            Label("\(book.fullText.count) 文字", systemImage: "character.ja")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("\(Int(book.readingProgress * 100))%", systemImage: "book.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Font size
                Section("文字サイズ") {
                    Picker("サイズ", selection: $settings.fontSize) {
                        ForEach(ReaderFontSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("吾輩は猫である")
                        .font(.system(size: settings.fontSize.basePoints))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                // Theme
                Section("テーマ") {
                    HStack(spacing: 16) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                settings.theme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(theme.backgroundColor)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(
                                                    settings.theme == theme
                                                        ? Color.accentColor
                                                        : Color.gray.opacity(0.3),
                                                    lineWidth: settings.theme == theme ? 2.5 : 1
                                                )
                                        )
                                        .overlay(
                                            Text("あ")
                                                .foregroundStyle(theme.textColor)
                                                .font(.title3)
                                        )
                                        .frame(height: 48)
                                    Text(theme.label)
                                        .font(.caption2)
                                        .foregroundStyle(
                                            settings.theme == theme ? .primary : .secondary
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Brightness
                Section("明るさ") {
                    HStack {
                        Image(systemName: "sun.min")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.brightness, in: 0.1...1.0)
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                // Actions
                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSpeak()
                    } label: {
                        Label("朗読", systemImage: "speaker.wave.2.fill")
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
