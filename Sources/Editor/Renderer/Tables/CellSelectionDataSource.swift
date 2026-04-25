import AppKit
import Foundation

/// Custom `NSTextSelectionDataSource` that wraps the editor's
/// `NSTextLayoutManager` and overrides two methods so caret + click
/// behavior in table rows is **cell-aware**:
///
/// 1. `enumerateCaretOffsetsInLineFragmentAtLocation:usingBlock:` —
///    yields per-character caret x positions inside each cell's grid
///    geometry (rather than at the natural source-text x). Source
///    offsets between cells (pipes + whitespace) collapse to cell
///    edges.
/// 2. `lineFragmentRangeForPoint:inContainerAtLocation:` — returns a
///    cell-scoped `NSTextRange` for clicks in a `TableRowFragment`'s
///    geometry, so click-to-caret routes to the right cell.
///
/// All other data-source methods forward to the wrapped TLM. Install
/// by replacing `tlm.textSelectionNavigation` with one whose data
/// source is an instance of this class.
///
/// Production type that ports the validated spike's `CellDataSource`
/// (`spikes/d12_cell_caret/`). The spike's row-source-string parsing
/// is replaced here by reading `TableLayout.cellRanges` directly off
/// each row's attached `TableRowAttachment`.
final class CellSelectionDataSource: NSObject, NSTextSelectionDataSource {
    /// Strong reference to the wrapped TLM. No retain cycle because
    /// `NSTextSelectionNavigation.textSelectionDataSource` is weak;
    /// the data source's lifetime is owned by an external retainer
    /// (the `EditorContainer` Coordinator).
    private let tlm: NSTextLayoutManager

    init(wrapping textLayoutManager: NSTextLayoutManager) {
        self.tlm = textLayoutManager
    }

    // MARK: - Pass-throughs to the wrapped layout manager

    var documentRange: NSTextRange { tlm.documentRange }

