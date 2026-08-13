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

        for (index, token) in tokens.enumerated() {
            let start = result.length
            var attributes = baseAttributes

            if let reading = token.reading {
                let annotation = CTRubyAnnotationCreateWithAttributes(
                    .auto,
                    .auto,
                    .before,
                    reading as CFString,
                    [
                        kCTRubyAnnotationSizeFactorAttributeName: 0.5
                    ] as CFDictionary
                )
                attributes[NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)] = annotation
            }

            let attributed = NSAttributedString(string: token.surface, attributes: attributes)
            result.append(attributed)

            ranges.append(TokenRange(
                start: start,
                length: (token.surface as NSString).length,
                tokenIndex: index
            ))
        }

        return AnnotatedResult(attributedString: result, tokenRanges: ranges)
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
}

// MARK: - Paged Ruby View (single page rendering)

/// Renders a specific character range of an attributed string using CoreText.
/// Used for paginated reading where each page shows a portion of the text.
class PagedRubyTextView: UIView {

    var attributedText: NSAttributedString?
    var characterRange: CFRange = CFRangeMake(0, 0)
    var tokenRanges: [TokenRange] = []
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
        guard let attributedText,
              let context = UIGraphicsGetCurrentContext() else { return }

        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let path = CGMutablePath()
        path.addRect(bounds)
        let frame = CTFramesetterCreateFrame(framesetter, characterRange, path, nil)
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

                if charIndex != kCFNotFound {
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
}

// MARK: - Paged Furigana SwiftUI Wrapper

struct PagedFuriganaView: UIViewRepresentable {
    let attributedText: NSAttributedString?
    let characterRange: CFRange
    let backgroundColor: UIColor
    var tokenRanges: [TokenRange] = []
    var onTokenTapped: ((Int) -> Void)?

    func makeUIView(context: Context) -> PagedRubyTextView {
        let view = PagedRubyTextView()
        view.isOpaque = true
        return view
    }

    func updateUIView(_ uiView: PagedRubyTextView, context: Context) {
        uiView.backgroundColor = backgroundColor
        uiView.attributedText = attributedText
        uiView.characterRange = characterRange
        uiView.tokenRanges = tokenRanges
        uiView.onTokenTapped = onTokenTapped
        uiView.setNeedsDisplay()
    }
}
