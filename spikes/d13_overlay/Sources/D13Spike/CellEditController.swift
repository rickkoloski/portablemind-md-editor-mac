// CellEditController — owns a single reusable CellEditOverlay.
// On showOverlay(forCellAt:clickPoint:), positions the overlay at the
// cell's view-coord rect and seeds it with the cell's source content.
// On commit, splices the overlay's text back into the host's source
// at the cell's range.

import AppKit
import Foundation

final class CellEditController: NSObject, CellEditOverlayDelegate {
    private weak var hostView: NSTextView?
    private var overlay: CellEditOverlay?

    /// Active cell tracking — we record what cell the overlay is editing
    /// so commit can splice back to the right source range.
    private(set) var activeRow: Int = -1   // row index in document (table-row source range)
    private(set) var activeCol: Int = -1
    private(set) var activeCellRange: NSRange = NSRange(location: 0, length: 0)
    private(set) var activeAttachment: TableRowAttachment?

    /// Captured at commit time so Tab nav can find the same logical table
    /// after the renderer creates fresh layout instances.
    fileprivate var lastCommitAnchor: TableAnchor?
    /// Where the active row's source range starts — used to compute the
    /// table's first-row location at commit time.
    private var activeTableFirstRowLoc: Int = 0

    init(hostView: NSTextView) {
        self.hostView = hostView
        super.init()
    }

    var isActive: Bool { overlay != nil }

