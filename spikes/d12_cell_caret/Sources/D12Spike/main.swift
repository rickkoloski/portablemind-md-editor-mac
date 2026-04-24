// D12 Cell Caret Spike — validate that a custom NSTextSelectionDataSource
// can route caret x-position to cell geometry independent of source character
// visual layout.
//
// Hypothesis: overriding `enumerateCaretOffsetsInLineFragmentAtLocation` and
// `lineFragmentRangeForPoint` on a custom NSTextSelectionDataSource causes
// NSTextView to draw the caret at our custom x-offsets.
//
// Observation: every call into CellDataSource is logged with [CELL-DS] prefix.
// Mouse and key events are logged with [EVENT]. If [CELL-DS] lines appear on
// click/keypress, the DataSource is on the hot path.

import AppKit
import Foundation

// MARK: - Spike constants

let sourceText = "| cell one | cell two |\n"

// Source-offset ranges of the two cells' content.
let cell1SourceRange = NSRange(location: 2, length: 8)   // "cell one"
let cell2SourceRange = NSRange(location: 13, length: 8)  // "cell two"

// Virtual grid geometry — deliberately far from where source text would render.
let cell1VisualX: CGFloat = 300
let cell1VisualWidth: CGFloat = 200
let cell2VisualX: CGFloat = 550
let cell2VisualWidth: CGFloat = 200
let visualCharStride: CGFloat = 18

// MARK: - Custom NSTextSelectionDataSource

final class CellDataSource: NSObject, NSTextSelectionDataSource {
    let tlm: NSTextLayoutManager
    init(tlm: NSTextLayoutManager) { self.tlm = tlm }

    var documentRange: NSTextRange { tlm.documentRange }

    func enumerateSubstrings(
        from location: any NSTextLocation,
        options: NSString.EnumerationOptions = [],
        using block: (String?, NSTextRange, NSTextRange?, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        tlm.enumerateSubstrings(from: location, options: options, using: block)
    }

    func textRange(for selectionGranularity: NSTextSelection.Granularity,
                   enclosing location: any NSTextLocation) -> NSTextRange? {
        tlm.textRange(for: selectionGranularity, enclosing: location)
    }

    func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
        tlm.location(location, offsetBy: offset)
    }

    func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
        tlm.offset(from: from, to: to)
    }

    func baseWritingDirection(at location: any NSTextLocation)
        -> NSTextSelectionNavigation.WritingDirection {
        tlm.baseWritingDirection(at: location)
    }

    func textLayoutOrientation(at location: any NSTextLocation)
        -> NSTextSelectionNavigation.LayoutOrientation {
        tlm.textLayoutOrientation(at: location)
    }

    func enumerateContainerBoundaries(
        from location: any NSTextLocation,
        reverse: Bool,
        using block: (any NSTextLocation, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        tlm.enumerateContainerBoundaries(from: location, reverse: reverse, using: block)
    }

    // MARK: - Overridden behavior

    func enumerateCaretOffsetsInLineFragment(
        at location: any NSTextLocation,
        using block: (CGFloat, any NSTextLocation, Bool, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        // SPIKE TEST 2: return monotonic x-values that are OBVIOUSLY shifted
        // from natural CT layout. Natural 24pt Menlo char width ≈ 14.4pt;
        // we return every character at 30pt stride starting at x=50.
        // If the caret visually draws at our x values, DataSource controls
        // caret placement. If it draws at natural ~14.4*offset positions,
        // DataSource does not.
        NSLog("[CELL-DS] enumerateCaretOffsets called at location=%@",
              "\(location)")

        let docStart = tlm.documentRange.location
        var stop = ObjCBool(false)
        let rowLength = (sourceText as NSString).length - 1  // exclude trailing \n

        for i in 0...rowLength {
            if stop.boolValue { break }
            let caretX = 50.0 + CGFloat(i) * 30.0
            guard let loc = tlm.location(docStart, offsetBy: i) else { continue }
            NSLog("[CELL-DS]   yielding srcIdx=%d x=%.1f", i, caretX)
            block(caretX, loc, true, &stop)
        }
    }

    func lineFragmentRange(for point: CGPoint,
                           inContainerAt location: any NSTextLocation) -> NSTextRange? {
        NSLog("[CELL-DS] lineFragmentRangeForPoint (%.1f, %.1f)", point.x, point.y)

        let docStart = tlm.documentRange.location

        let cell1Rect = CGRect(x: cell1VisualX, y: 0,
                               width: cell1VisualWidth, height: 1000)
        let cell2Rect = CGRect(x: cell2VisualX, y: 0,
                               width: cell2VisualWidth, height: 1000)

        let targetRange: NSRange?
        if cell1Rect.contains(point) {
            NSLog("[CELL-DS]   → cell 1 hit")
            targetRange = cell1SourceRange
        } else if cell2Rect.contains(point) {
            NSLog("[CELL-DS]   → cell 2 hit")
            targetRange = cell2SourceRange
        } else {
            NSLog("[CELL-DS]   → outside cells, fallback")
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }

        guard let range = targetRange,
              let start = tlm.location(docStart, offsetBy: range.location),
              let end = tlm.location(start, offsetBy: range.length)
        else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        return NSTextRange(location: start, end: end)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var dataSource: CellDataSource!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[SPIKE] applicationDidFinishLaunching")

        let windowRect = NSRect(x: 100, y: 100, width: 900, height: 200)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "D12 Cell Caret Spike"
        window.backgroundColor = NSColor.white

        // Text view fills the content view directly. No scroll view — keeps
        // coordinate systems simple for the spike.
        let contentBounds = window.contentView!.bounds
        textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = contentBounds
        textView.autoresizingMask = [.width, .height]

        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white
        textView.textColor = NSColor.black
        textView.insertionPointColor = NSColor.systemBlue
        textView.font = NSFont(name: "Menlo", size: 24)
            ?? NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 12, height: 60)

        textView.string = sourceText
        textView.delegate = self

        window.contentView?.addSubview(textView)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        NSLog("[SPIKE] textView frame=%@ bounds=%@",
              NSStringFromRect(textView.frame),
              NSStringFromRect(textView.bounds))
        NSLog("[SPIKE] textStorage length=%d, string='%@'",
              textView.textStorage?.length ?? -1,
              textView.string)

        // Install the custom data source AFTER the text view is fully configured
        // and has a layout manager available.
        if let tlm = textView.textLayoutManager {
            dataSource = CellDataSource(tlm: tlm)
            tlm.textSelectionNavigation = NSTextSelectionNavigation(dataSource: dataSource)
            NSLog("[SPIKE] installed custom NSTextSelectionNavigation")
            NSLog("[SPIKE] tlm.textSelectionNavigation.dataSource === dataSource? %@",
                  (tlm.textSelectionNavigation.textSelectionDataSource as AnyObject) === dataSource
                    ? "YES" : "NO")
        } else {
            NSLog("[SPIKE] ERROR: textView.textLayoutManager is nil")
        }

        NSApp.activate(ignoringOtherApps: true)

        // Event monitors — log clicks and keys regardless of who handles them.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            if let w = event.window, w === self.window {
                let p = self.textView.convert(event.locationInWindow, from: nil)
                NSLog("[EVENT] mouseDown text-view (%.1f, %.1f) clickCount=%d",
                      p.x, p.y, event.clickCount)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            NSLog("[EVENT] keyDown chars='%@'", event.characters ?? "")
            return event
        }

        NSLog("[SPIKE] ready — waiting for interaction")
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        let sel = tv.selectedRange()
        NSLog("[SPIKE] selection: location=%d length=%d", sel.location, sel.length)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
