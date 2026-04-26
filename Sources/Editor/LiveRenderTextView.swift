import AppKit
import Foundation

/// NSTextView subclass for the live-render markdown editor.
///
/// **TextKit 1 host** as of D17. Constructed via the explicit storage
/// → layout-manager → container chain so the text view never picks up
/// `NSTextLayoutManager` (TK2). The pre-D17 standard prohibited
/// touching `.layoutManager` because that demoted us from the TK2
/// path; post-D17 the standard is inverted — we are deliberately on
/// TK1 (see `docs/current_work/specs/d17_textkit1_migration_spec.md`
/// § 2 for citations) and `.layoutManager` is the supported path.
///
/// Cell-aware behavior for table rows (Tab/Shift+Tab, Left/Right at
/// cell boundaries, Backspace at content-start) is reinstated atop
/// TK1 in D17 phase 6. The mid-flight code paths in this file that
/// reference `textLayoutManager` are leftovers from D8–D13's TK2
/// implementation; they will return nil under TK1 and silently no-op,
/// and they are removed entirely in phases 3–5.
final class LiveRenderTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    /// D17 phase 1 — designated init that builds an explicit TK1
    /// text-storage chain. Use this everywhere instead of relying on
    /// `NSTextView`'s default initializer, which on macOS 12+ may
    /// pick up `NSTextLayoutManager` (TK2).
    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        // Runtime trip wire: confirm we did not accidentally end up
        // on TK2. If this assertion fires the construction chain
        // above is wrong.
        assert(self.textLayoutManager == nil,
               "LiveRenderTextView ended up on TextKit 2 — D17 standard violated")
    }

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

    /// D15.1 scroll-jump fix: when > 0, intercept and discard internal
    /// auto-scroll-to-caret calls. NSTextView's selection-change side
    /// effects (from insertText, insertNewline, etc.) call
    /// `scrollRangeToVisible(_:)` on self. During typing the user is
    /// editing a position that is *already visible* — there is nothing
    /// to make visible. The auto-scroll only causes layout/clip-view
    /// shifts that the user sees as the editor "jumping". We honor the
    /// suppression for keyDown-induced edits and for cell-edit-overlay
    /// commits (where focus returns to the host with potentially-stale
    /// selectedRange). Cleared on the next runloop tick so explicit
    /// post-edit scrolls (D9 reveal-at-line) still work.
    var scrollSuppressionDepth: Int = 0

    override func scrollRangeToVisible(_ range: NSRange) {
        if scrollSuppressionDepth > 0 { return }
        super.scrollRangeToVisible(range)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // D15.1: TextKit 2 lazy-lays-out fragments only when their
        // region becomes visible. Fragments outside the visible area
        // can have `layoutFragmentFrame.origin = (0, 0)` (default
        // unset) until the user scrolls to them. After a scroll, the
        // newly-revealed region's fragments may be in transition —
        // some have real positions, others still have y=0. A click
        // here resolves through `tlm.textLayoutFragment(for:)`, which
        // can return a fragment whose `.origin.y` hasn't caught up,
        // and we then mount the cell-edit overlay at the stale y. The
        // root fix is to force TextKit 2 to complete layout for the
        // document range before we trust any fragment's frame for
        // click routing or overlay placement. Repro confirmed: with
        // tables outside the initial viewport, post-scroll click
        // mounts overlay at the cell's pre-scroll screen position.
        if let tlm = textLayoutManager,
           let tcm = tlm.textContentManager {
            tlm.ensureLayout(for: tcm.documentRange)
        }
        // D15.1 debug HUD — record click coords + resolved fragment
        // info into the probe (no-op when HUD disabled in settings).
        recordClickForDebugProbe(event: event)
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
        // D15.1: suppress NSTextView's internal auto-scroll-to-caret
        // for content-modifying keys. Navigation keys (arrows, page,
        // home/end) keep their natural follow-the-caret scrolling.
        let suppress = !Self.isNavigationKey(keyCode: event.keyCode)
        if suppress {
            scrollSuppressionDepth += 1
        }
        super.keyDown(with: event)
        if suppress {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollSuppressionDepth = max(0, self.scrollSuppressionDepth - 1)
            }
        }
    }

    /// keyCodes for keys that should retain NSTextView's natural
    /// auto-scroll-to-caret behavior. Everything else (printable chars,
    /// return, delete, tab, escape, etc.) gets the suppression guard.
    private static func isNavigationKey(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 123, 124, 125, 126: return true   // arrows: left, right, down, up
        case 116, 121:           return true   // page up, page down
        case 115, 119:           return true   // home, end
        default:                 return false
        }
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

    // MARK: - Debug HUD instrumentation

    /// D15.1 — feed click coords and resolved-fragment info into
    /// `DebugProbe.shared`. Cheap and side-effect-free; the HUD itself
    /// only renders when toggled on in View menu.
    private func recordClickForDebugProbe(event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerY = viewPoint.y - textContainerInset.height
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: containerY)
        var fragOriginY: CGFloat = 0
        var fragKind: String = "—"
        var tableRow: Int = -1
        var tableCol: Int = -1
        var fragmentClass: String = "—"
        if let tlm = textLayoutManager,
           let frag = tlm.textLayoutFragment(for: containerPoint) {
            fragOriginY = frag.layoutFragmentFrame.origin.y
            fragmentClass = String(describing: type(of: frag))
            if let row = frag as? TableRowFragment {
                fragKind = String(describing: row.attachment.kind)
                tableRow = row.attachment.cellContentIndex ?? -1
                let layout = row.attachment.layout
                let xInFrag = containerPoint.x
                    - frag.layoutFragmentFrame.origin.x
                for c in 0..<layout.contentWidths.count {
                    let leftEdge = layout.columnLeadingX[c] - layout.cellInset.left
                    let rightEdge = layout.columnTrailingX[c] + layout.cellInset.right
                    if xInFrag >= leftEdge && xInFrag < rightEdge {
                        tableCol = c
                        break
                    }
                }
            } else {
                fragKind = "para"
            }
        }
        let line = lineNumberForOffset(containerPoint: containerPoint)
        DebugProbe.shared.recordClick(
            viewPoint: viewPoint,
            containerY: containerY,
            line: line,
            fragKind: fragKind,
            fragOriginY: fragOriginY,
            tableRow: tableRow,
            tableCol: tableCol,
            fragmentClass: fragmentClass)
    }

    /// 1-based line number at the click point, derived by counting
    /// newlines from doc start to the resolved character offset. Slow
    /// path on long docs but cheap enough on a single click.
    private func lineNumberForOffset(containerPoint: NSPoint) -> Int {
        guard let tlm = textLayoutManager,
              let frag = tlm.textLayoutFragment(for: containerPoint),
              let tcm = tlm.textContentManager else {
            return 0
        }
        let elementRange = frag.rangeInElement
        let docStart = tcm.documentRange.location
        let offset = tlm.offset(from: docStart, to: elementRange.location)
        let source = self.string as NSString
        var line = 1
        var i = 0
        let limit = min(offset, source.length)
        while i < limit {
            if source.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }

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
