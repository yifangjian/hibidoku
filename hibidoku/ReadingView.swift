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

                // Paged content with page curl effect
                if !pages.isEmpty {
                    PageCurlView(
                        pages: pages,
                        currentPage: $currentPage,
                        backgroundColor: settings.theme.uiBackgroundColor,
                        contentInsets: UIEdgeInsets(
                            top: pageInsets.top,
                            left: pageInsets.leading,
                            bottom: pageInsets.bottom,
                            right: pageInsets.trailing
                        ),
                        onTokenTapped: { handleTokenTap($0) },
                        onCenterTapped: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                barsVisible.toggle()
                            }
                        },
                        onPageChanged: { onPageChanged($0) }
                    )
                    .ignoresSafeArea()
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

// MARK: - Page Curl View (UIPageViewController wrapper)

struct PageCurlView: UIViewControllerRepresentable {
    let pages: [PageData]
    @Binding var currentPage: Int
    let backgroundColor: UIColor
    let contentInsets: UIEdgeInsets
    var onTokenTapped: ((Int) -> Void)?
    var onCenterTapped: (() -> Void)?
    var onPageChanged: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue]
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false
        pvc.view.backgroundColor = backgroundColor

        // Center tap gesture for toggling bars
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleCenterTap(_:)))
        pvc.view.addGestureRecognizer(tap)

        // Set initial page
        if let initialVC = context.coordinator.viewController(for: currentPage) {
            pvc.setViewControllers([initialVC], direction: .forward, animated: false)
        }

        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        pvc.view.backgroundColor = backgroundColor

        // Update current page if it changed programmatically (e.g. full pagination completed)
        let coord = context.coordinator
        if let currentVC = pvc.viewControllers?.first as? PageContentViewController,
           currentVC.pageIndex != currentPage,
           currentPage < pages.count {
            let direction: UIPageViewController.NavigationDirection =
                currentPage > (currentVC.pageIndex) ? .forward : .reverse
            if let newVC = coord.viewController(for: currentPage) {
                pvc.setViewControllers([newVC], direction: direction, animated: false)
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView

        init(_ parent: PageCurlView) {
            self.parent = parent
        }

        func viewController(for index: Int) -> PageContentViewController? {
            guard index >= 0, index < parent.pages.count else { return nil }
            let vc = PageContentViewController()
            vc.pageIndex = index
            vc.pageData = parent.pages[index]
            vc.bgColor = parent.backgroundColor
            vc.contentInsets = parent.contentInsets
            vc.onTokenTapped = parent.onTokenTapped
            return vc
        }

        // MARK: DataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? PageContentViewController else { return nil }
            return self.viewController(for: vc.pageIndex - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let vc = viewController as? PageContentViewController else { return nil }
            return self.viewController(for: vc.pageIndex + 1)
        }

        // MARK: Delegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let vc = pageViewController.viewControllers?.first as? PageContentViewController else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            parent.onPageChanged?(vc.pageIndex)
        }

        // MARK: Center tap

        @objc func handleCenterTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            guard let viewWidth = gesture.view?.bounds.width else { return }
            let centerStart = viewWidth * 0.3
            let centerEnd = viewWidth * 0.7
            if location.x > centerStart && location.x < centerEnd {
                parent.onCenterTapped?()
            }
        }
    }
}

// MARK: - Page Content ViewController

class PageContentViewController: UIViewController {
    var pageIndex: Int = 0
    var pageData: PageData?
    var bgColor: UIColor = .white
    var contentInsets: UIEdgeInsets = .zero
    var onTokenTapped: ((Int) -> Void)?

    private var rubyView: PagedRubyTextView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgColor

        let ruby = PagedRubyTextView()
        ruby.isOpaque = true
        ruby.backgroundColor = bgColor
        ruby.pageData = pageData
        ruby.onTokenTapped = onTokenTapped
        ruby.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ruby)

        NSLayoutConstraint.activate([
            ruby.topAnchor.constraint(equalTo: view.topAnchor, constant: contentInsets.top),
            ruby.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInsets.left),
            ruby.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -contentInsets.right),
            ruby.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -contentInsets.bottom)
        ])

        self.rubyView = ruby
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
