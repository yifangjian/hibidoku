import UIKit
import CoreText
import SwiftUI

// MARK: - Token Range Mapping

nonisolated struct TokenRange: Sendable {
    let start: Int
    let length: Int
    let tokenIndex: Int
}

nonisolated struct AnnotatedResult: @unchecked Sendable {
    let attributedString: NSAttributedString
    let tokenRanges: [TokenRange]
}

/// Pre-sliced page data — each page has its own small attributed string.
nonisolated struct PageData: @unchecked Sendable {
    let attributedString: NSAttributedString
    let tokenRanges: [TokenRange]
}

// MARK: - RubyTextView (CoreText direct drawing + tap detection)

/// Custom UIView that renders text with CTRubyAnnotation using CoreText.
/// UILabel and UITextView silently ignore CTRubyAnnotation since iOS 11,
/// so direct CoreText drawing is the only reliable approach.
class RubyTextView: UIView {

    var attributedText: NSAttributedString? {
        didSet {
            ctFrame = nil
            setNeedsDisplay()
            invalidateIntrinsicContentSize()
        }
    }

    var tokenRanges: [TokenRange] = []
    var onTokenTapped: ((Int) -> Void)?

    private var preferredMaxLayoutWidth: CGFloat = 0
    private var ctFrame: CTFrame?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentMode = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    override func draw(_ rect: CGRect) {
        guard let attributedText = attributedText,
              let context = UIGraphicsGetCurrentContext() else { return }

        // CoreText uses bottom-left origin; UIKit uses top-left. Flip.
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let path = CGMutablePath()
        path.addRect(bounds)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

        // Cache for tap detection
        self.ctFrame = frame

        CTFrameDraw(frame, context)
    }

    override var intrinsicContentSize: CGSize {
        guard let attributedText = attributedText else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let maxWidth = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : CGFloat.greatestFiniteMagnitude
        let constraints = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRangeMake(0, 0), nil, constraints, nil
        )
        // Add small padding to avoid clipping from height underestimation
        return CGSize(width: ceil(size.width), height: ceil(size.height) + 8)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let oldWidth = preferredMaxLayoutWidth
        preferredMaxLayoutWidth = bounds.width
        if oldWidth != preferredMaxLayoutWidth {
            invalidateIntrinsicContentSize()
        }
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let ctFrame = ctFrame else { return }

        let tapLocation = gesture.location(in: self)

        // Convert from UIKit coordinates (top-left origin) to CoreText (bottom-left origin)
        let ctPoint = CGPoint(x: tapLocation.x, y: bounds.height - tapLocation.y)

