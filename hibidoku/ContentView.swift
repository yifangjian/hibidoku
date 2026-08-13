import SwiftUI
import AVFoundation

struct SentenceTranslation: Identifiable {
    let id = UUID()
    let sentence: String
    var translation: String = ""
}

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var annotatedText: NSAttributedString?
    @State private var synthesizer = AVSpeechSynthesizer()

    // Token tap / dictionary
    @State private var currentTokens: [FuriganaToken] = []
    @State private var currentTokenRanges: [TokenRange] = []
    @State private var selectedToken: FuriganaToken?
    @State private var dictEntries: [DictEntry] = []
    @State private var showWordDetail = false

    // Sentence translations
    @State private var sentenceTranslations: [SentenceTranslation] = []

    private var hasInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Input area
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inputText)
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    if inputText.isEmpty {
                        Text("日本語の文章をここに貼り付けてください…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }

                // Buttons
                HStack(spacing: 20) {
                    Button("標音") {
                        annotateAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasInput)

                    Button("朗讀") {
                        speakAction()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasInput)
                }

                // Results area
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
                }
                .scrollDismissesKeyboard(.interactively)

                Spacer()
            }
            .padding()
            .navigationTitle("日々読")
            .toolbar {
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
        }
    }

    private func annotateAction() {
        let tokens = JapaneseTokenizer.tokenize(inputText)
        let result = RubyTextView.buildAnnotatedResult(from: tokens)

        currentTokens = tokens
        currentTokenRanges = result.tokenRanges
        annotatedText = result.attributedString

        sentenceTranslations = JapaneseTokenizer.splitSentences(inputText)
            .map { SentenceTranslation(sentence: $0) }
    }

    private func speakAction() {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: inputText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func handleTokenTap(_ tokenIndex: Int) {
        guard tokenIndex >= 0 && tokenIndex < currentTokens.count else { return }
        let token = currentTokens[tokenIndex]

        // Skip whitespace/punctuation-only tokens
        let trimmed = token.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        selectedToken = token
        dictEntries = DictionaryService.shared.lookup(token.surface)
        showWordDetail = true
    }
}

#Preview {
    ContentView()
}
