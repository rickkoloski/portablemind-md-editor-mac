// D12 Cell Caret Spike v2 — full round-trip reproducer.
//
// Goal: prove click, caret, and typed-edit align in a single visually
// rendered cell grid, driven by:
//   1. Custom NSTextLayoutFragment that draws a two-cell grid.
//   2. NSTextLayoutManagerDelegate returning that fragment.
//   3. Custom NSTextSelectionDataSource routing click and caret offsets
//      to cell geometry.
//
// Behavior target (what Rick should see):
//   - Two visually rendered cell boxes with their current content.
//   - Source pipes (`|`) not visible as characters; they're structural.
//   - Click inside cell 1 → caret appears inside cell 1 at the clicked x.
//   - Type a letter → letter appears inside cell 1, caret advances by one
//     cell-char-width inside cell 1.
//   - Click inside cell 2 → caret appears inside cell 2, not cell 1.
//
// If Rick sees a coherent experience (click → caret → edit all matched
// visually), spike is GREEN for the full design, not just caret-x.

import AppKit
import Foundation

// MARK: - Spike constants

let initialSourceText = "| cell one | cell two |\n"

// Fragment geometry. Independent of the source-text's natural CT layout.
// Cells are flush with the fragment's top edge (y=0) so the line fragment
// (where NSTextView draws the caret) sits inside the cell vertically.
let fragmentHeight: CGFloat = 40
let cell1X: CGFloat = 20
let cell2X: CGFloat = 360
let cellWidth: CGFloat = 320
let cellContentFontSize: CGFloat = 18

/// Tunable knobs exposed as live inputs in the window toolbar so CD
/// can dial in visual alignment in real time. Edits to these values
/// trigger a full layout invalidation + redraw.
enum TuningKnobs {
    /// Vertical offset applied to cell rects (and their content),
    /// in fragment-local coords. Shifts cells up (negative) or down
    /// (positive). Use to align the cell box with the caret's Y.
    /// Default -7.5 dialed in by CD 2026-04-24 against Menlo 18pt.
    static var cellYOffset: CGFloat = -7.5
    /// Horizontal inset of the CARET only inside each cell (measured
    /// from the cell's left edge). The cell content text is drawn at
    /// a fixed 8pt inset independently. Use this to dial the caret's
    /// column alignment with the text without moving the text.
    /// Default 13 dialed in by CD 2026-04-24 against Menlo 18pt.
    static var caretXOffset: CGFloat = 13
}

/// Fixed horizontal inset for cell content text drawing. Decoupled from
/// the caret X knob so CD can tune caret alignment independently.
let cellContentXInset: CGFloat = 8
/// Exact char width of the cell-content font, measured once.
let perCharStride: CGFloat = {
    let font = NSFont.monospacedSystemFont(ofSize: cellContentFontSize, weight: .regular)
    return ("M" as NSString).size(withAttributes: [.font: font]).width
}()

// Cell visual rects (in fragment-local coordinates, flipped y).
var cell1Rect: CGRect {
    CGRect(x: cell1X, y: 0, width: cellWidth, height: fragmentHeight)
}
var cell2Rect: CGRect {
    CGRect(x: cell2X, y: 0, width: cellWidth, height: fragmentHeight)
}

// MARK: - Cell-range parser

