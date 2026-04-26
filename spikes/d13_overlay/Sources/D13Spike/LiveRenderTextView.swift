// LiveRenderTextView — NSTextView subclass that intercepts mouseDown
// to mount a cell-edit overlay when the click lands on a TableRowFragment
// cell. Single-click only for Tier 1; double-click and modifier-click
// stay default for Tier 5+.

import AppKit
import Foundation

final class LiveRenderTextView: NSTextView {
    var cellEditController: CellEditController?

    override func mouseDown(with event: NSEvent) {
        guard let tlm = textLayoutManager else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let inset = textContainerInset
        let containerPoint = CGPoint(x: viewPoint.x - inset.width,
                                     y: viewPoint.y - inset.height)
        guard let frag = tlm.textLayoutFragment(for: containerPoint),
              let row = frag as? TableRowFragment else {
            super.mouseDown(with: event)
            return
        }
        let attachment = row.attachment
        // Only act on header/body rows; separator is non-interactive.
        guard attachment.kind != .separator,
              let cci = attachment.cellContentIndex else {
            super.mouseDown(with: event)
            return
        }

        let layout = attachment.layout
        let fragFrame = frag.layoutFragmentFrame
        // Locate column based on the click's x within the fragment.
        let xInFrag = containerPoint.x - fragFrame.origin.x
        var colIdx = -1
        for c in 0..<layout.contentWidths.count {
            let leftEdge = layout.columnLeadingX[c] - layout.cellInset.left
            let rightEdge = layout.columnTrailingX[c] + layout.cellInset.right
            if xInFrag >= leftEdge && xInFrag < rightEdge {
                colIdx = c
                break
            }
        }
        if colIdx < 0 {
            // Click in margin — fall through.
            super.mouseDown(with: event)
            return
        }

        // For Tier 1: place caret at offset 0. Tier 2 implements
        // proper click-to-caret math.
        let localCaretIndex = 0

        // Find the source range of the table row containing the fragment.
        // The fragment's textElement.elementRange gives us this.
        guard let element = frag.textElement,
              let textRange = element.elementRange else {
            super.mouseDown(with: event)
            return
        }
        let docStart = tlm.documentRange.location
        let rowLoc = tlm.offset(from: docStart, to: textRange.location)
        let rowLen = tlm.offset(from: textRange.location, to: textRange.endLocation)
        let rowSourceRange = NSRange(location: rowLoc, length: rowLen)

        cellEditController?.showOverlay(
            attachment: attachment,
            rowIdx: cci,
            colIdx: colIdx,
            tableRowSourceRange: rowSourceRange,
            localCaretIndex: localCaretIndex,
            fragmentFrame: fragFrame)
    }
}
