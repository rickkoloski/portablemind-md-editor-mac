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

let initialSourceText = "| cell one | cell two |\n| c1 row 2 | c2 row 2 |\n"

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

// MARK: - Row + cell parser

/// One row in a table. `range` is the source range of the row (exclusive
/// of trailing \n). `cells` are cell-content ranges in ABSOLUTE source
/// offsets (i.e., already shifted by the row's location, not row-local).
struct Row {
    let rowIndex: Int
    let range: NSRange           // absolute source range of the row
    let cells: [NSRange]         // absolute source ranges of each cell's content
}

/// Parse a row's cell ranges, returning ABSOLUTE source offsets. The
/// caller supplies the row's absolute start offset so we shift the
/// returned ranges accordingly.
private func parseCellRanges(inRowLine ns: NSString,
                             startingAt rowStart: Int,
                             rowLength: Int) -> [NSRange] {
    var ranges: [NSRange] = []
    let PIPE: unichar = 0x7c
    let SPACE: unichar = 0x20
    let NEWLINE: unichar = 0x0a
    let rowEnd = rowStart + rowLength

    var i = rowStart
    // Skip leading pipe + whitespace.
    while i < rowEnd,
          ns.character(at: i) == PIPE || ns.character(at: i) == SPACE {
        i += 1
    }

    while i < rowEnd {
        if ns.character(at: i) == NEWLINE { break }
        let contentStart = i
        while i < rowEnd,
              ns.character(at: i) != PIPE,
              ns.character(at: i) != NEWLINE {
            i += 1
        }
        var contentEnd = i
        while contentEnd > contentStart,
              ns.character(at: contentEnd - 1) == SPACE {
            contentEnd -= 1
        }
        if contentEnd > contentStart {
            ranges.append(NSRange(location: contentStart,
                                  length: contentEnd - contentStart))
        }
        let advanceStart = i
        while i < rowEnd,
              ns.character(at: i) == PIPE || ns.character(at: i) == SPACE {
            i += 1
        }
        if i == advanceStart { break }
    }
    return ranges
}

/// Split a full document source into table rows (one `Row` per line,
/// assuming every non-empty line is a table row — OK for the spike).
func parseRows(in source: String) -> [Row] {
    let ns = source as NSString
    let length = ns.length
    var rows: [Row] = []
    let NEWLINE: unichar = 0x0a

    var lineStart = 0
    var rowIndex = 0
    while lineStart < length {
        // Find end of this line (exclusive of \n).
        var lineEnd = lineStart
        while lineEnd < length, ns.character(at: lineEnd) != NEWLINE {
            lineEnd += 1
        }
        let lineLength = lineEnd - lineStart
        if lineLength > 0 {
            let cells = parseCellRanges(inRowLine: ns,
                                        startingAt: lineStart,
                                        rowLength: lineLength)
            if !cells.isEmpty {
                rows.append(Row(
                    rowIndex: rowIndex,
                    range: NSRange(location: lineStart, length: lineLength),
                    cells: cells))
                rowIndex += 1
            }
        }
        // Advance past the newline.
        lineStart = (lineEnd < length) ? lineEnd + 1 : length
    }
    return rows
}

/// Find the row containing a given source offset (inclusive of the
/// row-end position so a caret "after last char" of the row still
/// resolves to that row).
func rowContaining(offset: Int, in rows: [Row]) -> Row? {
    for row in rows {
        if offset >= row.range.location && offset <= row.range.location + row.range.length {
            return row
        }
    }
    return nil
}