/// Splits a row's source text into cell content ranges (source NSRanges).
/// Ignores leading/trailing pipes and surrounding whitespace. GFM-style
/// pipe-escape (`\|`) not handled in the spike.
func parseCellRanges(in source: String) -> [NSRange] {
    let ns = source as NSString
    let length = ns.length
    var ranges: [NSRange] = []
    let PIPE: unichar = 0x7c
    let SPACE: unichar = 0x20
    let NEWLINE: unichar = 0x0a

    var i = 0
    // Skip leading pipe + whitespace
    while i < length,
          ns.character(at: i) == PIPE || ns.character(at: i) == SPACE {
        i += 1
    }

    while i < length {
        // Stop at newline — we only parse one line.
        if ns.character(at: i) == NEWLINE { break }

        let contentStart = i
        // Read content until pipe or newline.
        while i < length,
              ns.character(at: i) != PIPE,
              ns.character(at: i) != NEWLINE {
            i += 1
        }
        // Trim trailing whitespace from [contentStart, i).
        var contentEnd = i
        while contentEnd > contentStart,
              ns.character(at: contentEnd - 1) == SPACE {
            contentEnd -= 1
        }
        if contentEnd > contentStart {
            ranges.append(NSRange(location: contentStart,
                                  length: contentEnd - contentStart))
        }
        // Advance past the pipe (if any) + following whitespace.
        // Guard: if we can't make progress, break to avoid infinite loop.
        let advanceStart = i
        while i < length,
              ns.character(at: i) == PIPE || ns.character(at: i) == SPACE {
            i += 1
        }
        if i == advanceStart { break }  // couldn't advance — bail out
    }
    return ranges
}

// MARK: - Custom layout fragment

final class CellGridFragment: NSTextLayoutFragment {
    override var layoutFragmentFrame: CGRect {
        let base = super.layoutFragmentFrame
        return CGRect(x: base.origin.x, y: base.origin.y,
                      width: 800, height: fragmentHeight)
    }