        let lines = CTFrameGetLines(ctFrame) as! [CTLine]
        guard !lines.isEmpty else { return }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), &origins)

        // Find which line was tapped
        for (lineIndex, line) in lines.enumerated() {
            let origin = origins[lineIndex]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            // Line bounds in CoreText coordinates
            let lineTop = origin.y + ascent
            let lineBottom = origin.y - descent
            let lineLeft = origin.x
            let lineRight = origin.x + width

            if ctPoint.x >= lineLeft && ctPoint.x <= lineRight &&
               ctPoint.y >= lineBottom && ctPoint.y <= lineTop {
                // Found the line, now find the character index
                let relativePoint = CGPoint(x: ctPoint.x - origin.x, y: ctPoint.y - origin.y)
                let charIndex = CTLineGetStringIndexForPosition(line, relativePoint)

                if charIndex != kCFNotFound {
                    // Find matching token
                    for tokenRange in tokenRanges {
                        if charIndex >= tokenRange.start && charIndex < tokenRange.start + tokenRange.length {
                            onTokenTapped?(tokenRange.tokenIndex)
                            return
                        }
                    }
                }
                return
            }
        }
    }

    // MARK: - Build Attributed String with Ruby Annotations and Range Mapping

    nonisolated static func buildAnnotatedResult(
        from tokens: [FuriganaToken],
        fontSize: CGFloat = 22,
        lineHeightMultiple: CGFloat = 1.8,
        textColor: UIColor = .label
    ) -> AnnotatedResult {
        let result = NSMutableAttributedString()
        var ranges: [TokenRange] = []

        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor
        ]

        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)

        for (index, token) in tokens.enumerated() {
            let start = result.length

            if let reading = token.reading {
                // Split compound kanji tokens into per-character ruby annotations
                let charReadings = Self.splitReadingPerCharacter(surface: token.surface, fullReading: reading)

                for (char, charReading) in charReadings {
                    var attributes = baseAttributes
                    if let charReading {
                        let annotation = CTRubyAnnotationCreateWithAttributes(
                            .auto,
                            .auto,
                            .before,
                            charReading as CFString,
                            [
                                kCTRubyAnnotationSizeFactorAttributeName: 0.5
                            ] as CFDictionary
                        )
                        attributes[rubyKey] = annotation
                    }
                    let attributed = NSAttributedString(string: String(char), attributes: attributes)
                    result.append(attributed)
                }
            } else {
                let attributed = NSAttributedString(string: token.surface, attributes: baseAttributes)
                result.append(attributed)
            }

            ranges.append(TokenRange(
                start: start,
                length: (token.surface as NSString).length,
                tokenIndex: index
            ))
        }

        return AnnotatedResult(attributedString: result, tokenRanges: ranges)
    }

    // MARK: - Per-character reading decomposition

    /// Split a compound token's reading into per-character readings.
    /// For example: surface="名前" reading="なまえ" → [("名","な"), ("前","まえ")]
    /// For mixed kanji/kana surfaces like "食べる" reading="たべる" → [("食","た"), ("べ",""), ("る","")]
    /// Falls back to putting the entire reading on the first kanji if decomposition fails.
    nonisolated private static func splitReadingPerCharacter(
        surface: String,
        fullReading: String
    ) -> [(Character, String?)] {
        let surfaceChars = Array(surface)

        // If single character, no splitting needed
        if surfaceChars.count <= 1 {
            return surfaceChars.map { ($0, fullReading) }
        }

        // Identify kanji vs non-kanji runs in the surface
        // e.g. "食べ物" → [kanji("食"), kana("べ"), kanji("物")]
        struct SurfaceSegment {
            let text: String
            let isKanji: Bool
            let charIndices: Range<Int>  // indices into surfaceChars
        }

        var segments: [SurfaceSegment] = []
        var segStart = 0
        while segStart < surfaceChars.count {
            let isKanji = Self.charIsKanji(surfaceChars[segStart])
            var segEnd = segStart + 1
            while segEnd < surfaceChars.count && Self.charIsKanji(surfaceChars[segEnd]) == isKanji {
                segEnd += 1
            }
            let segText = String(surfaceChars[segStart..<segEnd])
            segments.append(SurfaceSegment(text: segText, isKanji: isKanji, charIndices: segStart..<segEnd))
            segStart = segEnd
        }

        // If there's only one segment and it's all kanji, try per-character tokenizer lookup
        if segments.count == 1 && segments[0].isKanji {
            return splitAllKanjiReading(surfaceChars: surfaceChars, fullReading: fullReading)
        }

        // For mixed surfaces (e.g. "食べる" → reading "たべる"):
        // Anchor kana segments in the reading, then assign remaining reading to kanji segments
        var charReadings: [(Character, String?)] = surfaceChars.map { ($0, nil as String?) }
        let readingChars = Array(fullReading)

        // Match kana segments to the reading to find kanji reading boundaries
        // Use dynamic programming / greedy matching approach
        var readingOffset = 0
        var assignmentSuccess = true

        for segment in segments {
            if !segment.isKanji {
                // This kana segment should appear in the reading at the current offset
                let kanaText = Array(segment.text)
                // Try to find this kana sequence at or after readingOffset
                let kataVersion = Self.hiraganaToKatakana(segment.text)
                let hiraVersion = segment.text

                var found = false
                // Check if reading at current offset matches (hiragana or katakana)
                if readingOffset + kanaText.count <= readingChars.count {
                    let readingSlice = String(readingChars[readingOffset..<readingOffset + kanaText.count])
                    let readingSliceHira = Self.katakanaToHiragana(readingSlice)
                    if readingSliceHira == hiraVersion || readingSlice == kataVersion || readingSlice == hiraVersion {
                        // Kana matches — no ruby needed for these characters
                        for i in segment.charIndices {
                            charReadings[i] = (surfaceChars[i], nil)
                        }
                        readingOffset += kanaText.count
                        found = true
                    }
                }
                if !found {
                    assignmentSuccess = false
                    break
                }
            } else {
                // Kanji segment — find where the next kana segment starts in the reading
                // to determine how much reading belongs to this kanji segment
                let nextKanaSegment = segments.first(where: {
                    $0.charIndices.lowerBound > segment.charIndices.lowerBound && !$0.isKanji
                })

                var kanjiReadingEnd = readingChars.count
                if let nextKana = nextKanaSegment {
                    // Find where the next kana appears in the remaining reading
                    let nextKanaText = nextKana.text
                    let nextKanaHira = Self.katakanaToHiragana(nextKanaText)
                    // Search for the kana anchor in the reading
                    for searchPos in readingOffset...(readingChars.count - Array(nextKanaText).count) {
                        let slice = String(readingChars[searchPos..<searchPos + Array(nextKanaText).count])
                        let sliceHira = Self.katakanaToHiragana(slice)
                        if sliceHira == nextKanaHira {
                            kanjiReadingEnd = searchPos
                            break
                        }
                    }
                }

                let kanjiReading = String(readingChars[readingOffset..<kanjiReadingEnd])
                let kanjiChars = Array(segment.text)

                if kanjiChars.count == 1 {
                    charReadings[segment.charIndices.lowerBound] = (kanjiChars[0], kanjiReading)
                } else {
                    // Multiple kanji in a row — try per-character tokenizer decomposition
                    let subResults = splitAllKanjiReading(surfaceChars: kanjiChars, fullReading: kanjiReading)
                    for (i, (char, reading)) in subResults.enumerated() {
                        charReadings[segment.charIndices.lowerBound + i] = (char, reading)
                    }
                }
                readingOffset = kanjiReadingEnd
            }
        }

        if !assignmentSuccess {
            // Fallback: distribute reading evenly across kanji characters
            return Self.distributeReadingEvenly(surfaceChars: surfaceChars, fullReading: fullReading)
        }

        return charReadings
    }

    /// Split reading for an all-kanji surface (e.g. "名前" → "なまえ")
    /// Uses CFStringTokenizer to get per-character readings, then verifies
    /// they concatenate to the full compound reading.
    /// If decomposition fails, keeps the reading as a single annotation on
    /// the first character to avoid incorrect splits.
    nonisolated private static func splitAllKanjiReading(
        surfaceChars: [Character],
        fullReading: String
    ) -> [(Character, String?)] {
        // Try getting individual readings via the tokenizer
        var perCharReadings: [String] = []
        for char in surfaceChars {
            let charStr = String(char)
            let cfStr = charStr as CFString
            let locale = Locale(identifier: "ja") as CFLocale
            let tok = CFStringTokenizerCreate(
                kCFAllocatorDefault, cfStr,
                CFRangeMake(0, (charStr as NSString).length),
                kCFStringTokenizerUnitWordBoundary, locale
            )
            let tokType = CFStringTokenizerGoToTokenAtIndex(tok, 0)
            if tokType.rawValue != 0,
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                   tok, kCFStringTokenizerAttributeLatinTranscription
               ) as? String {
                let mutable = NSMutableString(string: latin)
                CFStringTransform(mutable, nil, "Latin-Hiragana" as CFString, false)
                perCharReadings.append(mutable as String)
            } else {
                perCharReadings.append("")
            }
        }

        // Verify: concatenated per-char readings should match fullReading
        let concatenated = perCharReadings.joined()
        if concatenated == fullReading {
            return zip(surfaceChars, perCharReadings).map { ($0, $1.isEmpty ? nil : $1) }
        }

        // Try backtracking search: find a valid way to split fullReading
        // so that each portion is a known reading for that kanji character.
        // Build a set of known readings per character by trying the tokenizer
        // with different common suffixes (to elicit on/kun readings).
        var knownReadings: [[String]] = []
        for char in surfaceChars {
            var readings = Set<String>()
            let charStr = String(char)
            // The reading we already got
            if let idx = surfaceChars.firstIndex(of: char),
               idx < perCharReadings.count,
               !perCharReadings[Int(surfaceChars.distance(from: surfaceChars.startIndex, to: idx))].isEmpty {
                readings.insert(perCharReadings[Int(surfaceChars.distance(from: surfaceChars.startIndex, to: idx))])
            }
            // Try tokenizing with common particles to elicit different readings
            let probes = [charStr, charStr + "の", charStr + "に", charStr + "を"]
            for probe in probes {
                let cfProbe = probe as CFString
                let locale = Locale(identifier: "ja") as CFLocale
                let tok = CFStringTokenizerCreate(
                    kCFAllocatorDefault, cfProbe,
                    CFRangeMake(0, (probe as NSString).length),
                    kCFStringTokenizerUnitWordBoundary, locale
                )
                let tokType = CFStringTokenizerGoToTokenAtIndex(tok, 0)
                if tokType.rawValue != 0 {
                    let range = CFStringTokenizerGetCurrentTokenRange(tok)
                    if range.location == 0 && range.length == (charStr as NSString).length,
                       let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                           tok, kCFStringTokenizerAttributeLatinTranscription
                       ) as? String {
                        let mutable = NSMutableString(string: latin)
                        CFStringTransform(mutable, nil, "Latin-Hiragana" as CFString, false)
                        readings.insert(mutable as String)
                    }
                }
            }
            knownReadings.append(Array(readings))
        }

        // Backtracking: try to split fullReading among characters
        let readingChars = Array(fullReading)
        var bestSplit: [String]?

        func backtrack(charIdx: Int, readingOffset: Int, current: [String]) {
            if bestSplit != nil { return } // Already found a solution
            if charIdx == surfaceChars.count {
                if readingOffset == readingChars.count {
                    bestSplit = current
                }
                return
            }
            let remaining = surfaceChars.count - charIdx
            let remainingReading = readingChars.count - readingOffset
            // Each remaining char needs at least 1 reading char
            let maxLen = remainingReading - (remaining - 1)
            guard maxLen >= 1 else { return }

            for len in 1...maxLen {
                let candidate = String(readingChars[readingOffset..<readingOffset + len])
                // Check if this is a known reading for this character
                if knownReadings[charIdx].contains(candidate) {
                    backtrack(charIdx: charIdx + 1, readingOffset: readingOffset + len,
                              current: current + [candidate])
                    if bestSplit != nil { return }
                }
            }
        }

        backtrack(charIdx: 0, readingOffset: 0, current: [])

        if let split = bestSplit {
            return zip(surfaceChars, split).map { ($0, $1) }
        }

        // Final fallback: distribute reading evenly across all characters
        // This produces a visually reasonable result even if not perfectly accurate
        return Self.distributeReadingEvenly(surfaceChars: surfaceChars, fullReading: fullReading)
    }

    /// Distribute a reading evenly across kanji characters.
    /// e.g. "とうきょう" across ["東","京"] → ["とう","きょう"] (roughly 5/2 = 2-3 split)
    nonisolated private static func distributeReadingEvenly(
        surfaceChars: [Character],
        fullReading: String
    ) -> [(Character, String?)] {
        let readingChars = Array(fullReading)
        let count = surfaceChars.count
        guard count > 0 else { return [] }
        if count == 1 {
            return [(surfaceChars[0], fullReading)]
        }

        let totalReading = readingChars.count
        var results: [(Character, String?)] = []
        var offset = 0

        for i in 0..<count {
            if i == count - 1 {
                // Last character gets everything remaining
                let portion = String(readingChars[offset...])
                results.append((surfaceChars[i], portion.isEmpty ? nil : portion))
            } else {
                // Distribute proportionally
                let portionSize = Int(round(Double(totalReading) / Double(count)))
                let remaining = totalReading - offset
                let charsLeft = count - i
                // Ensure at least 1 char for remaining characters
                let thisSize = min(max(portionSize, 1), remaining - (charsLeft - 1))
                let portion = String(readingChars[offset..<offset + thisSize])
                results.append((surfaceChars[i], portion))
                offset += thisSize
            }
        }
        return results
    }

    // MARK: - Character classification helpers

    nonisolated private static func charIsKanji(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) ||
               (0x3400...0x4DBF).contains(v) ||
               (0x20000...0x2A6DF).contains(v) ||
               (0xF900...0xFAFF).contains(v)
    }

    nonisolated private static func katakanaToHiragana(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Katakana-Hiragana" as CFString, false)
        return mutable as String
    }

    nonisolated private static func hiraganaToKatakana(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hiragana-Katakana" as CFString, false)
        return mutable as String
    }

    /// Legacy method for backward compatibility
    static func buildAttributedString(from tokens: [FuriganaToken], fontSize: CGFloat = 22) -> NSAttributedString {
        buildAnnotatedResult(from: tokens, fontSize: fontSize).attributedString
    }
}

