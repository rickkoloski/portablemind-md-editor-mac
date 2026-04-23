import AppKit

/// Line-number gutter drawn as an `NSRulerView` attached to the
/// editor's scroll view. TextKit 2: line-fragment geometry comes from
/// `NSTextLayoutManager.enumerateTextLayoutFragments` — no
/// `.layoutManager` access anywhere (engineering-standards §2.2).
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
              let tlm = textView.textLayoutManager,
              let tcm = tlm.textContentManager
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

        tlm.enumerateTextLayoutFragments(
            from: tlm.documentRange.location,
            options: [.ensuresLayout]
        ) { [weak self] fragment in
            guard let self else { return false }

            // Fragment frame is in text-container coordinates. Offset
            // by container origin to get text-view coordinates, then
            // convert to ruler-view coordinates.
            let frameInTextView = fragment.layoutFragmentFrame
                .offsetBy(dx: textContainerOrigin.x,
                          dy: textContainerOrigin.y)
            let frameInRuler = self.convert(frameInTextView, from: textView)

            // Dirty-rect culling.
            if frameInRuler.minY > rect.maxY { return false }
            if frameInRuler.maxY < rect.minY { return true }

            // Map fragment start to a 1-based line number.
            let elementRange = fragment.rangeInElement
            let startOffset = tcm.offset(from: tcm.documentRange.location,
                                         to: elementRange.location)
            let lineNumber = self.lineNumber(for: startOffset)

            let str = "\(lineNumber)" as NSString
            let strSize = str.size(withAttributes: attrs)
            let x = self.ruleThickness - strSize.width - self.rightPadding
            let y = frameInRuler.minY
                + (frameInRuler.height - strSize.height) / 2
            str.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            return true
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
