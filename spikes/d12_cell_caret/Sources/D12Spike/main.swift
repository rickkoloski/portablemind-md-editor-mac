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
let perCharStride: CGFloat = 12   // used for caret x mapping inside a cell

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
        CGRect(origin: .zero, size: layoutFragmentFrame.size)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        NSLog("[FRAG] draw called at point=(%.1f, %.1f)", point.x, point.y)

        // Source for this row.
        guard let paragraph = textElement as? NSTextParagraph else {
            NSLog("[FRAG]   element is not NSTextParagraph")
            return
        }
        let source = paragraph.attributedString.string
        let cellRanges = parseCellRanges(in: source)

        // Draw cell boxes.
        context.saveGState()
        defer { context.restoreGState() }

        let rect1 = cell1Rect.offsetBy(dx: point.x, dy: point.y)
        let rect2 = cell2Rect.offsetBy(dx: point.x, dy: point.y)

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
        // Draw cell content at the top-left of each cell with a small
        // left inset. Vertical origin = 0 so content sits on the line
        // fragment's baseline area (the same y the caret draws at).
        if cellRanges.count >= 1 {
            let txt = ns.substring(with: cellRanges[0])
            (txt as NSString).draw(
                at: CGPoint(x: rect1.origin.x + 8, y: rect1.origin.y + 4),
                withAttributes: attrs)
        }
        if cellRanges.count >= 2 {
            let txt = ns.substring(with: cellRanges[1])
            (txt as NSString).draw(
                at: CGPoint(x: rect2.origin.x + 8, y: rect2.origin.y + 4),
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
        NSLog("[DELEGATE] textLayoutFragmentFor called, element=%@",
              String(describing: type(of: textElement)))
        if textElement is NSTextParagraph {
            NSLog("[DELEGATE]   → returning CellGridFragment")
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

        if i < c1.location {
            // Before cell 1 — left edge of cell 1.
            return cell1X + 8
        }
        if i <= c1.location + c1.length {
            let local = i - c1.location
            return cell1X + 8 + CGFloat(local) * perCharStride
        }
        if i < c2.location {
            // Between cells — right edge of cell 1.
            return cell1X + cellWidth - 8
        }
        if i <= c2.location + c2.length {
            let local = i - c2.location
            return cell2X + 8 + CGFloat(local) * perCharStride
        }
        // After cell 2 — right edge of cell 2.
        return cell2X + cellWidth - 8
    }

    func enumerateCaretOffsetsInLineFragment(
        at location: any NSTextLocation,
        using block: (CGFloat, any NSTextLocation, Bool,
                      UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let source = currentSource()
        let total = (source as NSString).length

        let ranges = parseCellRanges(in: source)
        NSLog("[CELL-DS] enumerate (total=%d, cells=%d)", total, ranges.count)

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
        let targetRange: NSRange
        if cell1Rect.contains(point) {
            targetRange = c1
        } else if cell2Rect.contains(point) {
            targetRange = c2
        } else {
            // Outside any cell — fall back.
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }

        guard let start = tlm.location(docStart, offsetBy: targetRange.location),
              let end = tlm.location(start, offsetBy: targetRange.length)
        else { return tlm.lineFragmentRange(for: point, inContainerAt: location) }

        return NSTextRange(location: start, end: end)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var dataSource: CellDataSource!
    var gridDelegate: GridDelegate!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 250),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "D12 Cell Caret Spike v2 — round trip"
        window.backgroundColor = NSColor.white

        textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = window.contentView!.bounds
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white
        textView.textColor = NSColor.black
        textView.insertionPointColor = NSColor.systemBlue
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 10, height: 30)

        textView.delegate = self

        // Install delegate + data source BEFORE setting the string, so the
        // initial layout runs through our custom fragment path. Production's
        // EditorContainer.swift does this in the same order (tlm.delegate
        // set, then textView.string = ...).
        if let tlm = textView.textLayoutManager {
            gridDelegate = GridDelegate()
            tlm.delegate = gridDelegate

            if let storage = textView.textContentStorage
                ?? tlm.textContentManager as? NSTextContentStorage {
                dataSource = CellDataSource(tlm: tlm, storage: storage)
                tlm.textSelectionNavigation =
                    NSTextSelectionNavigation(dataSource: dataSource)
                NSLog("[SPIKE] installed grid delegate + data source")
            } else {
                NSLog("[SPIKE] ERROR: could not get text content storage")
            }
        } else {
            NSLog("[SPIKE] ERROR: no textLayoutManager")
        }

        textView.string = initialSourceText

        window.contentView?.addSubview(textView)
        // Hardcoded small-corner position so the window cannot land off
        // any screen in a multi-display setup. (100, 100) in screen coords
        // is near the bottom-left of the primary display.
        window.setFrameOrigin(NSPoint(x: 100, y: 100))
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.level = .floating
        window.makeFirstResponder(textView)
        NSLog("[SPIKE] window frame=%@, visible=%@, onActiveSpace=%@",
              NSStringFromRect(window.frame),
              window.isVisible ? "YES" : "NO",
              window.isOnActiveSpace ? "YES" : "NO")

        // Ensure layout after window is on screen.
        if let tlm = textView.textLayoutManager,
           let tcm = tlm.textContentManager {
            tlm.ensureLayout(for: tcm.documentRange)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.arrangeInFront(nil)

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            if let w = event.window, w === self.window {
                let p = self.textView.convert(event.locationInWindow, from: nil)
                NSLog("[EVENT] mouseDown at (%.1f, %.1f) clickCount=%d",
                      p.x, p.y, event.clickCount)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            NSLog("[EVENT] keyDown chars='%@'", event.characters ?? "")
            return event
        }

        NSLog("[SPIKE] ready — click inside a cell, observe caret + type")
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        let sel = tv.selectedRange()
        NSLog("[SPIKE] selection: location=%d length=%d", sel.location, sel.length)
    }

    func textDidChange(_ notification: Notification) {
        NSLog("[SPIKE] textDidChange, length=%d",
              textView.textStorage?.length ?? -1)
        // Force layout invalidation + viewport refresh so the grid fragment
        // redraws with updated source. Without this the custom fragment
        // keeps its cached draw.
        if let tlm = textView.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
            tlm.textViewportLayoutController.layoutViewport()
            textView.needsDisplay = true
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