// MARK: - SwiftUI Wrapper

struct FuriganaDisplayView: UIViewRepresentable {
    let attributedText: NSAttributedString?
    var tokenRanges: [TokenRange] = []
    var onTokenTapped: ((Int) -> Void)?

    func makeUIView(context: Context) -> RubyTextView {
        let view = RubyTextView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: RubyTextView, context: Context) {
        uiView.attributedText = attributedText
        uiView.tokenRanges = tokenRanges
        uiView.onTokenTapped = onTokenTapped
    }
}

// MARK: - Pagination

extension RubyTextView {

    /// Calculate page ranges for paginated display.
    /// Each CFRange represents the character range that fits in one page.
    nonisolated static func calculatePageRanges(
        for attributedString: NSAttributedString,
        pageSize: CGSize
    ) -> [CFRange] {
        guard attributedString.length > 0, pageSize.width > 0, pageSize.height > 0 else {
            return []
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        var ranges: [CFRange] = []
        var currentIndex = 0
        let totalLength = attributedString.length

        while currentIndex < totalLength {
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: pageSize))
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(currentIndex, 0),
                path,
                nil
            )
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else { break }
            ranges.append(CFRangeMake(currentIndex, visibleRange.length))
            currentIndex += visibleRange.length
        }

        return ranges
    }

    /// Slice the full attributed string into per-page PageData for fast rendering.
    nonisolated static func slicePages(
        from annotated: AnnotatedResult,
        pageSize: CGSize
    ) -> [PageData] {
        let fullAttr = annotated.attributedString
        guard fullAttr.length > 0, pageSize.width > 0, pageSize.height > 0 else {
            return []
        }

        let ranges = calculatePageRanges(for: fullAttr, pageSize: pageSize)
        let allTokenRanges = annotated.tokenRanges

        return ranges.map { cfRange in
            let loc = cfRange.location
            let len = cfRange.length
            let nsRange = NSRange(location: loc, length: len)
            let pageAttr = fullAttr.attributedSubstring(from: nsRange)

            // Remap token ranges to be relative to this page's substring
            let pageTokenRanges = allTokenRanges.compactMap { tr -> TokenRange? in
                let trEnd = tr.start + tr.length
                let pageEnd = loc + len
                // Token overlaps with this page
                guard trEnd > loc && tr.start < pageEnd else { return nil }
                let clippedStart = max(tr.start, loc)
                let clippedEnd = min(trEnd, pageEnd)
                let clippedLen = clippedEnd - clippedStart
                guard clippedLen > 0 else { return nil }
                return TokenRange(
                    start: clippedStart - loc,
                    length: clippedLen,
                    tokenIndex: tr.tokenIndex
                )
            }

            return PageData(attributedString: pageAttr, tokenRanges: pageTokenRanges)
        }
    }
}

