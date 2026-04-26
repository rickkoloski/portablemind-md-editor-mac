import AppKit

/// Line-number gutter drawn as an `NSRulerView` attached to the
/// editor's scroll view.
///
/// **TextKit 1** (D17): line-fragment geometry comes from
/// `NSLayoutManager.enumerateLineFragments(forGlyphRange:using:)`. The
/// pre-D17 implementation iterated TK2's `NSTextLayoutFragment`s; that
/// API path returns nil under our current TK1 host.
///
/// Visibility is controlled externally by `EditorContainer` via
/// `NSScrollView.rulersVisible`. This view always renders when given
/// a draw pass; presence is the visibility signal.
final class LineNumberRulerView: NSRulerView {
    private let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 11,
                                                              weight: .regular)
    private let gutterTextColor = NSColor.secondaryLabelColor
    private let gutterBackground = NSColor.textBackgroundColor
    private let rightPadding: CGFloat = 6

    private var cachedLineStarts: [Int] = [0]
    private var cachedSourceHash: Int? = nil

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView,
                   orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
        // macOS 14 Sonoma changed NSView.clipsToBounds default to
        // false. Without this, the ruler's background fill extends
        // beyond its bounds and obscures the NSTextView content.
        // See Apple Dev Forums thread 767825.
        self.clipsToBounds = true
    }

    required init(coder: NSCoder) {
        fatalError("LineNumberRulerView does not support NSCoder")
    }

    func invalidate() {
        cachedSourceHash = nil
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        gutterBackground.setFill()
        rect.fill()

        let source = textView.string
        refreshLineStartsIfNeeded(for: source)

        let textContainerOrigin = textView.textContainerOrigin
        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: gutterTextColor
        ]

        // Iterate logical (source) lines, not visual (wrapped) lines.
        // For each non-empty source line, take the first character's
        // glyph and use that glyph's line-fragment rect as the y
        // anchor for the line number. Empty source lines (consecutive
        // newlines) get their number drawn at the line-fragment rect
        // of the newline glyph itself.
        let nsSource = source as NSString
        for (index, lineStart) in cachedLineStarts.enumerated() {
            // Determine the character range to look up. For the last
            // logical line (which may not end with a newline), point
            // at the first char on the line; for an empty line, the
            // newline char itself.
            let charIndex = lineStart < nsSource.length ? lineStart : max(0, nsSource.length - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            guard glyphIndex < layoutManager.numberOfGlyphs ||
                  (glyphIndex == 0 && layoutManager.numberOfGlyphs == 0) else { continue }
            let lineFragRect: NSRect
            if layoutManager.numberOfGlyphs == 0 {
                // Empty document — draw "1" at the top.
                lineFragRect = NSRect(x: 0, y: 0,
                                      width: textContainer.size.width,
                                      height: textView.font?.boundingRectForFont.height ?? 16)
            } else {
                var effective: NSRange = NSRange(location: 0, length: 0)
                lineFragRect = layoutManager.lineFragmentRect(
                    forGlyphAt: min(glyphIndex, layoutManager.numberOfGlyphs - 1),
                    effectiveRange: &effective)
            }

            let frameInTextView = lineFragRect.offsetBy(
                dx: textContainerOrigin.x,
                dy: textContainerOrigin.y)
            let frameInRuler = self.convert(frameInTextView, from: textView)

            if frameInRuler.minY > rect.maxY { break }       // past viewport
            if frameInRuler.maxY < rect.minY { continue }    // before viewport

            let lineNumber = index + 1
            let str = "\(lineNumber)" as NSString
            let strSize = str.size(withAttributes: attrs)
            let x = self.ruleThickness - strSize.width - self.rightPadding
            let y = frameInRuler.minY
                + (frameInRuler.height - strSize.height) / 2
            str.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    // MARK: - Line index

    private func refreshLineStartsIfNeeded(for source: String) {
        let hash = source.hashValue
        if cachedSourceHash == hash { return }
        var starts: [Int] = [0]
        let ns = source as NSString
        let newline = unichar(UnicodeScalar("\n").value)
        var i = 0
        let length = ns.length
        while i < length {
            if ns.character(at: i) == newline {
                starts.append(i + 1)
            }
            i += 1
        }
        cachedLineStarts = starts
        cachedSourceHash = hash
    }

    /// Largest index `i` such that `cachedLineStarts[i] <= offset`, +1.
    private func lineNumber(for offset: Int) -> Int {
        var lo = 0
        var hi = cachedLineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cachedLineStarts[mid] <= offset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo + 1
    }
}