    /// Show the overlay over the cell at (rowIdx, colIdx) of `attachment.layout`.
    /// `tableRowSourceRange` is the row's source range in the host's NSTextStorage.
    /// `localCaretIndex` is the initial caret position within the cell's content.
    func showOverlay(attachment: TableRowAttachment,
                     rowIdx: Int,
                     colIdx: Int,
                     tableRowSourceRange: NSRange,
                     localCaretIndex: Int,
                     fragmentFrame: CGRect) {
        // Capture the table's first row source location for Tab anchor.
        if let storage = hostView?.textStorage {
            // Walk back from the active row to find the first row of this layout
            // (= smallest offset of any row whose attachment.layout === attachment.layout).
            var firstLoc = tableRowSourceRange.location
            let scanRange = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(SpikeAttributeKeys.rowAttachmentKey,
                                       in: scanRange, options: []) { value, range, _ in
                if let att = value as? TableRowAttachment,
                   ObjectIdentifier(att.layout) == ObjectIdentifier(attachment.layout) {
                    firstLoc = min(firstLoc, range.location)
                }
            }
            self.activeTableFirstRowLoc = firstLoc
        }
        guard let host = hostView else { return }
        // If overlay is currently mounted in another cell, commit first.
        if isActive { commit() }

        let layout = attachment.layout
        guard rowIdx < layout.cellContentPerRow.count,
              colIdx < layout.cellContentPerRow[rowIdx].count,
              colIdx < layout.contentWidths.count
        else { return }

        // Compute the cell's full rect in text-view coords (the cell
        // INCLUDING its cellInset gutter, so the active-cell border
        // wraps the entire cell box). Text inside the overlay aligns
        // with the host's cell rendering because we set the overlay's
        // textContainerInset = cellInset below.
        let inset = host.textContainerInset
        let cellLeft = fragmentFrame.origin.x + layout.columnLeadingX[colIdx] - layout.cellInset.left + inset.width
        let cellTop = fragmentFrame.origin.y + inset.height
        let cellWidth = layout.contentWidths[colIdx] + layout.cellInset.left + layout.cellInset.right
        let cellHeight = fragmentFrame.size.height
        let cellFrameInTV = CGRect(x: cellLeft, y: cellTop, width: cellWidth, height: cellHeight)

        // Get the cell's source content as a string. Use the cell's source
        // range so we capture what's actually in the markdown buffer.
        let cellRange = layout.cellRanges[rowIdx][colIdx]
        // cellRange is row-relative? No — production cellRanges store
        // ABSOLUTE document offsets. The renderer's parseCellRanges
        // returns absolute document offsets (we pass `rowStart` to
        // parseCellRanges which produces absolute ranges).
        let cellSource = (host.string as NSString).substring(with: cellRange)

        // Construct overlay (or reuse if existing — we kill+recreate
        // here for spike simplicity; production may pool).
        // Container width = content width (column width); the overlay's
        // textContainerInset adds cellInset.left + .right horizontally
        // to bring total inner width up to the cell rect's width.
        let textContainer = NSTextContainer(size: CGSize(width: layout.contentWidths[colIdx], height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let storage = NSTextStorage(string: cellSource,
                                     attributes: [
                                        .font: layout.bodyFont,
                                        .foregroundColor: NSColor.labelColor
                                     ])
        storage.addLayoutManager(layoutManager)

        let ov = CellEditOverlay(frame: cellFrameInTV, textContainer: textContainer)
        ov.commitDelegate = self
        ov.font = layout.bodyFont
        ov.minSize = .zero
        ov.maxSize = NSSize(width: cellFrameInTV.size.width, height: CGFloat.greatestFiniteMagnitude)
        ov.isVerticallyResizable = false
        ov.isHorizontallyResizable = false
        ov.autoresizingMask = []
        // Match host's cellInset so text aligns with the host cell rendering.
        ov.textContainerInset = NSSize(width: layout.cellInset.left,
                                       height: layout.cellInset.top)
        host.addSubview(ov)
        ov.frame = cellFrameInTV
        let safeIdx = max(0, min(localCaretIndex, cellSource.count))
        ov.setSelectedRange(NSRange(location: safeIdx, length: 0))
        host.window?.makeFirstResponder(ov)

        self.overlay = ov
        self.activeRow = rowIdx
        self.activeCol = colIdx
        self.activeCellRange = cellRange
        self.activeAttachment = attachment

        spikeLog("overlay show: row=\(rowIdx) col=\(colIdx) cellRange=\(cellRange) frame=\(cellFrameInTV)")
    }

    func commit() {
        guard let ov = overlay, let host = hostView else { return }
        let newContent = ov.string
        // Pipe-escape on commit: `|` → `\|`. (Spike: simple escape; doesn't
        // un-escape pre-existing `\|` for now.)
        let escaped = newContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
        // Compute character delta to update the table-first-row anchor for
        // Tab navigation (so post-commit row lookup finds the right table).
        let delta = escaped.utf16.count - activeCellRange.length
        let updatedFirstRowLoc = activeTableFirstRowLoc <= activeCellRange.location
            ? activeTableFirstRowLoc
            : activeTableFirstRowLoc + delta
        lastCommitAnchor = TableAnchor(tableFirstRowLoc: updatedFirstRowLoc)
        if let storage = host.textStorage {
            storage.replaceCharacters(in: activeCellRange, with: escaped)
            SpikeRenderer.render(into: storage)
        }
        spikeLog("overlay commit: range=\(activeCellRange) new=\(escaped) anchor=\(updatedFirstRowLoc)")
        teardown()
    }

    func cancel() {
        spikeLog("overlay cancel")
        teardown()
    }

    private func teardown() {
        overlay?.removeFromSuperview()
        overlay = nil
        activeRow = -1
        activeCol = -1
        activeCellRange = NSRange(location: 0, length: 0)
        activeAttachment = nil
        hostView?.window?.makeFirstResponder(hostView)
    }

    // MARK: - CellEditOverlayDelegate

    func overlayCommit(_ overlay: CellEditOverlay) { commit() }
    func overlayCancel(_ overlay: CellEditOverlay) { cancel() }

    /// Tier 5: Tab / Shift+Tab navigation across cells.
    /// Commits the current cell, then re-shows the overlay on the next
    /// cell across rows (within the same table). At table boundaries
    /// (last cell of last row, first cell of first row) commits and
    /// dismisses the overlay rather than wrapping.
    func overlayAdvanceTab(_ overlay: CellEditOverlay, backward: Bool) {
        guard let attachment = activeAttachment,
              let host = hostView,
              let storage = host.textStorage,
              let tlm = host.textLayoutManager else {
            commit()
            return
        }
        let curRow = activeRow
        let curCol = activeCol
        let layout = attachment.layout

        // Compute next (row, col) within the same table.
        var nextRow = curRow
        var nextCol = curCol + (backward ? -1 : 1)
        let colCount = layout.contentWidths.count
        if nextCol >= colCount {
            nextCol = 0
            nextRow += 1
        } else if nextCol < 0 {
            nextCol = colCount - 1
            nextRow -= 1
        }

        // Bounds: row must be a valid cellContentIndex.
        if nextRow < 0 || nextRow >= layout.cellContentPerRow.count {
            // Past table boundary — commit + dismiss.
            commit()
            return
        }

        // Commit current cell first; capture next-cell info BEFORE commit
        // (commit() re-runs renderer which creates fresh layout instances).
        commit()

        // Locate the new (rowIdx, colIdx) in the freshly-rendered storage.
        // Walk attributes to find the row's TableRowAttachment whose layout
        // is the new layout, kind != .separator, and cellContentIndex == nextRow.
        var foundAttachment: TableRowAttachment?
        var foundRowRange: NSRange?
        let full = NSRange(location: 0, length: storage.length)
        // We can't compare ObjectIdentifier because layouts were re-instantiated.
        // Instead, identify by document position: find rows belonging to the
        // table that contained the previously-edited cell. We use the original
        // tableRowSourceRange's location as an anchor — find the layout whose
        // first row starts at or after the smallest start offset that matches
        // the previous table's first row offset.
        //
        // Simpler heuristic for the spike: collect all rows in document order,
        // group by layout, find the group whose row offsets bracket the
        // previously-active range location, then pick that group's nextRow'th
        // body row at nextCol.
        let originalRowLoc = activeCellRange.location  // captured BEFORE commit() ran. Wait — no, commit() teardown'd those.
        _ = originalRowLoc
        // Capture before commit() — we need to refactor to remember table identity.
        // For the spike, take a simpler path: re-walk + match by table containing
        // the activeRow/activeCol's pre-commit position.
        // Pre-commit, we knew the table. Save it before commit:
        //   (Refactored: see captureTableAnchor + restoreTableAnchor below.)
        spikeLog("Tab nav: targetRow=\(nextRow) targetCol=\(nextCol) — using saved anchor")

        // For spike: use the saved anchor (set at commit time before teardown).
        guard let anchor = lastCommitAnchor else { return }
        var rowsInTable: [(NSRange, TableRowAttachment)] = []
        storage.enumerateAttribute(SpikeAttributeKeys.rowAttachmentKey,
                                   in: full, options: []) { value, range, _ in
            if let att = value as? TableRowAttachment {
                rowsInTable.append((range, att))
            }
        }
        // Group by layout instance (post-rerender layouts are fresh).
        var byLayout: [(ObjectIdentifier, [(NSRange, TableRowAttachment)])] = []
        for r in rowsInTable {
            let id = ObjectIdentifier(r.1.layout)
            if let idx = byLayout.firstIndex(where: { $0.0 == id }) {
                byLayout[idx].1.append(r)
            } else {
                byLayout.append((id, [r]))
            }
        }
        // Pick the table whose first row's start equals the anchor's tableFirstRowLoc,
        // OR whose first row's start is closest to it (the row may have shifted by
        // the commit's character delta).
        var bestTable: [(NSRange, TableRowAttachment)]?
        var bestDist = Int.max
        for (_, rows) in byLayout {
            guard let firstLoc = rows.first?.0.location else { continue }
            let dist = abs(firstLoc - anchor.tableFirstRowLoc)
            if dist < bestDist {
                bestDist = dist
                bestTable = rows
            }
        }
        guard let tableRows = bestTable else { return }
        let nonSepRows = tableRows.filter { $0.1.kind != .separator }
        guard nextRow < nonSepRows.count,
              let cci = nonSepRows[nextRow].1.cellContentIndex else { return }
        foundAttachment = nonSepRows[nextRow].1
        foundRowRange = nonSepRows[nextRow].0

        guard let nextAttachment = foundAttachment,
              let rowRange = foundRowRange else { return }

        // Find the layout fragment for that row.
        guard let docStart = tlm.textContentManager?.documentRange.location,
              let rowStart = tlm.location(docStart, offsetBy: rowRange.location),
              let frag = tlm.textLayoutFragment(for: rowStart) else { return }

        // Initial caret = 0 for the new cell on Tab (matches Numbers).
        showOverlay(
            attachment: nextAttachment,
            rowIdx: cci,
            colIdx: nextCol,
            tableRowSourceRange: rowRange,
            localCaretIndex: 0,
            fragmentFrame: frag.layoutFragmentFrame)
        spikeLog("Tab advance: now showing row=\(cci) col=\(nextCol) cellRange=\(activeCellRange)")
    }
}

/// Anchor captured at commit time so post-rerender Tab navigation can
/// locate the same logical table by its first-row offset.
private struct TableAnchor {
    let tableFirstRowLoc: Int
}
