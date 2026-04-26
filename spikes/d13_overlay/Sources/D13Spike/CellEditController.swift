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
        if let storage = host.textStorage {
            storage.replaceCharacters(in: activeCellRange, with: escaped)
            SpikeRenderer.render(into: storage)
        }
        spikeLog("overlay commit: range=\(activeCellRange) new=\(escaped)")
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
    func overlayAdvanceTab(_ overlay: CellEditOverlay, backward: Bool) {
        // Tier 5 will implement Tab navigation. For Tier 1, just commit.
        commit()
    }
}