    func enumerateSubstrings(
        from location: any NSTextLocation,
        options: NSString.EnumerationOptions = [],
        using block: (String?, NSTextRange, NSTextRange?,
                      UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        tlm.enumerateSubstrings(from: location, options: options, using: block)
    }

    func textRange(for selectionGranularity: NSTextSelection.Granularity,
                   enclosing location: any NSTextLocation) -> NSTextRange? {
        tlm.textRange(for: selectionGranularity, enclosing: location)
    }

    func location(_ location: any NSTextLocation,
                  offsetBy offset: Int) -> (any NSTextLocation)? {
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
        tlm.enumerateContainerBoundaries(from: location,
                                          reverse: reverse,
                                          using: block)
    }

    // MARK: - Overridden behavior — table-aware caret + hit-test

    /// Yield (caretX, location, leadingEdge, stop) for each source
    /// offset in the line fragment at `location`. For non-table rows
    /// we forward to the wrapped TLM; for table rows we map source
    /// offsets to per-cell geometry.
    func enumerateCaretOffsetsInLineFragment(
        at location: any NSTextLocation,
        using block: (CGFloat, any NSTextLocation, Bool,
                      UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        guard let attachment = tableAttachment(at: location) else {
            tlm.enumerateCaretOffsetsInLineFragment(at: location, using: block)
            return
        }
        let layout = attachment.layout
        guard let rowIdx = attachment.cellContentIndex,
              rowIdx < layout.cellRanges.count
        else {
            tlm.enumerateCaretOffsetsInLineFragment(at: location, using: block)
            return
        }
        let cells = layout.cellRanges[rowIdx]
        // Find the row's source range via the attachment storage.
        guard let rowRange = rowRangeContaining(location: location)
        else {
            tlm.enumerateCaretOffsetsInLineFragment(at: location, using: block)
            return
        }
        let docStart = tlm.documentRange.location
        let rowStart = tlm.offset(from: docStart, to: rowRange.location)
        let rowEnd = tlm.offset(from: docStart, to: rowRange.endLocation)

        var stop = ObjCBool(false)
        for i in rowStart...rowEnd {
            if stop.boolValue { return }
            guard let loc = tlm.location(docStart, offsetBy: i) else { continue }
            let x = caretX(forSourceOffset: i,
                           cells: cells,
                           layout: layout)
            block(x, loc, true, &stop)
        }
    }

    /// Return the cell-scoped `NSTextRange` for a click point in a
    /// table row, or fall back to the wrapped TLM for non-table clicks.
    func lineFragmentRange(for point: CGPoint,
                           inContainerAt location: any NSTextLocation
    ) -> NSTextRange? {
        // TEST-HARNESS: per-call log so we can verify the data source
        // is on the click-routing path. Compiled out of release.
        #if DEBUG
        NSLog("[CELL-DS] lfr at (%.1f, %.1f)", point.x, point.y)
        #endif

        guard let frag = tlm.textLayoutFragment(for: point),
              let attachment = (frag as? TableRowFragment)?.attachment
        else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        let layout = attachment.layout
        guard let rowIdx = attachment.cellContentIndex,
              rowIdx < layout.cellRanges.count
        else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        let cells = layout.cellRanges[rowIdx]
        guard !cells.isEmpty,
              let cellIdx = cellIndex(forPointX: point.x, layout: layout)
        else {
            return tlm.lineFragmentRange(for: point, inContainerAt: location)
        }
        let target = cells[cellIdx]
        let docStart = tlm.documentRange.location
        // +1 on length so caret can land at content-end (one past last
        // char) — see spike Tier-4 finding (off-by-one in NSRange→
        // NSTextRange conversion).
        guard let start = tlm.location(docStart, offsetBy: target.location),
              let end = tlm.location(start, offsetBy: target.length + 1)
        else { return tlm.lineFragmentRange(for: point, inContainerAt: location) }
        return NSTextRange(location: start, end: end)
    }

    // MARK: - Helpers

    /// Read the `TableRowAttachment` at the given location's source
    /// offset, or `nil` if that offset isn't inside a table row.
    private func tableAttachment(at location: any NSTextLocation)
        -> TableRowAttachment? {
        guard let storage = tlm.textContentManager as? NSTextContentStorage,
              let attrStorage = storage.textStorage,
              attrStorage.length > 0
        else { return nil }
        let docStart = tlm.documentRange.location
        let offset = tlm.offset(from: docStart, to: location)
        let probe = max(0, min(offset, attrStorage.length - 1))
        return attrStorage.attribute(
            TableAttributeKeys.rowAttachmentKey,
            at: probe,
            effectiveRange: nil) as? TableRowAttachment
    }

    /// Find the source NSTextRange of the row paragraph containing
    /// `location`. Walks back to the first character whose attachment
    /// matches, then forward to the last; the resulting span is the
    /// row's source line.
    private func rowRangeContaining(location: any NSTextLocation)
        -> NSTextRange? {
        guard let storage = tlm.textContentManager as? NSTextContentStorage,
              let attrStorage = storage.textStorage,
              attrStorage.length > 0,
              let pivot = tableAttachment(at: location)
        else { return nil }
        let docStart = tlm.documentRange.location
        let probeOffset = max(0, min(
            tlm.offset(from: docStart, to: location),
            attrStorage.length - 1))
        let pivotID = ObjectIdentifier(pivot)

        // Walk back while the attachment matches (same row).
        var lo = probeOffset
        while lo > 0,
              let prev = attrStorage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: lo - 1,
                effectiveRange: nil) as? TableRowAttachment,
              ObjectIdentifier(prev) == pivotID {
            lo -= 1
        }
        // Walk forward while the attachment matches.
        var hi = probeOffset
        while hi < attrStorage.length - 1,
              let next = attrStorage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: hi + 1,
                effectiveRange: nil) as? TableRowAttachment,
              ObjectIdentifier(next) == pivotID {
            hi += 1
        }
        guard let start = tlm.location(docStart, offsetBy: lo),
              let end = tlm.location(docStart, offsetBy: hi + 1)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Map a source offset within a table row to a caret x position
    /// using the row's TableLayout column geometry. Source offsets
    /// before/between/after cells collapse to cell edges so the caret
    /// has a sensible visual home.
    private func caretX(forSourceOffset i: Int,
                        cells: [NSRange],
                        layout: TableLayout) -> CGFloat {
        guard !cells.isEmpty,
              !layout.columnLeadingX.isEmpty,
              !layout.contentWidths.isEmpty else { return 0 }
        let stride = advanceStride(layout: layout)

        if i < cells[0].location {
            return layout.columnLeadingX[0]
        }
        for (idx, cell) in cells.enumerated() {
            let cellEnd = cell.location + cell.length
            if i >= cell.location && i <= cellEnd, idx < layout.columnLeadingX.count {
                let local = i - cell.location
                return layout.columnLeadingX[idx] + CGFloat(local) * stride
            }
            if idx + 1 < cells.count, idx < layout.columnTrailingX.count {
                let nextStart = cells[idx + 1].location
                if i > cellEnd && i < nextStart {
                    return layout.columnTrailingX[idx]
                }
            }
        }
        let lastIdx = cells.count - 1
        if lastIdx < layout.columnTrailingX.count {
            return layout.columnTrailingX[lastIdx]
        }
        return layout.columnLeadingX[0]
    }

    /// Per-character advance width inside a cell. Simple "M" stride
    /// against the layout's body font. Adequate for monospaced cell
    /// content; D12 step 6 (font-metric tuning) refines this for
    /// proportional fonts via CT glyph-advance-aware mapping.
    private func advanceStride(layout: TableLayout) -> CGFloat {
        ("M" as NSString).size(
            withAttributes: [.font: layout.bodyFont]
        ).width
    }

    /// Map a click x-coordinate (fragment-local) to a column index in
    /// the row's layout. Clicks before the first column / after the
    /// last column snap to the nearest column.
    private func cellIndex(forPointX pointX: CGFloat,
                           layout: TableLayout) -> Int? {
        let leading = layout.columnLeadingX
        let trailing = layout.columnTrailingX
        guard !leading.isEmpty, leading.count == trailing.count else { return nil }
        let inset = layout.cellInset
        // The cell's outer bounds (including padding) span from
        // leading[i] - inset.left to trailing[i] + inset.right.
        for i in 0..<leading.count {
            let cellLeft = leading[i] - inset.left
            let cellRight = trailing[i] + inset.right
            if pointX < cellLeft && i == 0 { return 0 }
            if pointX >= cellLeft && pointX < cellRight { return i }
        }
        // Past the last cell.
        return leading.count - 1
    }
}