// MARK: - Paged Ruby View (single page rendering)

/// Renders a specific character range of an attributed string using CoreText.
/// Used for paginated reading where each page shows a portion of the text.
class PagedRubyTextView: UIView {

    var pageData: PageData?
    var onTokenTapped: ((Int) -> Void)?

    private var ctFrame: CTFrame?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let pageData,
              let context = UIGraphicsGetCurrentContext() else { return }

        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let framesetter = CTFramesetterCreateWithAttributedString(pageData.attributedString as CFAttributedString)
        let path = CGMutablePath()
        path.addRect(bounds)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        self.ctFrame = frame
        CTFrameDraw(frame, context)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let ctFrame else { return }

        let tapLocation = gesture.location(in: self)
        let ctPoint = CGPoint(x: tapLocation.x, y: bounds.height - tapLocation.y)

        let lines = CTFrameGetLines(ctFrame) as! [CTLine]
        guard !lines.isEmpty else { return }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), &origins)

        for (lineIndex, line) in lines.enumerated() {
            let origin = origins[lineIndex]
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            let lineTop = origin.y + ascent
            let lineBottom = origin.y - descent

            if ctPoint.x >= origin.x && ctPoint.x <= origin.x + width &&
               ctPoint.y >= lineBottom && ctPoint.y <= lineTop {
                let relativePoint = CGPoint(x: ctPoint.x - origin.x, y: ctPoint.y - origin.y)
                let charIndex = CTLineGetStringIndexForPosition(line, relativePoint)

                if charIndex != kCFNotFound, let pageData {
                    for tokenRange in pageData.tokenRanges {
                        if charIndex >= tokenRange.start && charIndex < tokenRange.start + tokenRange.length {
                            onTokenTapped?(tokenRange.tokenIndex)
                            return
                        }
                    }
                }
                return
            }
        }
    }
}

// MARK: - Paged Furigana SwiftUI Wrapper

struct PagedFuriganaView: UIViewRepresentable {
    let pageData: PageData
    let backgroundColor: UIColor
    var onTokenTapped: ((Int) -> Void)?

    func makeUIView(context: Context) -> PagedRubyTextView {
        let view = PagedRubyTextView()
        view.isOpaque = true
        return view
    }

    func updateUIView(_ uiView: PagedRubyTextView, context: Context) {
        uiView.backgroundColor = backgroundColor
        uiView.pageData = pageData
        uiView.onTokenTapped = onTokenTapped
        uiView.setNeedsDisplay()
    }
}