/// Back-compat shim for drawing code that's still row-local (the
/// CellGridFragment reads its own paragraph's attributedString, which
/// is the row-local source). Parses a single-row string into row-local
/// cell ranges.
func parseCellRanges(in rowSource: String) -> [NSRange] {
    let ns = rowSource as NSString
    return parseCellRanges(inRowLine: ns, startingAt: 0, rowLength: ns.length)
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

    /// Resolve a source location to its absolute offset.
    private func absoluteOffset(of loc: any NSTextLocation) -> Int {
        tlm.offset(from: tlm.documentRange.location, to: loc)
    }

    /// Compute the caret X for a source offset, scoped to its row.
    /// Non-cell offsets in a row collapse to the boundary of the nearest
    /// cell (pipes and inter-cell whitespace produce caret positions at
    /// cell edges within that row).
    private func caretX(forSourceOffset i: Int, in rows: [Row]) -> CGFloat {
        guard let row = rowContaining(offset: i, in: rows),
              row.cells.count >= 2 else {
            return CGFloat(i) * perCharStride
        }
        let c1 = row.cells[0]
        let c2 = row.cells[1]
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
        let rows = parseRows(in: source)
        let rowAtLocation = rowContaining(offset: absoluteOffset(of: location), in: rows)
        logLine("CELL-DS", "enumerate at loc offset=\(absoluteOffset(of: location)) → row \(rowAtLocation?.rowIndex ?? -1)")

        // Guard: if the location doesn't map to any parsed row, fall back
        // to the TLM default enumeration for that line fragment.
        guard let row = rowAtLocation, row.cells.count >= 2 else {
            tlm.enumerateCaretOffsetsInLineFragment(at: location, using: block)
            return
        }

        let docStart = tlm.documentRange.location
        var stop = ObjCBool(false)

        func emit(_ i: Int) {
            guard let loc = tlm.location(docStart, offsetBy: i) else { return }
            let x = caretX(forSourceOffset: i, in: rows)
            block(x, loc, true, &stop)
        }

        // Emit source offsets for THIS row's range only. Per the header,
        // `enumerateCaretOffsetsInLineFragment` is scoped to one line
        // fragment — so we emit offsets inside the row's source span.
        let rowStart = row.range.location
        let rowEnd = row.range.location + row.range.length
        // Include the row's end position (+1) so a caret can land after
        // the last char of the last cell in the row.
        for i in rowStart...rowEnd {
            emit(i)
            if stop.boolValue { return }
        }
    }

    func lineFragmentRange(
        for point: CGPoint,
        inContainerAt location: any NSTextLocation
    ) -> NSTextRange? {
        // `location` is the container's anchor (typically documentRange
        // start, offset 0), NOT the click's document position. Use
        // `textLayoutFragment(for: point)` to find the fragment actually
        // hit by the click, then get its range to identify the row.
        guard let hitFragment = tlm.textLayoutFragment(for: point) else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        let rowStartLocation = hitFragment.rangeInElement.location
        let rowStartOffset = tlm.offset(from: tlm.documentRange.location,
                                        to: rowStartLocation)

        let source = currentSource()
        let rows = parseRows(in: source)
        guard let row = rows.first(where: { $0.range.location == rowStartOffset }),
              row.cells.count >= 2 else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        let c1 = row.cells[0]
        let c2 = row.cells[1]

        let docStart = tlm.documentRange.location

        let midX = (cell1Rect.maxX + cell2Rect.minX) / 2
        let targetRange: NSRange = (point.x < midX) ? c1 : c2
        logLine("CELL-DS", "lfr for (\(point.x), \(point.y)) row=\(row.rowIndex) (via fragment hit-test) midX=\(midX) → \(NSEqualRanges(targetRange, c1) ? "cell 1" : "cell 2")")

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
    /// cell's end (within the same row) instead of deleting the pipe.
    /// Multi-row: at cell-1 start, jump to previous row's cell-2 end
    /// (cross-row, non-destructive).
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, let storage = textStorage {
            let source = storage.string
            let rows = parseRows(in: source)
            if let row = rowContaining(offset: sel.location, in: rows),
               row.cells.count >= 2 {
                let c1 = row.cells[0]
                let c2 = row.cells[1]
                // Caret at start of cell 2 → jump to end of cell 1 (same row).
                if sel.location == c2.location {
                    let prevEnd = c1.location + c1.length
                    logLine("UI", "backspace at row-\(row.rowIndex) cell-2 start → row-\(row.rowIndex) cell-1 end (offset \(prevEnd))")
                    setSelectedRange(NSRange(location: prevEnd, length: 0))
                    return
                }
                // Caret at start of cell 1 → jump to previous row's cell-2 end,
                // or line start if this is the first row.
                if sel.location == c1.location {
                    if row.rowIndex > 0,
                       row.rowIndex - 1 < rows.count,
                       let prevRowCells = rows[row.rowIndex - 1].cells.last {
                        let prevEnd = prevRowCells.location + prevRowCells.length
                        logLine("UI", "backspace at row-\(row.rowIndex) cell-1 start → row-\(row.rowIndex - 1) last-cell end (offset \(prevEnd))")
                        setSelectedRange(NSRange(location: prevEnd, length: 0))
                    } else {
                        logLine("UI", "backspace at row-0 cell-1 start → document start")
                        setSelectedRange(NSRange(location: 0, length: 0))
                    }
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    /// Tier 2.4 arrow nav + Tier 2.6 Tab: all driven by current row's cells.
    override func keyDown(with event: NSEvent) {
        logLine("LTV", "keyDown keyCode=\(event.keyCode) selRange=\(selectedRange().location)+\(selectedRange().length)")
        let sel = selectedRange()
        guard sel.length == 0, let storage = textStorage else {
            super.keyDown(with: event)
            return
        }
        let source = storage.string
        let rows = parseRows(in: source)
        let rowFound = rowContaining(offset: sel.location, in: rows)
        logLine("LTV", "  loc=\(sel.location) row=\(rowFound?.rowIndex ?? -1) rowsCount=\(rows.count)")
        guard let row = rowFound,
              row.cells.count >= 2 else {
            super.keyDown(with: event)
            return
        }
        let c1 = row.cells[0]
        let c2 = row.cells[1]
        let c1End = c1.location + c1.length
        let c2End = c2.location + c2.length
        let loc = sel.location

        let KEY_TAB: UInt16 = 48
        let KEY_LEFT: UInt16 = 123
        let KEY_RIGHT: UInt16 = 124

        switch event.keyCode {
        case KEY_TAB:
            let shift = event.modifierFlags.contains(.shift)
            let inCell1 = loc >= c1.location && loc <= c1End
            let target: Int
            if shift {
                if inCell1 {
                    // At first cell of this row; Shift+Tab goes to previous row's last cell end, or stays.
                    if row.rowIndex > 0, let prev = rows[row.rowIndex - 1].cells.last {
                        target = prev.location + prev.length
                    } else {
                        target = c1.location
                    }
                } else {
                    target = c1End
                }
            } else {
                if inCell1 {
                    target = c2.location
                } else {
                    // At last cell of this row; Tab goes to next row's first cell start, or stays.
                    if row.rowIndex + 1 < rows.count, let next = rows[row.rowIndex + 1].cells.first {
                        target = next.location
                    } else {
                        target = c2End
                    }
                }
            }
            logLine("UI", "Tab shift=\(shift) row=\(row.rowIndex) loc=\(loc) → \(target)")
            setSelectedRange(NSRange(location: target, length: 0))
            return

        case KEY_RIGHT:
            if loc == c1End {
                logLine("UI", "→ row=\(row.rowIndex) cell-1 end → cell-2 start (\(c2.location))")
                setSelectedRange(NSRange(location: c2.location, length: 0))
                return
            }
            if loc == c2End {
                // Last cell of this row. Move to next row's first cell start if there is one.
                if row.rowIndex + 1 < rows.count,
                   let next = rows[row.rowIndex + 1].cells.first {
                    logLine("UI", "→ row=\(row.rowIndex) cell-2 end → row=\(row.rowIndex + 1) cell-1 start (\(next.location))")
                    setSelectedRange(NSRange(location: next.location, length: 0))
                } else {
                    logLine("UI", "→ at last-row cell-2 end → ignore (boundary)")
                }
                return
            }
            super.keyDown(with: event)
            return

        case KEY_LEFT:
            if loc == c2.location {
                logLine("UI", "← row=\(row.rowIndex) cell-2 start → cell-1 end (\(c1End))")
                setSelectedRange(NSRange(location: c1End, length: 0))
                return
            }
            if loc == c1.location {
                // First cell of this row. Move to previous row's last cell end if any.
                if row.rowIndex > 0, let prev = rows[row.rowIndex - 1].cells.last {
                    let prevEnd = prev.location + prev.length
                    logLine("UI", "← row=\(row.rowIndex) cell-1 start → row=\(row.rowIndex - 1) last-cell end (\(prevEnd))")
                    setSelectedRange(NSRange(location: prevEnd, length: 0))
                } else {
                    logLine("UI", "← at row-0 cell-1 start → ignore (boundary)")
                }
                return
            }
            super.keyDown(with: event)
            return

        default:
            super.keyDown(with: event)
        }
    }

    /// Delete at cell-end jumps to the next cell's start (same row), or
    /// to next row's first cell if we're at last cell.
    override func deleteForward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, let storage = textStorage {
            let source = storage.string
            let rows = parseRows(in: source)
            if let row = rowContaining(offset: sel.location, in: rows),
               row.cells.count >= 2 {
                let c1 = row.cells[0]
                let c2 = row.cells[1]
                if sel.location == c1.location + c1.length {
                    logLine("UI", "delete at row-\(row.rowIndex) cell-1 end → row-\(row.rowIndex) cell-2 start (\(c2.location))")
                    setSelectedRange(NSRange(location: c2.location, length: 0))
                    return
                }
                if sel.location == c2.location + c2.length {
                    if row.rowIndex + 1 < rows.count, let next = rows[row.rowIndex + 1].cells.first {
                        logLine("UI", "delete at row-\(row.rowIndex) cell-2 end → row-\(row.rowIndex + 1) cell-1 start (\(next.location))")
                        setSelectedRange(NSRange(location: next.location, length: 0))
                    } else {
                        logLine("UI", "delete at last-row cell-2 end → ignore (boundary)")
                    }
                    return
                }
            }
        }
        super.deleteForward(sender)
    }
}

// MARK: - Automation harness

/// Polls /tmp/d12-command.json at regular intervals. When present, reads
/// the JSON, dispatches an action, and deletes the command file so it
/// won't be re-processed. This lets an external driver (Claude Code, a
/// test script, etc.) control the spike via simple file writes + reads.
final class CommandFilePoller {
    let commandPath = "/tmp/d12-command.json"
    let resultPath = "/tmp/d12-result.json"
    weak var delegate: AppDelegate?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard FileManager.default.fileExists(atPath: commandPath) else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: commandPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            try? FileManager.default.removeItem(atPath: commandPath)
            return
        }
        // Delete BEFORE executing so re-entry can't loop.
        try? FileManager.default.removeItem(atPath: commandPath)
        logLine("HARNESS", "command action=\(action) raw=\(obj)")
        delegate?.runHarnessCommand(action: action, params: obj)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var logTextView: NSTextView!
    var dataSource: CellDataSource!
    var gridDelegate: GridDelegate!
    var yOffsetField: NSTextField!
    var xOffsetField: NSTextField!
    var commandPoller: CommandFilePoller!

    // MARK: - Automation command handlers

    func runHarnessCommand(action: String, params: [String: Any]) {
        switch action {
        case "dump_state":
            let path = params["path"] as? String ?? "/tmp/d12-state.json"
            writeStateDump(to: path)
        case "snapshot":
            let path = params["path"] as? String ?? "/tmp/d12-shot.png"
            writeWindowSnapshot(to: path)
        case "reset_text":
            textView.string = initialSourceText
            logLine("HARNESS", "reset_text → \(initialSourceText.count) chars")
            forceRerender()
        case "set_text":
            if let text = params["text"] as? String {
                textView.string = text
                logLine("HARNESS", "set_text → \(text.count) chars")
                forceRerender()
            }
        case "set_selection":
            if let loc = params["location"] as? Int {
                let len = params["length"] as? Int ?? 0
                textView.setSelectedRange(NSRange(location: loc, length: len))
                logLine("HARNESS", "set_selection → (\(loc), \(len))")
            }
        case "window_info":
            writeWindowInfo(to: params["path"] as? String ?? "/tmp/d12-window.json")
        case "cell_screen_rects":
            writeCellScreenRects(to: params["path"] as? String ?? "/tmp/d12-cells.json")
        default:
            logLine("HARNESS", "unknown action: \(action)")
        }
    }

    /// Emit each cell's rect in SCREEN coords (top-left origin, the
    /// coordinate system cliclick / screencapture expect). Uses TextKit
    /// 2 geometry + NSView conversions rather than hand-computed offsets.
    private func writeCellScreenRects(to path: String) {
        guard let tlm = textView.textLayoutManager,
              let tcm = tlm.textContentManager,
              let screenHeight = NSScreen.screens.first?.frame.height
        else { return }

        var cellEntries: [[String: Any]] = []
        var rowIndex = 0
        tlm.enumerateTextLayoutFragments(
            from: tcm.documentRange.location,
            options: [.ensuresLayout]
        ) { frag in
            guard frag is CellGridFragment else { return true }
            let fragFrame = frag.layoutFragmentFrame
            // Per-cell rects in FRAGMENT coords (cell1Rect / cell2Rect), with
            // cellYOffset applied (same transform as draw).
            let dy = TuningKnobs.cellYOffset
            let cellRectsInFragment: [(String, CGRect)] = [
                ("cell-1", cell1Rect.offsetBy(dx: 0, dy: dy)),
                ("cell-2", cell2Rect.offsetBy(dx: 0, dy: dy))
            ]
            for (label, cellRect) in cellRectsInFragment {
                // Fragment frame origin + cell-in-fragment → text-container coords.
                let containerRect = CGRect(
                    x: fragFrame.origin.x + cellRect.origin.x,
                    y: fragFrame.origin.y + cellRect.origin.y,
                    width: cellRect.size.width,
                    height: cellRect.size.height)
                // text-container coords + textContainerInset → text-view coords (top-left).
                let tvInset = self.textView.textContainerInset
                let tvRect = CGRect(
                    x: containerRect.origin.x + tvInset.width,
                    y: containerRect.origin.y + tvInset.height,
                    width: containerRect.width,
                    height: containerRect.height)
                // text-view is flipped=true; its frame is in parent coords.
                // Convert to window coords then screen coords.
                let windowRect = self.textView.convert(tvRect, to: nil)
                let screenRectBL = self.window.convertToScreen(windowRect)
                // Screen coords: flip Y so origin is top-left (cliclick convention).
                let screenRectTL = CGRect(
                    x: screenRectBL.origin.x,
                    y: screenHeight - screenRectBL.origin.y - screenRectBL.size.height,
                    width: screenRectBL.size.width,
                    height: screenRectBL.size.height)

                cellEntries.append([
                    "row": rowIndex,
                    "cell": label,
                    "centerScreen": [
                        "x": screenRectTL.midX,
                        "y": screenRectTL.midY
                    ],
                    "screenTL": [
                        "x": screenRectTL.origin.x,
                        "y": screenRectTL.origin.y,
                        "w": screenRectTL.size.width,
                        "h": screenRectTL.size.height
                    ]
                ])
            }
            rowIndex += 1
            return true
        }

        let payload: [String: Any] = ["cells": cellEntries]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            logLine("HARNESS", "cell_screen_rects → \(path) (\(cellEntries.count) cells)")
        }
    }

    private func forceRerender() {
        guard let tlm = textView.textLayoutManager,
              let tcm = tlm.textContentManager,
              let storage = textView.textStorage else { return }
        let fullNSRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.edited(.editedAttributes, range: fullNSRange, changeInLength: 0)
        storage.endEditing()
        tlm.invalidateLayout(for: tcm.documentRange)
        tlm.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
    }

    /// Serialize spike state to JSON so the harness caller can inspect
    /// it. Includes source, selection, parsed rows + cells, tuning knobs.
    /// Also includes per-fragment rects (layoutFragmentFrame in container
    /// coords) so the caller can reason about row geometry.
    private func writeStateDump(to path: String) {
        let storage = textView.textStorage
        let source = storage?.string ?? ""
        let sel = textView.selectedRange()
        let rows = parseRows(in: source)

        var fragmentInfos: [[String: Any]] = []
        if let tlm = textView.textLayoutManager,
           let tcm = tlm.textContentManager {
            tlm.enumerateTextLayoutFragments(from: tcm.documentRange.location,
                                             options: [.ensuresLayout]) { frag in
                let frame = frag.layoutFragmentFrame
                let render = frag.renderingSurfaceBounds
                fragmentInfos.append([
                    "type": "\(type(of: frag))",
                    "layoutFragmentFrame": [
                        "x": frame.origin.x, "y": frame.origin.y,
                        "w": frame.size.width, "h": frame.size.height
                    ],
                    "renderingSurfaceBounds": [
                        "x": render.origin.x, "y": render.origin.y,
                        "w": render.size.width, "h": render.size.height
                    ]
                ])
                return true
            }
        }

        let state: [String: Any] = [
            "source": source,
            "sourceLength": (source as NSString).length,
            "selection": ["location": sel.location, "length": sel.length],
            "rows": rows.map { row in
                [
                    "rowIndex": row.rowIndex,
                    "range": ["location": row.range.location, "length": row.range.length],
                    "cells": row.cells.map { ["location": $0.location, "length": $0.length] }
                ] as [String: Any]
            },
            "tuning": [
                "cellYOffset": TuningKnobs.cellYOffset,
                "caretXOffset": TuningKnobs.caretXOffset,
                "cellContentXInset": cellContentXInset,
                "perCharStride": perCharStride
            ],
            "cellAnchors": [
                "cell1X": cell1X,
                "cell2X": cell2X,
                "cellWidth": cellWidth,
                "fragmentHeight": fragmentHeight
            ],
            "fragments": fragmentInfos,
            "textContainerInset": [
                "width": textView.textContainerInset.width,
                "height": textView.textContainerInset.height
            ],
            "textViewFrame": [
                "x": textView.frame.origin.x,
                "y": textView.frame.origin.y,
                "w": textView.frame.size.width,
                "h": textView.frame.size.height
            ]
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            logLine("HARNESS", "dumped state to \(path) (\(data.count) bytes)")
        }
    }

    /// Snapshot the window's content view (excludes title bar chrome).
    private func writeWindowSnapshot(to path: String) {
        guard let content = window.contentView else { return }
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        logLine("HARNESS", "snapshot → \(path) (\(data.count) bytes, \(Int(rep.size.width))x\(Int(rep.size.height)))")
    }

    /// Useful for the harness to know the window's screen frame so
    /// cliclick can dispatch clicks at the right absolute coords.
    private func writeWindowInfo(to path: String) {
        let wf = window.frame
        let cf = window.contentView?.frame ?? .zero
        // In macOS screen coords (bottom-left origin), we also compute
        // top-left-origin versions for convenience.
        let screens = NSScreen.screens.first
        let screenHeight = screens?.frame.height ?? 0
        let info: [String: Any] = [
            "windowFrame": [
                "x": wf.origin.x, "y": wf.origin.y,
                "w": wf.size.width, "h": wf.size.height
            ],
            "contentViewFrame": [
                "x": cf.origin.x, "y": cf.origin.y,
                "w": cf.size.width, "h": cf.size.height
            ],
            "titleBarHeight": wf.height - cf.height,
            "screenHeight": screenHeight,
            "contentTopLeftScreenCoords": [
                "x": wf.origin.x,
                // flip y so top-left origin in screen coords
                "y": screenHeight - wf.origin.y - wf.height + (wf.height - cf.height)
            ]
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            logLine("HARNESS", "window_info → \(path)")
        }
    }

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

        commandPoller = CommandFilePoller()
        commandPoller.delegate = self
        commandPoller.start()
        logLine("HARNESS", "polling /tmp/d12-command.json every 200ms")
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
