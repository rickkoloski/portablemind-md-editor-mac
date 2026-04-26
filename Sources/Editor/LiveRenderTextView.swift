import AppKit
import Foundation

/// NSTextView subclass housing our TextKit 2 live-render editor.
///
/// IMPORTANT (`docs/engineering-standards_ref.md` §2.2): never access
/// `.layoutManager` on this class or any `NSTextView`. Accessing it
/// lazy-creates a TextKit 1 manager and silently flips the code path.
///
/// D12 adds cell-aware behavior for table rows:
/// - Single-click in a cell snaps the caret to a valid in-cell offset
///   (via `snapCaretToCellContent` after the default click flow).
/// - Double-click in a cell toggles whole-row source-reveal mode
///   (replaces D8.1's caret-in-range auto-reveal).
/// - Tab / Shift+Tab cycles through cells, crossing rows at the ends.
/// - Left / Right arrow at cell-content boundaries jumps to the
///   adjacent cell (skipping pipe + whitespace source chars).
/// - Backspace at cell-content-start moves caret to the previous
///   cell's content-end (non-destructive); Delete is symmetric.
final class LiveRenderTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    /// Optional callback for the EditorContainer Coordinator to handle
    /// double-click reveal triggering. Set during view setup so this
    /// class doesn't need to know about Coordinator internals.
    var onDoubleClickRevealRequest: ((TableRowAttachment) -> Void)?

    /// D13: per-cell edit overlay controller. When set, single-click on
    /// a table cell mounts the overlay rather than placing a flat caret.
    weak var cellEditController: CellEditController?

    /// D13: modal popout controller — opened via right-click menu's
    /// "Edit Cell in Popout…" item.
    weak var cellEditModalController: CellEditModalController?

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // Double-click on a table cell → request reveal of the row's
        // table to source mode (D12 retained mechanism).
        if event.clickCount == 2,
           let tlm = textLayoutManager {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: viewPoint.x - textContainerInset.width,
                y: viewPoint.y - textContainerInset.height)
            if let frag = tlm.textLayoutFragment(for: containerPoint),
               let attachment = (frag as? TableRowFragment)?.attachment {
                onDoubleClickRevealRequest?(attachment)
                return
            }
        }
        // D13: single-click on a table cell → mount the edit overlay
        // (replaces D12's snapCaretToCellContent path). If the row is
        // in source-reveal mode (double-click triggered), or if the
        // click isn't on a TableRowFragment, fall through to default.
        if event.clickCount == 1,
           let tlm = textLayoutManager,
           let controller = cellEditController {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: viewPoint.x - textContainerInset.width,
                y: viewPoint.y - textContainerInset.height)
            if let frag = tlm.textLayoutFragment(for: containerPoint),
               let row = frag as? TableRowFragment,
               !isRowRevealed(row.attachment, in: tlm),
               row.attachment.kind != .separator,
               let cci = row.attachment.cellContentIndex,
               cci < row.attachment.layout.cellContentPerRow.count {
                showOverlay(for: row, at: containerPoint,
                            controller: controller, tlm: tlm)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func isRowRevealed(_ attachment: TableRowAttachment,
                               in tlm: NSTextLayoutManager) -> Bool {
        guard let delegate = tlm.delegate as? TableLayoutManagerDelegate else {
            return false
        }
        return delegate.revealedTables.contains(ObjectIdentifier(attachment.layout))
    }

    /// Compute column from click x within the fragment, run click-to-caret
    /// math (Phase 1 cellLocalCaretIndex), find the row's source range,
    /// hand all of it to the controller.
    private func showOverlay(for row: TableRowFragment,
                             at containerPoint: NSPoint,
                             controller: CellEditController,
                             tlm: NSTextLayoutManager) {
        let layout = row.attachment.layout
        guard let cci = row.attachment.cellContentIndex else { return }
        let frag = row
        let fragFrame = frag.layoutFragmentFrame
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
        guard colIdx >= 0 else { return }

        // Phase 1 click-to-caret math.
        let cellContentOriginX = fragFrame.origin.x + layout.columnLeadingX[colIdx]
        let cellContentOriginY = fragFrame.origin.y + layout.cellInset.top
        let relX = containerPoint.x - cellContentOriginX
        let relY = containerPoint.y - cellContentOriginY
        let localCaretIndex = layout.cellLocalCaretIndex(
            rowIdx: cci, colIdx: colIdx, relX: relX, relY: relY)

        // Compute the row's source range from the fragment's element range.
        guard let element = frag.textElement,
              let textRange = element.elementRange,
              let docStart = tlm.textContentManager?.documentRange.location else {
            return
        }
        let rowLoc = tlm.offset(from: docStart, to: textRange.location)
        let rowLen = tlm.offset(from: textRange.location, to: textRange.endLocation)
        let rowSourceRange = NSRange(location: rowLoc, length: rowLen)

        controller.showOverlay(
            attachment: row.attachment,
            rowIdx: cci, colIdx: colIdx,
            tableRowSourceRange: rowSourceRange,
            localCaretIndex: localCaretIndex,
            fragmentFrame: fragFrame)
    }

    // MARK: - Key navigation

    override func keyDown(with event: NSEvent) {
        // TEST-HARNESS: temporary log to verify cell-aware nav fires.
        #if DEBUG
        let rowFound = currentTableRow() != nil
        NSLog("[CELL-NAV] keyDown keyCode=\(event.keyCode) sel=\(selectedRange().location) inRow=\(rowFound)")
        #endif
        // Cell-aware navigation runs first; if it consumes the event,
        // we don't fall through to KeyboardBindings or super.
        if selectedRange().length == 0,
           let row = currentTableRow() {
            switch event.keyCode {
            case Self.keyTab:
                handleTab(in: row,
                          shift: event.modifierFlags.contains(.shift))
                return
            case Self.keyLeft:
                if handleLeftArrow(in: row) { return }
            case Self.keyRight:
                if handleRightArrow(in: row) { return }
            default:
                break
            }
        }
        if let binding = KeyboardBindings.match(event: event),
           CommandDispatcher.shared.dispatch(
            identifier: binding.commandIdentifier, in: self) {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Delete

    /// Backspace at a cell-content-start moves caret to previous cell's
    /// content-end (same row, or previous row's last cell if at first
    /// cell of the row). Non-destructive cell-boundary crossing.
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0,
           let row = currentTableRow(),
           !row.cells.isEmpty {
            // At any cell's content-start?
            if let atStartIdx = row.cells.firstIndex(
                where: { $0.location == sel.location }) {
                if atStartIdx > 0 {
                    let prev = row.cells[atStartIdx - 1]
                    setSelectedRange(NSRange(
                        location: prev.location + prev.length, length: 0))
                    return
                }
                // First cell of the row → previous row's last cell end.
                if let prevRow = previousTableRow(before: row.range.location),
                   let prevLast = prevRow.cells.last {
                    setSelectedRange(NSRange(
                        location: prevLast.location + prevLast.length,
                        length: 0))
                    return
                }
                // No previous row → ignore (don't delete the leading pipe).
                return
            }
        }
        super.deleteBackward(sender)
    }

    /// Delete at a cell-content-end moves caret to the next cell's
    /// content-start (same row, or next row's first cell if at last
    /// cell of the row). Non-destructive symmetric counterpart.
    override func deleteForward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0,
           let row = currentTableRow(),
           !row.cells.isEmpty {
            if let atEndIdx = row.cells.firstIndex(
                where: { $0.location + $0.length == sel.location }) {
                if atEndIdx + 1 < row.cells.count {
                    let next = row.cells[atEndIdx + 1]
                    setSelectedRange(NSRange(
                        location: next.location, length: 0))
                    return
                }
                if let nextRow = nextTableRow(after: row.range.location + row.range.length),
                   let nextFirst = nextRow.cells.first {
                    setSelectedRange(NSRange(
                        location: nextFirst.location, length: 0))
                    return
                }
                return
            }
        }
        super.deleteForward(sender)
    }

    // MARK: - Cell-nav handlers

    private struct TableRowInfo {
        let attachment: TableRowAttachment
        let range: NSRange    // source range of the row's line
        let cells: [NSRange]
    }

    private func handleTab(in row: TableRowInfo, shift: Bool) {
        let loc = selectedRange().location
        // Find which cell contains (or precedes) the caret.
        let curIdx = row.cells.firstIndex(where: { cell in
            loc >= cell.location && loc <= cell.location + cell.length
        }) ?? 0
        let target: Int
        if shift {
            if curIdx > 0 {
                let prev = row.cells[curIdx - 1]
                target = prev.location + prev.length
            } else if let prevRow = previousTableRow(before: row.range.location),
                      let prevLast = prevRow.cells.last {
                target = prevLast.location + prevLast.length
            } else {
                target = row.cells[0].location
            }
        } else {
            if curIdx + 1 < row.cells.count {
                target = row.cells[curIdx + 1].location
            } else if let nextRow = nextTableRow(
                after: row.range.location + row.range.length),
                      let nextFirst = nextRow.cells.first {
                target = nextFirst.location
            } else {
                let last = row.cells[row.cells.count - 1]
                target = last.location + last.length
            }
        }
        setSelectedRange(NSRange(location: target, length: 0))
    }

    /// Returns true if the arrow key was consumed by cell-nav.
    private func handleLeftArrow(in row: TableRowInfo) -> Bool {
        let loc = selectedRange().location
        for (idx, cell) in row.cells.enumerated() where loc == cell.location {
            if idx > 0 {
                let prev = row.cells[idx - 1]
                setSelectedRange(NSRange(
                    location: prev.location + prev.length, length: 0))
                return true
            }
            // First cell of row → previous row's last cell end.
            if let prevRow = previousTableRow(before: row.range.location),
               let prevLast = prevRow.cells.last {
                setSelectedRange(NSRange(
                    location: prevLast.location + prevLast.length, length: 0))
                return true
            }
            return true   // boundary; consume so caret doesn't escape into pipes
        }
        return false
    }

    private func handleRightArrow(in row: TableRowInfo) -> Bool {
        let loc = selectedRange().location
        for (idx, cell) in row.cells.enumerated() {
            let cellEnd = cell.location + cell.length
            guard loc == cellEnd else { continue }
            if idx + 1 < row.cells.count {
                let next = row.cells[idx + 1]
                setSelectedRange(NSRange(
                    location: next.location, length: 0))
                return true
            }
            if let nextRow = nextTableRow(after: row.range.location + row.range.length),
               let nextFirst = nextRow.cells.first {
                setSelectedRange(NSRange(
                    location: nextFirst.location, length: 0))
                return true
            }
            return true
        }
        return false
    }

    // MARK: - Row discovery
    //
    // D12's `snapCaretToCellContent` was removed in D13 — the cell-edit
    // overlay path replaces it. Single-click in a cell now mounts the
    // overlay; clicks outside cells go through default NSTextView
    // handling.

    /// Build a TableRowInfo for the row currently containing the caret,
    /// or nil if the caret isn't inside a body / header table row.
    private func currentTableRow() -> TableRowInfo? {
        guard let storage = textStorage,
              storage.length > 0 else { return nil }
        let probe = max(0, min(selectedRange().location, storage.length - 1))
        guard let attachment = storage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: probe,
                effectiveRange: nil) as? TableRowAttachment,
              attachment.kind != .separator,
              let rowIdx = attachment.cellContentIndex,
              rowIdx < attachment.layout.cellRanges.count
        else { return nil }
        let rowRange = sourceRange(forAttachment: attachment, near: probe,
                                   in: storage)
        return TableRowInfo(
            attachment: attachment,
            range: rowRange,
            cells: attachment.layout.cellRanges[rowIdx])
    }

    /// Find the source-range bounds of the run of characters tagged
    /// with the same TableRowAttachment instance as `near`.
    private func sourceRange(forAttachment attachment: TableRowAttachment,
                             near probe: Int,
                             in storage: NSTextStorage) -> NSRange {
        let pivotID = ObjectIdentifier(attachment)
        var lo = probe
        while lo > 0,
              let prev = storage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: lo - 1,
                effectiveRange: nil) as? TableRowAttachment,
              ObjectIdentifier(prev) == pivotID {
            lo -= 1
        }
        var hi = probe
        while hi < storage.length - 1,
              let next = storage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: hi + 1,
                effectiveRange: nil) as? TableRowAttachment,
              ObjectIdentifier(next) == pivotID {
            hi += 1
        }
        return NSRange(location: lo, length: hi - lo + 1)
    }

    /// Find the next body/header row starting at or after `offset`.
    private func nextTableRow(after offset: Int) -> TableRowInfo? {
        guard let storage = textStorage else { return nil }
        var i = offset
        while i < storage.length {
            if let attachment = storage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: i,
                effectiveRange: nil) as? TableRowAttachment,
               attachment.kind != .separator,
               let rowIdx = attachment.cellContentIndex,
               rowIdx < attachment.layout.cellRanges.count {
                let r = sourceRange(forAttachment: attachment,
                                    near: i, in: storage)
                return TableRowInfo(
                    attachment: attachment,
                    range: r,
                    cells: attachment.layout.cellRanges[rowIdx])
            }
            i += 1
        }
        return nil
    }

    /// Find the previous body/header row ending at or before `offset`.
    private func previousTableRow(before offset: Int) -> TableRowInfo? {
        guard let storage = textStorage else { return nil }
        var i = offset - 1
        while i >= 0 {
            if let attachment = storage.attribute(
                TableAttributeKeys.rowAttachmentKey,
                at: i,
                effectiveRange: nil) as? TableRowAttachment,
               attachment.kind != .separator,
               let rowIdx = attachment.cellContentIndex,
               rowIdx < attachment.layout.cellRanges.count {
                let r = sourceRange(forAttachment: attachment,
                                    near: i, in: storage)
                return TableRowInfo(
                    attachment: attachment,
                    range: r,
                    cells: attachment.layout.cellRanges[rowIdx])
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Constants

    private static let keyTab: UInt16 = 48
    private static let keyLeft: UInt16 = 123
    private static let keyRight: UInt16 = 124

    // MARK: - Right-click menu (D13 §3.12 modal popout)

    /// Add an "Edit Cell in Popout…" item to the contextual menu when
    /// the click was on a table cell. Suppress the item when an
    /// overlay is already active on the SAME cell (spec §3.13 row 3).
    override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event) ?? NSMenu()
        guard let tlm = textLayoutManager else { return baseMenu }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height)
        guard let frag = tlm.textLayoutFragment(for: containerPoint),
              let row = frag as? TableRowFragment,
              row.attachment.kind != .separator,
              let cci = row.attachment.cellContentIndex,
              cci < row.attachment.layout.cellRanges.count else {
            return baseMenu
        }

        // Locate column from x.
        let layout = row.attachment.layout
        let xInFrag = containerPoint.x - frag.layoutFragmentFrame.origin.x
        var colIdx = -1
        for c in 0..<layout.contentWidths.count {
            let leftEdge = layout.columnLeadingX[c] - layout.cellInset.left
            let rightEdge = layout.columnTrailingX[c] + layout.cellInset.right
            if xInFrag >= leftEdge && xInFrag < rightEdge {
                colIdx = c
                break
            }
        }
        guard colIdx >= 0 else { return baseMenu }

        // §3.13 row 3: omit the popout item if the overlay is already
        // active on this exact cell — user must commit / cancel first.
        if let controller = cellEditController,
           controller.isActive,
           controller.activeRow == cci,
           controller.activeCol == colIdx {
            return baseMenu
        }

        let item = NSMenuItem(
            title: "Edit Cell in Popout…",
            action: #selector(editCellInPopoutAction(_:)),
            keyEquivalent: "")
        item.target = self
        // Stash the (rowIdx, colIdx, cellRange) so the action can
        // open the modal without recomputing geometry.
        item.representedObject = CellMenuTarget(
            rowIdx: cci, colIdx: colIdx,
            cellRange: layout.cellRanges[cci][colIdx],
            attachment: row.attachment)
        baseMenu.insertItem(item, at: 0)
        baseMenu.insertItem(.separator(), at: 1)
        return baseMenu
    }

    @objc func editCellInPopoutAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? CellMenuTarget,
              let modal = cellEditModalController else { return }
        // §3.13 row 2: commit any active overlay on a different cell first.
        if let controller = cellEditController, controller.isActive {
            controller.commit()
        }
        let cellSource = (string as NSString).substring(with: target.cellRange)
        let rowLabel = "Row \(target.rowIdx)"
        let colLabel = "Col \(target.colIdx + 1)"
        modal.openModal(
            forCellRange: target.cellRange,
            originalContent: cellSource,
            rowLabel: rowLabel,
            colLabel: colLabel)
    }
}

/// Carry data through the right-click menu action.
private final class CellMenuTarget: NSObject {
    let rowIdx: Int
    let colIdx: Int
    let cellRange: NSRange
    let attachment: TableRowAttachment
    init(rowIdx: Int, colIdx: Int, cellRange: NSRange,
         attachment: TableRowAttachment) {
        self.rowIdx = rowIdx
        self.colIdx = colIdx
        self.cellRange = cellRange
        self.attachment = attachment
        super.init()
    }
}
