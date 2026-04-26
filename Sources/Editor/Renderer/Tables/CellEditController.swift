// D13: Cell-edit controller — owns the singleton CellEditOverlay,
// shows / commits / cancels it. Coordinator-owned (held by
// EditorContainer.Coordinator).
//
// Show flow (spec §3.2):
//   1. Caller (LiveRenderTextView.mouseDown) provides the row's
//      attachment, (rowIdx, colIdx), source range, click-derived
//      caret index, and the fragment frame.
//   2. Compute the cell's full rect in text-view coords (incl. cellInset
//      gutter), construct an NSTextView subview at that frame, copy
//      the cell's source content into its storage, set caret, make
//      first responder.
//
// Commit flow (spec §3.3):
//   1. Pipe-escape (\\ → \\\\, then | → \|) and newline normalize.
//   2. replaceCharacters(in: cellRange, with: escaped) on host storage.
//   3. Call coordinator.renderCurrentText to re-render the table.
//   4. Tear down overlay; restore first responder to host.
//
// Tab nav (spec §3.10, Phase 4) — see overlayAdvanceTab. Uses an
// anchor pattern (table's first-row source location at commit time)
// to relocate the same logical table after re-render destroys layout
// instances. Header rows are excluded from the cycle (Numbers/Excel
// convention).

import AppKit
import Foundation

@MainActor
final class CellEditController: NSObject, CellEditOverlayDelegate {
    private weak var hostView: NSTextView?
    /// Closure into the coordinator's renderCurrentText so commit can
    /// re-render without taking a strong reference to the coordinator.
    private let renderHook: (NSTextView) -> Void

    private var overlay: CellEditOverlay?

    /// Active cell tracking. Recorded so commit can splice back to
    /// the correct source range and Tab nav can compute the next cell.
    private(set) var activeRow: Int = -1
    private(set) var activeCol: Int = -1
    private(set) var activeCellRange: NSRange = NSRange(location: 0, length: 0)
    private(set) var activeAttachment: TableRowAttachment?

    /// Captured at commit time so post-rerender Tab nav can relocate
    /// the same logical table by source-position anchor (re-render
    /// destroys layout instance identity).
    private var lastCommitAnchor: TableAnchor?
    private var activeTableFirstRowLoc: Int = 0

    init(hostView: NSTextView, renderHook: @escaping (NSTextView) -> Void) {
        self.hostView = hostView
        self.renderHook = renderHook
        super.init()
    }

    var isActive: Bool { overlay != nil }

    /// Show the overlay over `(rowIdx, colIdx)` of `attachment.layout`.
    /// `tableRowSourceRange` is the row's source range in the host's
    /// NSTextStorage. `localCaretIndex` is the initial caret position
    /// within the cell content (post `parseCellRanges` trim).
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

        // Capture the table's first-row source location for Tab anchor.
        // Walk the storage to find the smallest row offset whose
        // attachment.layout matches.
        if let storage = host.textStorage {
            var firstLoc = tableRowSourceRange.location
            let scanRange = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(
                TableAttributeKeys.rowAttachmentKey,
                in: scanRange, options: []
            ) { value, range, _ in
                if let att = value as? TableRowAttachment,
                   ObjectIdentifier(att.layout) == ObjectIdentifier(attachment.layout) {
                    firstLoc = min(firstLoc, range.location)
                }
            }
            self.activeTableFirstRowLoc = firstLoc
        }

        // Compute the cell's full rect in text-view coords. We size the
        // overlay to include the cellInset gutter so the active-cell
        // border wraps the entire cell box. textContainerInset = cellInset
        // makes the overlay's text origin align with the host's
        // drawCells output.
        let inset = host.textContainerInset
        let cellLeft = fragmentFrame.origin.x + layout.columnLeadingX[colIdx]
            - layout.cellInset.left + inset.width
        let cellTop = fragmentFrame.origin.y + inset.height
        let cellWidth = layout.contentWidths[colIdx]
            + layout.cellInset.left + layout.cellInset.right
        let cellHeight = fragmentFrame.size.height
        let cellFrameInTV = CGRect(
            x: cellLeft, y: cellTop, width: cellWidth, height: cellHeight)

        // Get the cell's source content (post-trim).
        let cellRange = layout.cellRanges[rowIdx][colIdx]
        let cellSource = (host.string as NSString).substring(with: cellRange)

        // Construct the overlay's text container at the content width
        // (NOT the full cell width) — textContainerInset adds the
        // cellInset.left/right padding.
        let textContainer = NSTextContainer(size: CGSize(
            width: layout.contentWidths[colIdx],
            height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let storage = NSTextStorage(string: cellSource, attributes: [
            .font: layout.bodyFont,
            .foregroundColor: NSColor.labelColor
        ])
        storage.addLayoutManager(layoutManager)

        let ov = CellEditOverlay(frame: cellFrameInTV, textContainer: textContainer)
        ov.commitDelegate = self
        ov.font = layout.bodyFont
        ov.minSize = .zero
        ov.maxSize = NSSize(width: cellFrameInTV.size.width,
                            height: CGFloat.greatestFiniteMagnitude)
        ov.isVerticallyResizable = false
        ov.isHorizontallyResizable = false
        ov.autoresizingMask = []
        ov.textContainerInset = NSSize(
            width: layout.cellInset.left,
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
    }

    func commit() {
        guard let ov = overlay, let host = hostView else { return }
        let newContent = ov.string
        // Pipe-escape order: \\ → \\\\ first to avoid double-escape,
        // then | → \|. Newline → space (V1 normalization).
        let escaped = newContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
        // Compute char delta to update the table-anchor for Tab nav.
        let delta = (escaped as NSString).length - activeCellRange.length
        let updatedFirstRowLoc = activeTableFirstRowLoc <= activeCellRange.location
            ? activeTableFirstRowLoc
            : activeTableFirstRowLoc + delta
        lastCommitAnchor = TableAnchor(tableFirstRowLoc: updatedFirstRowLoc)

        if let storage = host.textStorage {
            storage.replaceCharacters(in: activeCellRange, with: escaped)
            // Trigger production's re-render. Same path used by
            // textDidChange — keeps render logic single-sourced.
            renderHook(host)
        }
        teardown()
    }

    func cancel() { teardown() }

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

    /// Phase 4 stub. Will be expanded with full Tab cycling logic
    /// (cross-row, header exclusion, anchor-based table re-find).
    func overlayAdvanceTab(_ overlay: CellEditOverlay, backward: Bool) {
        commit()
    }
}

/// Anchor captured at commit time so post-rerender Tab navigation can
/// locate the same logical table by its first-row offset (re-render
/// destroys ObjectIdentifier-based identity for `TableLayout`).
struct TableAnchor {
    let tableFirstRowLoc: Int
}
