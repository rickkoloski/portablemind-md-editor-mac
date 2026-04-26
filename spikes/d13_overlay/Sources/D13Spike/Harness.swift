// TEST-HARNESS: file-based command poller. Mirrors the D12 spike's
// pattern, retargeted to /tmp/d13-command.json. Writes results to
// /tmp/d13-state.json and snapshots to /tmp/d13-shot.png.
//
// Drives the spike from outside the process (no Accessibility prompts,
// no synthetic input required for state inspection). cliclick + osascript
// drive synthetic clicks/keys; the harness here drives state inspection
// and programmatic mutations.

import AppKit
import Foundation

final class HarnessCommandPoller {
    static let shared = HarnessCommandPoller()
    private let commandPath = "/tmp/d13-command.json"
    private let statePath = "/tmp/d13-state.json"
    private let shotPath = "/tmp/d13-shot.png"
    private let windowPath = "/tmp/d13-window.json"
    private let cellsPath = "/tmp/d13-cells.json"

    weak var window: NSWindow?
    weak var textView: NSTextView?
    weak var cellEditController: CellEditController?

    private var timer: Timer?

    func start(window: NSWindow, textView: NSTextView) {
        self.window = window
        self.textView = textView
        // Ensure no stale command file is processed at startup.
        try? FileManager.default.removeItem(atPath: commandPath)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        spikeLog("harness started")
    }

