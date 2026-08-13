import SwiftUI
import SwiftData
import AVFoundation

struct ReadingView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    // Settings
    @State private var settings = ReaderSettingsModel()

    // Text data
    @State private var currentTokens: [FuriganaToken] = []

    // Pagination
    @State private var pages: [PageData] = []
    @State private var currentPage: Int = 0
    @State private var pageSize: CGSize = .zero
    @State private var isFullyPaginated = false
    @State private var paginationId = UUID()

    // UI state
    @State private var barsVisible = true
    @State private var showSettings = false
    @State private var isLoading = true

    // Dictionary lookup
    @State private var selectedToken: FuriganaToken?
    @State private var dictEntries: [DictEntry] = []
    @State private var showWordDetail = false

    // TTS
    @State private var synthesizer = AVSpeechSynthesizer()

    private let pageInsets = EdgeInsets(top: 60, leading: 24, bottom: 80, trailing: 24)

    var body: some View {
        GeometryReader { geometry in
            let textAreaSize = CGSize(
                width: geometry.size.width - pageInsets.leading - pageInsets.trailing,
                height: geometry.size.height - pageInsets.top - pageInsets.bottom
            )

            ZStack {
                // Full-screen themed background
                settings.theme.backgroundColor
                    .ignoresSafeArea()

                // Loading indicator
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("ページを準備中…")
                            .font(.subheadline)
                            .foregroundStyle(settings.theme.textColor.opacity(0.6))
                    }
                }

                // Paged content
                if !pages.isEmpty {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                                PagedFuriganaView(
                                    pageData: page,
                                    backgroundColor: settings.theme.uiBackgroundColor,
                                    onTokenTapped: { handleTokenTap($0) }
                                )
                                .padding(.top, pageInsets.top)
                                .padding(.bottom, pageInsets.bottom)
                                .padding(.horizontal, pageInsets.leading)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding(
                        get: { currentPage as Int? },
                        set: { if let p = $0 { onPageChanged(p) } }
                    ))
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let centerStart = geometry.size.width * 0.3
                                let centerEnd = geometry.size.width * 0.7
                                if value.location.x > centerStart && value.location.x < centerEnd {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        barsVisible.toggle()
                                    }
                                }
                            }
                    )
                }

                // Overlay bars
                VStack(spacing: 0) {
                    if barsVisible { topBar }
                    Spacer()
                    if barsVisible { bottomBar }
                }
                .animation(.easeInOut(duration: 0.25), value: barsVisible)

                // Always-visible progress bar
                VStack {
                    Spacer()
                    progressBar
                }
            }
            .onAppear {
                if pageSize != textAreaSize {
                    pageSize = textAreaSize
                    annotateAndPaginate()
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                let newTextArea = CGSize(
                    width: newSize.width - pageInsets.leading - pageInsets.trailing,
                    height: newSize.height - pageInsets.top - pageInsets.bottom
                )
                if newTextArea != pageSize {
                    pageSize = newTextArea
                    rePaginate()
                }
            }
            .onChange(of: settings.fontSize) { _, _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                rePaginate()
            }
            .onChange(of: settings.theme) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                rePaginate()
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!barsVisible)
        .sheet(isPresented: $showWordDetail) {
            if let token = selectedToken {
                WordDetailView(token: token, entries: dictEntries)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel(settings: settings, book: book, onSpeak: speakAction)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(settings.theme.textColor)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(book.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(settings.theme.textColor)
                    .lineLimit(1)
                if let author = book.author {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "textformat.size")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(settings.theme.textColor)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(
            settings.theme.backgroundColor.opacity(0.9)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 4) {
                Text("\(currentPage + 1) / \(max(pages.count, 1))")
                    .font(.caption.monospacedDigit())
                if !isFullyPaginated {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .foregroundStyle(settings.theme.textColor.opacity(0.7))

            Spacer()

            Text("\(Int(book.readingProgress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(settings.theme.textColor.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            settings.theme.backgroundColor.opacity(0.9)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                Rectangle()
                    .fill(book.resolvedColor)
                    .frame(width: geo.size.width * book.readingProgress)
            }
        }
        .frame(height: 2)
        .ignoresSafeArea(edges: .horizontal)
    }

    // MARK: - Pagination

    /// Initial chunk size for fast first-page display.
    private static let initialChunkSize = 3000

    private func annotateAndPaginate() {
        isLoading = true
        isFullyPaginated = false
        let runId = UUID()
        paginationId = runId

        let text = book.fullText
        let fontSize = settings.fontSize.basePoints
        let lineHeight = settings.fontSize.lineHeightMultiple
        let textColor = settings.theme.uiTextColor
        let size = pageSize
        let progress = book.readingProgress

        // Phase 1: Process a small initial chunk for instant display
        let chunkEnd = min(Self.initialChunkSize, text.count)
        let initialText = chunkEnd < text.count
            ? String(text.prefix(chunkEnd))
            : text

        Task.detached(priority: .userInitiated) {
            let initialTokens = JapaneseTokenizer.tokenize(initialText)
            let initialResult = RubyTextView.buildAnnotatedResult(
                from: initialTokens,
                fontSize: fontSize,
                lineHeightMultiple: lineHeight,
                textColor: textColor
            )
            let initialPages = RubyTextView.slicePages(from: initialResult, pageSize: size)
            let firstPages = initialPages.isEmpty
                ? [PageData(attributedString: initialResult.attributedString, tokenRanges: initialResult.tokenRanges)]
                : initialPages

            await MainActor.run {
                guard paginationId == runId else { return }
                currentTokens = initialTokens
                pages = firstPages
                currentPage = 0
                isLoading = false
            }

            // Phase 2: Process the full text in background
            guard chunkEnd < text.count else {
                await MainActor.run {
                    guard paginationId == runId else { return }
                    isFullyPaginated = true
                    let targetPage = min(
                        Int(Double(max(firstPages.count - 1, 0)) * progress),
                        max(firstPages.count - 1, 0)
                    )
                    currentPage = targetPage
                }
                return
            }

            let fullTokens = JapaneseTokenizer.tokenize(text)
            let fullResult = RubyTextView.buildAnnotatedResult(
                from: fullTokens,
                fontSize: fontSize,
                lineHeightMultiple: lineHeight,
                textColor: textColor
            )
            let fullPages = RubyTextView.slicePages(from: fullResult, pageSize: size)
            let finalPages = fullPages.isEmpty
                ? [PageData(attributedString: fullResult.attributedString, tokenRanges: fullResult.tokenRanges)]
                : fullPages
            let targetPage = min(
                Int(Double(max(finalPages.count - 1, 0)) * progress),
                max(finalPages.count - 1, 0)
            )

            await MainActor.run {
                guard paginationId == runId else { return }
                currentTokens = fullTokens
                pages = finalPages
                currentPage = targetPage
                isFullyPaginated = true
            }
        }
    }

    private func rePaginate() {
        guard !book.fullText.isEmpty else { return }
        annotateAndPaginate()
    }

    private func onPageChanged(_ page: Int) {
        guard page != currentPage else { return }
        currentPage = page
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateProgressFromPage(page)
    }

    private func updateProgressFromPage(_ page: Int) {
        guard pages.count > 1 else {
            book.readingProgress = 1.0
            return
        }
        book.readingProgress = Double(page) / Double(pages.count - 1)
    }

    // MARK: - Dictionary Lookup

    private func handleTokenTap(_ tokenIndex: Int) {
        guard tokenIndex >= 0, tokenIndex < currentTokens.count else { return }
        let token = currentTokens[tokenIndex]
        let surface = token.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surface.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedToken = token
        dictEntries = DictionaryService.shared.lookup(surface)
        showWordDetail = true
    }

    // MARK: - TTS

    private func speakAction() {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: book.fullText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, configurations: config)

    let sampleText = """
    親譲りの無鉄砲で小供の時から損ばかりしている。小学校に居る時分学校の二階から飛び降りて一週間ほど腰を抜かした事がある。なぜそんな無闘をしたと聞く人があるかも知れぬ。別段深い理由でもない。新築の二階から首を出していたら、同級生の一人が冗談に、いくら威張っても、そこから飛び降りる事は出来まい。弱虫やーい。と囃したからである。
    小使に負ぶさって帰って来た時、おやじが大きな眼をして二階ぐらいから飛び降りて腰を抜かす奴があるかと云ったから、この次は抜かさずに飛んで見せますと答えた。
    """

    let book = Book(title: "坊っちゃん", fullText: sampleText, source: .aozora, author: "夏目漱石")
    book.readingProgress = 0.3
    container.mainContext.insert(book)

    return NavigationStack {
        ReadingView(book: book)
    }
    .modelContainer(container)
}
