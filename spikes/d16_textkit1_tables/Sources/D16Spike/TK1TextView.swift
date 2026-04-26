// TK1TextView — minimal NSTextView subclass for the spike. Logs
// mouseDown selection results so we can see Scenario 2 (click-to-
// caret) and Scenario 4 (wrapped-cell click) without instrumentation
// in the stdlib path.
//
// Crucially: NO mouseDown override, NO scrollRangeToVisible override,
// NO layout-manager delegate. The whole point of D16 is to verify
// the four canonical scenarios work using stock TK1 behavior. If we
// reach for any of those workarounds we've changed framework without
// solving the problem class — see d16 spike spec § 4.

import AppKit

final class TK1TextView: NSTextView {
    /// Built by the spike doc so click handlers can answer
    /// "what cell did I land in?". Set externally after the
    /// attributed string is installed.
    static var cellRanges: [(row: Int, col: Int, range: NSRange)] = []

    override var acceptsFirstResponder: Bool { true }

    // Observation hook: report what cell the caret lands in after
    // a click. Pass-through to super so default behavior is intact.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let sel = selectedRange()
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let cell = TK1TextView.cell(forCharIndex: sel.location) {
            print("[D16] click at viewPoint=\(viewPoint) → caret loc=\(sel.location) → " +
                  "cell row=\(cell.row) col=\(cell.col) (range=\(cell.range))")
        } else {
            print("[D16] click at viewPoint=\(viewPoint) → caret loc=\(sel.location) → NO CELL " +
                  "(landed in plain-text region)")
        }
    }

    static func cell(forCharIndex index: Int) -> (row: Int, col: Int, range: NSRange)? {
        for entry in cellRanges {
            if NSLocationInRange(index, entry.range) ||
               index == entry.range.location + entry.range.length {
                return entry
            }
        }
        return nil
    }
}