    private func tick() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: commandPath)) else {
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            try? FileManager.default.removeItem(atPath: commandPath)
            return
        }
        try? FileManager.default.removeItem(atPath: commandPath)
        spikeLog("harness action: \(action)")

        switch action {
        case "dump_state":
            writeState()
        case "snapshot":
            writeSnapshot()
        case "window_info":
            writeWindowInfo()
        case "cell_screen_rects":
            writeCellScreenRects()
        case "set_text":
            if let s = obj["text"] as? String { setText(s) }
        case "reset_text":
            setText(seedSource)
        case "set_selection":
            if let loc = obj["location"] as? Int {
                let len = (obj["length"] as? Int) ?? 0
                setSelection(loc, len)
            }
        case "commit_overlay":
            cellEditController?.commit()
        case "cancel_overlay":
            cellEditController?.cancel()
        case "advance_overlay_tab":
            let backward = (obj["backward"] as? Bool) ?? false
            advanceOverlayTab(backward: backward)
        case "type_in_overlay":
            if let s = obj["text"] as? String { typeInOverlay(s) }
        case "show_overlay_at_table_cell":
            if let table = obj["table"] as? Int,
               let row = obj["row"] as? Int,
               let col = obj["col"] as? Int {
                let initialCaret = obj["caret"] as? Int
                showOverlayAtTableCell(tableIndex: table, rowIdx: row, colIdx: col,
                                       initialCaret: initialCaret)
            }
        case "query_caret_for_click":
            if let table = obj["table"] as? Int,
               let row = obj["row"] as? Int,
               let col = obj["col"] as? Int,
               let relX = obj["relX"] as? Double,
               let relY = obj["relY"] as? Double {
                queryCaretForClick(tableIndex: table, rowIdx: row, colIdx: col,
                                   relX: CGFloat(relX), relY: CGFloat(relY))
            }
        default:
            spikeLog("harness: unknown action \(action)")
        }
    }

    private func writeState() {
        guard let tv = textView else { return }
        var sel: [Int] = [0, 0]
        if let r = tv.selectedRanges.first as? NSRange {
            sel = [r.location, r.length]
        }
        var overlayInfo: [String: Any] = ["active": false]
        if let c = cellEditController, c.isActive {
            overlayInfo = [
                "active": true,
                "row": c.activeRow,
                "col": c.activeCol,
                "cellRangeLocation": c.activeCellRange.location,
                "cellRangeLength": c.activeCellRange.length
            ]
        }
        let payload: [String: Any] = [
            "source": tv.string,
            "selection": sel,
            "windowFrame": frameDict(window?.frame ?? .zero),
            "overlay": overlayInfo
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted]) {
            atomicWrite(data, to: statePath)
        }
    }

    private func writeSnapshot() {
        guard let win = window, let cv = win.contentView else { return }
        DispatchQueue.main.async {
            let bounds = cv.bounds
            guard let rep = cv.bitmapImageRepForCachingDisplay(in: bounds) else { return }
            cv.cacheDisplay(in: bounds, to: rep)
            let img = NSImage(size: bounds.size)
            img.addRepresentation(rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                self.atomicWrite(png, to: self.shotPath)
                spikeLog("snapshot written \(png.count) bytes")
            }
        }
    }

    private func writeWindowInfo() {
        guard let win = window else { return }
        let payload: [String: Any] = [
            "window": frameDict(win.frame),
            "screen": win.screen.map { frameDict($0.frame) } ?? [:],
            "isVisible": win.isVisible,
            "isOnScreen": win.isOnActiveSpace
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted]) {
            atomicWrite(data, to: windowPath)
        }
    }

    private func writeCellScreenRects() {
        // Stub for Tier 1+. Will populate cell screen rects via the
        // text view's layout manager once table rendering is verified.
        let payload: [String: Any] = ["note": "not yet implemented"]
        if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted]) {
            atomicWrite(data, to: cellsPath)
        }
    }

    private func setText(_ s: String) {
        guard let tv = textView else { return }
        tv.string = s
        if let storage = tv.textStorage {
            SpikeRenderer.render(into: storage)
        }
    }

    /// Walk text storage attributes to find the Nth distinct TableLayout
    /// (table 0 = first table in document order). Within that layout,
    /// pick the row at rowIdx (header=0, body=1, 2, ...) and call
    /// CellEditController.showOverlay with the right parameters.
    /// Look up table layout (without showing overlay) and return the
    /// computed local caret index for a click at (relX, relY) in
    /// cell-content-local coords. Result written to /tmp/d13-caret.json.
    private func queryCaretForClick(tableIndex: Int, rowIdx: Int, colIdx: Int,
                                    relX: CGFloat, relY: CGFloat) {
        guard let layoutAndRowIdx = findLayoutAndCellRow(tableIndex: tableIndex, rowIdx: rowIdx) else {
            spikeLog("query_caret_for_click: no layout/row found")
            return
        }
        let (layout, cci) = layoutAndRowIdx
        let idx = layout.cellLocalCaretIndex(rowIdx: cci, colIdx: colIdx,
                                             relX: relX, relY: relY)
        let cellContent = (cci < layout.cellContentPerRow.count && colIdx < layout.cellContentPerRow[cci].count)
            ? layout.cellContentPerRow[cci][colIdx].string
            : ""
        let payload: [String: Any] = [
            "tableIndex": tableIndex, "rowIdx": rowIdx, "colIdx": colIdx,
            "relX": Double(relX), "relY": Double(relY),
            "localCaretIndex": idx,
            "cellContent": cellContent,
            "cellContentLength": cellContent.count
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            atomicWrite(data, to: "/tmp/d13-caret.json")
        }
        spikeLog("query_caret_for_click: tIdx=\(tableIndex) row=\(rowIdx) col=\(colIdx) rel=(\(relX),\(relY)) → \(idx)")
    }

    /// Helper used by both query_caret_for_click and show_overlay_at_table_cell.
    private func findLayoutAndCellRow(tableIndex: Int, rowIdx: Int) -> (TableLayout, Int)? {
        guard let storage = textView?.textStorage else { return nil }
        var rows: [(NSRange, TableRowAttachment)] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(SpikeAttributeKeys.rowAttachmentKey,
                                   in: full, options: []) { value, range, _ in
            if let att = value as? TableRowAttachment {
                rows.append((range, att))
            }
        }
        var layoutOrder: [ObjectIdentifier] = []
        var rowsByLayout: [ObjectIdentifier: [(NSRange, TableRowAttachment)]] = [:]
        for r in rows {
            let id = ObjectIdentifier(r.1.layout)
            if rowsByLayout[id] == nil {
                layoutOrder.append(id)
                rowsByLayout[id] = []
            }
            rowsByLayout[id]?.append(r)
        }
        guard tableIndex < layoutOrder.count else { return nil }
        let id = layoutOrder[tableIndex]
        let layoutRows = (rowsByLayout[id] ?? []).filter { $0.1.kind != .separator }
        guard rowIdx < layoutRows.count,
              let cci = layoutRows[rowIdx].1.cellContentIndex else { return nil }
        return (layoutRows[rowIdx].1.layout, cci)
    }

    private func showOverlayAtTableCell(tableIndex: Int, rowIdx: Int, colIdx: Int,
                                        initialCaret: Int? = nil) {
        guard let tv = textView,
              let storage = tv.textStorage,
              let tlm = tv.textLayoutManager,
              let controller = cellEditController else { return }

        // Collect (rowSourceRange, attachment) for every row in document order.
        var rows: [(NSRange, TableRowAttachment)] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(SpikeAttributeKeys.rowAttachmentKey,
                                   in: full,
                                   options: []) { value, range, _ in
            if let att = value as? TableRowAttachment {
                rows.append((range, att))
            }
        }

        // Group rows by layout (ObjectIdentifier of layout instance).
        var layoutOrder: [ObjectIdentifier] = []
        var rowsByLayout: [ObjectIdentifier: [(NSRange, TableRowAttachment)]] = [:]
        for r in rows {
            let id = ObjectIdentifier(r.1.layout)
            if rowsByLayout[id] == nil {
                layoutOrder.append(id)
                rowsByLayout[id] = []
            }
            rowsByLayout[id]?.append(r)
        }

        guard tableIndex < layoutOrder.count else {
            spikeLog("show_overlay_at_table_cell: tableIndex \(tableIndex) out of range")
            return
        }
        let id = layoutOrder[tableIndex]
        let layoutRows = rowsByLayout[id] ?? []
        // Skip separator row (kind == .separator).
        let nonSepRows = layoutRows.filter { $0.1.kind != .separator }
        guard rowIdx < nonSepRows.count else {
            spikeLog("show_overlay_at_table_cell: rowIdx \(rowIdx) out of range (have \(nonSepRows.count))")
            return
        }
        let (rowRange, attachment) = nonSepRows[rowIdx]
        guard let cci = attachment.cellContentIndex else { return }

        // Find the layout fragment for that row.
        guard let docStart = tlm.textContentManager?.documentRange.location else { return }
        guard let rowStart = tlm.location(docStart, offsetBy: rowRange.location) else { return }
        guard let frag = tlm.textLayoutFragment(for: rowStart) else {
            spikeLog("show_overlay_at_table_cell: no fragment at row")
            return
        }

        controller.showOverlay(
            attachment: attachment,
            rowIdx: cci,
            colIdx: colIdx,
            tableRowSourceRange: rowRange,
            localCaretIndex: initialCaret ?? 0,
            fragmentFrame: frag.layoutFragmentFrame)
    }

    private func advanceOverlayTab(backward: Bool) {
        guard let controller = cellEditController, controller.isActive,
              let host = textView,
              let ov = host.subviews.compactMap({ $0 as? CellEditOverlay }).first
        else { return }
        controller.overlayAdvanceTab(ov, backward: backward)
    }

    private func typeInOverlay(_ s: String) {
        guard let controller = cellEditController, controller.isActive else { return }
        // Insert text at current selection in the overlay.
        // Find the overlay subview to type into.
        if let host = textView,
           let ov = host.subviews.compactMap({ $0 as? CellEditOverlay }).first {
            ov.insertText(s, replacementRange: ov.selectedRange())
        }
    }

    private func setSelection(_ loc: Int, _ len: Int) {
        guard let tv = textView else { return }
        let safeLoc = max(0, min(loc, tv.string.count))
        let safeLen = max(0, min(len, tv.string.count - safeLoc))
        tv.setSelectedRange(NSRange(location: safeLoc, length: safeLen))
    }

    private func atomicWrite(_ data: Data, to path: String) {
        let tmp = path + ".tmp"
        try? data.write(to: URL(fileURLWithPath: tmp))
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    private func frameDict(_ rect: CGRect) -> [String: CGFloat] {
        ["x": rect.origin.x, "y": rect.origin.y,
         "width": rect.size.width, "height": rect.size.height]
    }
}