    override var renderingSurfaceBounds: CGRect {
        // Extend vertically (both above and below the layoutFragmentFrame)
        // so that cellYOffset tuning can shift cell drawing outside the
        // natural bounds without getting clipped. The TextKit 2 header
        // explicitly allows a negative-Y origin here.
        let extra: CGFloat = 80
        return CGRect(x: 0, y: -extra,
                      width: layoutFragmentFrame.width,
                      height: layoutFragmentFrame.height + 2 * extra)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        logLine("FRAG", "draw at (\(point.x), \(point.y)) layoutFragmentFrame=\(NSStringFromRect(layoutFragmentFrame)) renderingSurfaceBounds=\(NSStringFromRect(renderingSurfaceBounds)) lineFragments=\(textLineFragments.count)")
        for (i, lf) in textLineFragments.enumerated() {
            logLine("FRAG", "  line[\(i)] typoBounds=\(NSStringFromRect(lf.typographicBounds)) glyphOrigin=(\(lf.glyphOrigin.x), \(lf.glyphOrigin.y))")
        }

        // Source for this row.
        guard let paragraph = textElement as? NSTextParagraph else {
            logLine("FRAG", "  element is not NSTextParagraph")
            return
        }
        let source = paragraph.attributedString.string
        let cellRanges = parseCellRanges(in: source)

        // Draw cell boxes.
        context.saveGState()
        defer { context.restoreGState() }

        let dy = point.y + TuningKnobs.cellYOffset
        let rect1 = cell1Rect.offsetBy(dx: point.x, dy: dy)
        let rect2 = cell2Rect.offsetBy(dx: point.x, dy: dy)

        // Yellow fill so it's OBVIOUS this fragment is drawing.
        context.setFillColor(NSColor.yellow.cgColor)
        context.fill(rect1.insetBy(dx: 0.75, dy: 0.75))
        context.fill(rect2.insetBy(dx: 0.75, dy: 0.75))

        context.setStrokeColor(NSColor.red.cgColor)
        context.setLineWidth(2.0)
        context.stroke(rect1)
        context.stroke(rect2)

        // Draw cell content text.
        let font = NSFont.monospacedSystemFont(ofSize: cellContentFontSize,
                                               weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = gc

        let ns = source as NSString
        // Text draws at a fixed inset; caret X tuning is independent.
        if cellRanges.count >= 1 {
            let txt = ns.substring(with: cellRanges[0])
            (txt as NSString).draw(
                at: CGPoint(x: rect1.origin.x + cellContentXInset,
                            y: rect1.origin.y + 4),
                withAttributes: attrs)
        }
        if cellRanges.count >= 2 {
            let txt = ns.substring(with: cellRanges[1])
            (txt as NSString).draw(
                at: CGPoint(x: rect2.origin.x + cellContentXInset,
                            y: rect2.origin.y + 4),
                withAttributes: attrs)
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Layout manager delegate

final class GridDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        logLine("DELEGATE", "textLayoutFragmentFor element=\(type(of: textElement))")
        if textElement is NSTextParagraph {
            logLine("DELEGATE", "  → returning CellGridFragment")
            return CellGridFragment(textElement: textElement,
                                    range: textElement.elementRange)
        }
        return NSTextLayoutFragment(textElement: textElement,
                                    range: textElement.elementRange)
    }
}

// MARK: - Custom selection data source

final class CellDataSource: NSObject, NSTextSelectionDataSource {
    weak var textStorage: NSTextContentStorage?
    let tlm: NSTextLayoutManager

    init(tlm: NSTextLayoutManager, storage: NSTextContentStorage) {
        self.tlm = tlm
        self.textStorage = storage
    }

    // Pass-throughs.
    var documentRange: NSTextRange { tlm.documentRange }
    func enumerateSubstrings(from l: any NSTextLocation,
                             options: NSString.EnumerationOptions = [],
                             using block: (String?, NSTextRange, NSTextRange?,
                                           UnsafeMutablePointer<ObjCBool>) -> Void) {
        tlm.enumerateSubstrings(from: l, options: options, using: block)
    }
    func textRange(for g: NSTextSelection.Granularity,
                   enclosing l: any NSTextLocation) -> NSTextRange? {
        tlm.textRange(for: g, enclosing: l)
    }
    func location(_ l: any NSTextLocation, offsetBy o: Int) -> (any NSTextLocation)? {
        tlm.location(l, offsetBy: o)
    }
    func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
        tlm.offset(from: from, to: to)
    }
    func baseWritingDirection(at l: any NSTextLocation)
        -> NSTextSelectionNavigation.WritingDirection {
        tlm.baseWritingDirection(at: l)
    }
    func textLayoutOrientation(at l: any NSTextLocation)
        -> NSTextSelectionNavigation.LayoutOrientation {
        tlm.textLayoutOrientation(at: l)
    }
    func enumerateContainerBoundaries(
        from l: any NSTextLocation, reverse: Bool,
        using block: (any NSTextLocation, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        tlm.enumerateContainerBoundaries(from: l, reverse: reverse, using: block)
    }

    // MARK: - Overridden behavior

    private func currentSource() -> String {
        textStorage?.attributedString?.string ?? ""
    }

    /// Compute the caret X for a source offset. Non-cell offsets collapse
    /// to the boundary of the nearest cell (pipes and inter-cell whitespace
    /// produce caret positions at cell edges).
    private func caretX(forSourceOffset i: Int, in source: String) -> CGFloat {
        let ranges = parseCellRanges(in: source)
        guard ranges.count >= 2 else {
            return CGFloat(i) * perCharStride
        }
        let c1 = ranges[0]
        let c2 = ranges[1]
        let pad = TuningKnobs.caretXOffset

        if i < c1.location {
            return cell1X + pad
        }
        if i <= c1.location + c1.length {
            let local = i - c1.location
            return cell1X + pad + CGFloat(local) * perCharStride
        }
        if i < c2.location {
            return cell1X + cellWidth - pad
        }
        if i <= c2.location + c2.length {
            let local = i - c2.location
            return cell2X + pad + CGFloat(local) * perCharStride
        }
        return cell2X + cellWidth - pad
    }

    func enumerateCaretOffsetsInLineFragment(
        at location: any NSTextLocation,
        using block: (CGFloat, any NSTextLocation, Bool,
                      UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let source = currentSource()
        let total = (source as NSString).length

        let ranges = parseCellRanges(in: source)
        logLine("CELL-DS", "enumerate (total=\(total), cells=\(ranges.count))")

        // Guard: if we don't have two cells, fall back to the TLM default.
        // This avoids trapping on invalid Swift ranges and keeps the spike
        // defensive during transient states.
        guard ranges.count >= 2 else {
            tlm.enumerateCaretOffsetsInLineFragment(at: location, using: block)
            return
        }

        let docStart = tlm.documentRange.location
        var stop = ObjCBool(false)

        func emit(_ i: Int) {
            guard let loc = tlm.location(docStart, offsetBy: i) else { return }
            let x = caretX(forSourceOffset: i, in: source)
            block(x, loc, true, &stop)
        }

        // Emit source offsets 0..<total in strict LTR visual order. We use
        // `caretX` as the single source of truth for x-position per offset;
        // the emit order just has to be monotonic in caretX. Since c1
        // precedes c2 in both source order and x-order, iterating 0..<total
        // produces the right thing as long as our caretX mapping is
        // monotonic for the 0..<total sequence.
        for i in 0..<total {
            emit(i)
            if stop.boolValue { return }
        }
    }

    func lineFragmentRange(
        for point: CGPoint,
        inContainerAt location: any NSTextLocation
    ) -> NSTextRange? {
        let source = currentSource()
        let ranges = parseCellRanges(in: source)
        guard ranges.count >= 2 else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        let c1 = ranges[0]
        let c2 = ranges[1]

        let docStart = tlm.documentRange.location

        // Tier 1c fix: ANY click in the row's horizontal space snaps to a
        // cell range by x-position. No fallback to natural CT layout.
        //   x < midpoint between cells → cell 1
        //   x ≥ midpoint between cells → cell 2
        let midX = (cell1Rect.maxX + cell2Rect.minX) / 2
        let targetRange: NSRange = (point.x < midX) ? c1 : c2
        logLine("CELL-DS", "lfr for (\(point.x), \(point.y)) midX=\(midX) → \(NSEqualRanges(targetRange, c1) ? "cell 1" : "cell 2")")

        // Extend by +1 so the caret can land AT the content-end position
        // (one past the last character). Without this, clicks to the right
        // of the last char snap back to "before the last char".
        guard let start = tlm.location(docStart, offsetBy: targetRange.location),
              let end = tlm.location(start, offsetBy: targetRange.length + 1)
        else { return tlm.lineFragmentRange(for: point, inContainerAt: location) }

        return NSTextRange(location: start, end: end)
    }
}

// MARK: - In-window log panel

/// Singleton that collects log lines. Renders into an NSTextView
/// mounted in the bottom pane of the spike window, and also mirrors
/// to NSLog / stderr for the /tmp/d12-spike.log file.
final class InWindowLog {
    static let shared = InWindowLog()
    weak var textView: NSTextView?
    private let maxChars = 50_000

    func log(_ tag: String, _ msg: String) {
        let timestamp = Self.fmt.string(from: Date())
        let line = "\(timestamp) [\(tag)] \(msg)\n"
        NSLog("[\(tag)] %@", msg)
        DispatchQueue.main.async { [weak self] in
            guard let self, let tv = self.textView, let storage = tv.textStorage else { return }
            storage.append(NSAttributedString(string: line, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.black
            ]))
            if storage.length > self.maxChars {
                storage.deleteCharacters(in: NSRange(
                    location: 0, length: storage.length - self.maxChars))
            }
            tv.scrollToEndOfDocument(nil)
        }
    }

    func allText() -> String {
        textView?.textStorage?.string ?? ""
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// Short alias
func logLine(_ tag: String, _ msg: String) {
    InWindowLog.shared.log(tag, msg)
}

/// NSTextView subclass that logs where the caret is drawn and
/// protects cell boundaries against destructive operations.
final class LoggingTextView: NSTextView {
    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func drawInsertionPoint(in rect: NSRect,
                                     color: NSColor,
                                     turnedOn flag: Bool) {
        logLine("CARET", "drawInsertionPoint rect=\(NSStringFromRect(rect)) on=\(flag) flipped=\(self.isFlipped)")
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    /// Tier 2.5 — backspace at a cell-start moves caret to the previous
    /// cell's end instead of deleting the pipe. Caret crosses the
    /// boundary non-destructively. Matches Word/Docs table cell behavior.
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, let storage = textStorage {
            let source = storage.string
            let ranges = parseCellRanges(in: source)
            // Caret at start of cell 2 → jump to end of cell 1.
            if ranges.count >= 2, sel.location == ranges[1].location {
                let prevEnd = ranges[0].location + ranges[0].length
                logLine("UI", "backspace at cell-2 start → jump to cell-1 end (offset \(prevEnd))")
                setSelectedRange(NSRange(location: prevEnd, length: 0))
                return
            }
            // Caret at start of cell 1 → jump to line start.
            if ranges.count >= 1, sel.location == ranges[0].location {
                logLine("UI", "backspace at cell-1 start → jump to line start (offset 0)")
                setSelectedRange(NSRange(location: 0, length: 0))
                return
            }
        }
        super.deleteBackward(sender)
    }

    /// Tier 2.4 — right arrow at cell-content-end jumps directly to next
    /// cell's content-start, skipping the inter-cell pipe source offsets.
    /// Left arrow at cell-content-start jumps to previous cell's
    /// content-end. Matches Word/Docs cell navigation.
    ///
    /// Tier 2.6 — Tab / Shift+Tab cycle between cells.
    override func keyDown(with event: NSEvent) {
        let sel = selectedRange()
        guard sel.length == 0, let storage = textStorage else {
            super.keyDown(with: event)
            return
        }
        let source = storage.string
        let ranges = parseCellRanges(in: source)
        guard ranges.count >= 2 else {
            super.keyDown(with: event)
            return
        }
        let c1 = ranges[0]
        let c2 = ranges[1]
        let c1End = c1.location + c1.length
        let c2End = c2.location + c2.length
        let loc = sel.location

        // Key codes
        let KEY_TAB: UInt16 = 48
        let KEY_LEFT: UInt16 = 123
        let KEY_RIGHT: UInt16 = 124

        switch event.keyCode {
        case KEY_TAB:
            let shift = event.modifierFlags.contains(.shift)
            let inCell1 = loc >= c1.location && loc <= c1End
            let inCell2 = loc >= c2.location && loc <= c2End
            let target: Int
            if shift {
                // Shift+Tab → previous cell's end (or this cell's start if no prev).
                if inCell2 {
                    target = c1End
                } else {
                    target = c1.location  // already in c1 → go to c1 start
                }
            } else {
                // Tab → next cell's start (or this cell's end if no next).
                if inCell1 {
                    target = c2.location
                } else {
                    target = c2End  // already in c2 → go to c2 end
                }
            }
            logLine("UI", "Tab (shift=\(shift)) loc=\(loc) → \(target)")
            setSelectedRange(NSRange(location: target, length: 0))
            return

        case KEY_RIGHT:
            // At cell-1 content-end → jump to cell-2 content-start.
            if loc == c1End {
                logLine("UI", "→ at cell-1 end → jump to cell-2 start (\(c2.location))")
                setSelectedRange(NSRange(location: c2.location, length: 0))
                return
            }
            // At cell-2 content-end → stop (don't advance into the trailing
            // pipe/newline region; Word/Docs behavior).
            if loc == c2End {
                logLine("UI", "→ at cell-2 end → ignore (boundary)")
                return
            }
            super.keyDown(with: event)
            return

        case KEY_LEFT:
            // At cell-2 content-start → jump to cell-1 content-end.
            if loc == c2.location {
                logLine("UI", "← at cell-2 start → jump to cell-1 end (\(c1End))")
                setSelectedRange(NSRange(location: c1End, length: 0))
                return
            }
            // At cell-1 content-start → stop at boundary.
            if loc == c1.location {
                logLine("UI", "← at cell-1 start → ignore (boundary)")
                return
            }
            super.keyDown(with: event)
            return

        default:
            super.keyDown(with: event)
        }
    }

    /// Symmetrically — Delete at cell-end jumps to the next cell's start.
    override func deleteForward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, let storage = textStorage {
            let source = storage.string
            let ranges = parseCellRanges(in: source)
            // Caret at end of cell 1 → jump to start of cell 2.
            if ranges.count >= 2,
               sel.location == ranges[0].location + ranges[0].length {
                logLine("UI", "delete at cell-1 end → jump to cell-2 start (offset \(ranges[1].location))")
                setSelectedRange(NSRange(location: ranges[1].location, length: 0))
                return
            }
            // Caret at end of cell 2 → jump to line end.
            if ranges.count >= 2,
               sel.location == ranges[1].location + ranges[1].length {
                let lineEnd = (source as NSString).length - 1  // before \n
                logLine("UI", "delete at cell-2 end → jump to line end (offset \(lineEnd))")
                setSelectedRange(NSRange(location: max(sel.location, lineEnd), length: 0))
                return
            }
        }
        super.deleteForward(sender)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var logTextView: NSTextView!
    var dataSource: CellDataSource!
    var gridDelegate: GridDelegate!
    var yOffsetField: NSTextField!
    var xOffsetField: NSTextField!

    @objc func copyLogsToClipboard(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(InWindowLog.shared.allText(), forType: .string)
        logLine("UI", "logs copied to clipboard (\(InWindowLog.shared.allText().count) chars)")
    }

    @objc func clearLogs(_ sender: Any?) {
        logTextView?.textStorage?.mutableString.setString("")
    }

    /// Called on Enter from the offset fields AND on every char via
    /// controlTextDidChange — lets CD dial values in real time.
    private func applyOffsets() {
        if let y = Double(yOffsetField.stringValue) {
            TuningKnobs.cellYOffset = CGFloat(y)
        }
        if let x = Double(xOffsetField.stringValue) {
            TuningKnobs.caretXOffset = CGFloat(x)
        }
        logLine("TUNE", "cellYOffset=\(TuningKnobs.cellYOffset) caretXOffset=\(TuningKnobs.caretXOffset)")

        // TextKit 2 caches the CellGridFragment's rendering. Plain
        // `invalidateLayout(for:)` marks layout dirty but doesn't drop
        // the fragment's cached draw. Same pattern D8.1 production uses:
        // signal `.editedAttributes` on the storage to force the fragment
        // cache to evict, then invalidate + force a layout pass.
        guard let tlm = textView.textLayoutManager,
              let tcm = tlm.textContentManager,
              let storage = textView.textStorage
        else { return }

        let fullNSRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.edited(.editedAttributes, range: fullNSRange, changeInLength: 0)
        storage.endEditing()
        tlm.invalidateLayout(for: tcm.documentRange)
        tlm.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
    }

    @objc func offsetFieldChanged(_ sender: Any?) { applyOffsets() }

    @objc func resetOffsets(_ sender: Any?) {
        yOffsetField.stringValue = "-7.5"
        xOffsetField.stringValue = "13"
        applyOffsets()
    }

    func controlTextDidChange(_ notification: Notification) {
        // Live update as the user types in either offset field.
        applyOffsets()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force light appearance so labels, button text, and hints stay
        // readable against the white backgrounds we use explicitly.
        NSApp.appearance = NSAppearance(named: .aqua)
        let windowSize = NSSize(width: 900, height: 600)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "D12 Cell Caret Spike v2 — round trip + log pane"
        window.backgroundColor = NSColor.white

        let content = window.contentView!

        // --- Top pane: editor (inside a scroll view)
        let editorContainerHeight: CGFloat = 220
        let editorRect = NSRect(
            x: 0,
            y: windowSize.height - editorContainerHeight,
            width: windowSize.width,
            height: editorContainerHeight)

        let editorScroll = NSScrollView(frame: editorRect)
        editorScroll.autoresizingMask = [.width, .minYMargin]
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.drawsBackground = false

        let editorContainer = NSTextContainer(size: CGSize(
            width: editorScroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude))
        editorContainer.widthTracksTextView = true
        let editorContentStorage = NSTextContentStorage()
        let editorTLM = NSTextLayoutManager()
        editorContentStorage.addTextLayoutManager(editorTLM)
        editorTLM.textContainer = editorContainer

        textView = LoggingTextView(frame: editorScroll.contentView.bounds,
                                   textContainer: editorContainer)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: editorRect.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white
        textView.textColor = NSColor.black
        textView.insertionPointColor = NSColor.systemBlue
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 10, height: 80)
        textView.delegate = self

        // Install delegate + data source BEFORE setting the string.
        if let tlm = textView.textLayoutManager {
            gridDelegate = GridDelegate()
            tlm.delegate = gridDelegate
            if let storage = textView.textContentStorage
                ?? tlm.textContentManager as? NSTextContentStorage {
                dataSource = CellDataSource(tlm: tlm, storage: storage)
                tlm.textSelectionNavigation =
                    NSTextSelectionNavigation(dataSource: dataSource)
                logLine("SPIKE", "installed grid delegate + data source")
            } else {
                logLine("SPIKE", "ERROR: could not get text content storage")
            }
        } else {
            logLine("SPIKE", "ERROR: no textLayoutManager")
        }

        textView.string = initialSourceText
        editorScroll.documentView = textView
        content.addSubview(editorScroll)

        // --- Bottom pane: toolbar + log
        let toolbarHeight: CGFloat = 28
        let toolbarRect = NSRect(
            x: 0,
            y: windowSize.height - editorContainerHeight - toolbarHeight,
            width: windowSize.width,
            height: toolbarHeight)
        let toolbar = NSView(frame: toolbarRect)
        toolbar.autoresizingMask = [.width, .minYMargin]

        let copyBtn = NSButton(frame: NSRect(x: 8, y: 2, width: 110, height: 24))
        copyBtn.title = "Copy logs"
        copyBtn.bezelStyle = .rounded
        copyBtn.target = self
        copyBtn.action = #selector(copyLogsToClipboard(_:))
        toolbar.addSubview(copyBtn)

        let clearBtn = NSButton(frame: NSRect(x: 124, y: 2, width: 70, height: 24))
        clearBtn.title = "Clear"
        clearBtn.bezelStyle = .rounded
        clearBtn.target = self
        clearBtn.action = #selector(clearLogs(_:))
        toolbar.addSubview(clearBtn)

        let yLabel = NSTextField(labelWithString: "cell Y:")
        yLabel.frame = NSRect(x: 210, y: 5, width: 50, height: 18)
        toolbar.addSubview(yLabel)

        yOffsetField = NSTextField(frame: NSRect(x: 262, y: 2, width: 60, height: 24))
        yOffsetField.stringValue = "\(TuningKnobs.cellYOffset)"
        yOffsetField.alignment = .right
        yOffsetField.target = self
        yOffsetField.action = #selector(offsetFieldChanged(_:))
        yOffsetField.delegate = self
        yOffsetField.isEditable = true
        yOffsetField.isBordered = true
        yOffsetField.isBezeled = true
        yOffsetField.drawsBackground = true
        yOffsetField.backgroundColor = .white
        yOffsetField.textColor = .black
        toolbar.addSubview(yOffsetField)

        let xLabel = NSTextField(labelWithString: "caret X:")
        xLabel.frame = NSRect(x: 334, y: 5, width: 56, height: 18)
        toolbar.addSubview(xLabel)

        xOffsetField = NSTextField(frame: NSRect(x: 392, y: 2, width: 60, height: 24))
        xOffsetField.stringValue = "\(TuningKnobs.caretXOffset)"
        xOffsetField.alignment = .right
        xOffsetField.target = self
        xOffsetField.action = #selector(offsetFieldChanged(_:))
        xOffsetField.delegate = self
        xOffsetField.isEditable = true
        xOffsetField.isBordered = true
        xOffsetField.isBezeled = true
        xOffsetField.drawsBackground = true
        xOffsetField.backgroundColor = .white
        xOffsetField.textColor = .black
        toolbar.addSubview(xOffsetField)

        logLine("SPIKE", "tuning fields created: yField frame=\(NSStringFromRect(yOffsetField.frame)) xField frame=\(NSStringFromRect(xOffsetField.frame))")
        logLine("SPIKE", "toolbar frame=\(NSStringFromRect(toolbar.frame)) subviews=\(toolbar.subviews.count)")

        let resetBtn = NSButton(frame: NSRect(x: 464, y: 2, width: 80, height: 24))
        resetBtn.title = "Reset"
        resetBtn.bezelStyle = .rounded
        resetBtn.target = self
        resetBtn.action = #selector(resetOffsets(_:))
        toolbar.addSubview(resetBtn)

        let hint = NSTextField(labelWithString: "edits redraw live")
        hint.frame = NSRect(x: 552, y: 5, width: 140, height: 18)
        hint.textColor = NSColor.secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        toolbar.addSubview(hint)

        content.addSubview(toolbar)

        // --- Log pane (bottom area)
        let logRect = NSRect(
            x: 0, y: 0,
            width: windowSize.width,
            height: windowSize.height - editorContainerHeight - toolbarHeight)
        let logScroll = NSScrollView(frame: logRect)
        logScroll.autoresizingMask = [.width, .height]
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder

        logTextView = NSTextView(frame: logScroll.contentView.bounds)
        logTextView.autoresizingMask = .width
        logTextView.minSize = NSSize(width: 0, height: logRect.height)
        logTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                     height: CGFloat.greatestFiniteMagnitude)
        logTextView.isVerticallyResizable = true
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.drawsBackground = true
        logTextView.backgroundColor = NSColor.white
        logTextView.textColor = NSColor.black
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.textContainerInset = NSSize(width: 6, height: 4)

        logScroll.documentView = logTextView
        content.addSubview(logScroll)

        InWindowLog.shared.textView = logTextView

        window.setFrameOrigin(NSPoint(x: 100, y: 100))
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.level = .floating
        window.makeFirstResponder(textView)
        logLine("SPIKE", "window frame=\(NSStringFromRect(window.frame)) visible=\(window.isVisible)")

        if let tlm = textView.textLayoutManager,
           let tcm = tlm.textContentManager {
            tlm.ensureLayout(for: tcm.documentRange)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.arrangeInFront(nil)

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            if let w = event.window, w === self.window {
                let p = self.textView.convert(event.locationInWindow, from: nil)
                logLine("EVENT", "mouseDown (text-view \(String(format: "%.1f", p.x)),\(String(format: "%.1f", p.y))) clickCount=\(event.clickCount)")
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Ignore keys routed to the log pane (they'd be Cmd+C etc. against
            // selected log text). We only care about keys to the editor.
            if let first = NSApp.keyWindow?.firstResponder,
               first === self.textView {
                logLine("EVENT", "keyDown '\(event.characters ?? "")' keyCode=\(event.keyCode)")
            }
            return event
        }

        logLine("SPIKE", "ready — click cells, observe caret + type; use 'Copy logs' to share output")
        logLine("SPIKE", "perCharStride=\(perCharStride)")
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === textView else { return }
        let sel = tv.selectedRange()
        logLine("SPIKE", "selection: location=\(sel.location) length=\(sel.length)")
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === textView else { return }
        logLine("SPIKE", "textDidChange, length=\(tv.textStorage?.length ?? -1)")
        if let tlm = tv.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
            tlm.textViewportLayoutController.layoutViewport()
            tv.needsDisplay = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
