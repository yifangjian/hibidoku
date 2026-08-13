import SwiftUI
import AVFoundation

struct SentenceTranslation: Identifiable {
    let id = UUID()
    let sentence: String
    var translation: String = ""
}

struct ReadingView: View {
    @Bindable var book: Book

    @State private var annotatedText: NSAttributedString?
    @State private var currentTokens: [FuriganaToken] = []
    @State private var currentTokenRanges: [TokenRange] = []
    @State private var sentenceTranslations: [SentenceTranslation] = []
    @State private var synthesizer = AVSpeechSynthesizer()

    // Dictionary lookup
    @State private var selectedToken: FuriganaToken?
    @State private var dictEntries: [DictEntry] = []
    @State private var showWordDetail = false

    // Progress tracking
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Furigana display (tappable)
                if annotatedText != nil {
                    FuriganaDisplayView(
                        attributedText: annotatedText,
                        tokenRanges: currentTokenRanges,
                        onTokenTapped: { tokenIndex in
                            handleTokenTap(tokenIndex)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Sentence translation fields
                if !sentenceTranslations.isEmpty {
                    Divider()

                    Text("翻訳")
                        .font(.headline)

                    ForEach($sentenceTranslations) { $item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.sentence)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("翻訳を入力…", text: $item.translation, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...4)
                        }
                    }
                }
            }
            .padding()
            .background(
                GeometryReader { contentGeo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetKey.self,
                            value: contentGeo.frame(in: .named("readingScroll")).origin.y
                        )
                        .onAppear { contentHeight = contentGeo.size.height }
                        .onChange(of: contentGeo.size.height) { _, newVal in
                            contentHeight = newVal
                        }
                }
            )
        }
        .coordinateSpace(name: "readingScroll")
        .background(
            GeometryReader { scrollGeo in
                Color.clear
                    .onAppear { viewportHeight = scrollGeo.size.height }
                    .onChange(of: scrollGeo.size.height) { _, newVal in
                        viewportHeight = newVal
                    }
            }
        )
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            updateProgress(scrollOffset: offset)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("朗讀") {
                    speakAction()
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
        .sheet(isPresented: $showWordDetail) {
            if let token = selectedToken {
                WordDetailView(token: token, entries: dictEntries)
                    .presentationDetents([.medium])
            }
        }
        .onAppear {
            annotateFullText()
        }
    }

    // MARK: - Actions

    private func annotateFullText() {
        let tokens = JapaneseTokenizer.tokenize(book.fullText)
        let result = RubyTextView.buildAnnotatedResult(from: tokens)
        currentTokens = tokens
        currentTokenRanges = result.tokenRanges
        annotatedText = result.attributedString
        sentenceTranslations = JapaneseTokenizer.splitSentences(book.fullText)
            .map { SentenceTranslation(sentence: $0) }
    }

    private func speakAction() {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: book.fullText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func handleTokenTap(_ tokenIndex: Int) {
        guard tokenIndex >= 0 && tokenIndex < currentTokens.count else { return }
        let token = currentTokens[tokenIndex]
        let trimmed = token.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedToken = token
        dictEntries = DictionaryService.shared.lookup(token.surface)
        showWordDetail = true
    }

    private func updateProgress(scrollOffset: CGFloat) {
        let scrollableDistance = contentHeight - viewportHeight
        guard scrollableDistance > 0 else {
            book.readingProgress = 1.0
            return
        }
        let progress = min(max(-scrollOffset / scrollableDistance, 0), 1)
        book.readingProgress = progress
    }
}

// MARK: - Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
