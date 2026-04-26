// TEST-HARNESS: Debug-only command-file poller. Search the codebase
// for `TEST-HARNESS:` to find every accommodation made for autonomous
// testing. Strip these by deleting the marked blocks if/when the
// harness is no longer needed.
//
// External drivers write JSON action files to /tmp/mdeditor-command.json;
// this class polls that file every 200ms, executes the action against
// the active text view (via HarnessActiveSink), and writes results to
// known paths under /tmp.
//
// Supported actions (extensible — add cases as testing surfaces new
// inspection needs):
//   {"action":"dump_state",      "path":"/tmp/mdeditor-state.json"}
//   {"action":"snapshot",        "path":"/tmp/mdeditor-shot.png"}
//   {"action":"window_info",     "path":"/tmp/mdeditor-window.json"}
//   {"action":"set_text",        "text":"..."}
//   {"action":"reset_text"}
//   {"action":"set_selection",   "location":N, "length":M}
//   {"action":"scroll_info",     "path":"/tmp/mdeditor-scroll.json"}
//   {"action":"set_scroll",      "y":F}
//   {"action":"insert_text",     "text":"...", "atSelection":true}
//
// D14 actions:
//   {"action":"save_focused_doc"}      // → focused doc's url
//   {"action":"save_as_focused_doc",   "newURL":"/path/to/new"}
//   {"action":"focused_doc_info",      "path":"/tmp/mdeditor-doc.json"}
//
// D13 actions:
//   {"action":"query_caret_for_click", "table":N, "row":N, "col":N,
//                                      "relX":F, "relY":F,
//                                      "path":"/tmp/mdeditor-caret.json"}
//   {"action":"show_overlay_at_table_cell", "table":N, "row":N, "col":N,
//                                           "caret":N (optional)}
//   {"action":"type_in_overlay",   "text":"..."}
//   {"action":"set_overlay_text",  "text":"..."}
//   {"action":"commit_overlay"}
//   {"action":"cancel_overlay"}
//   {"action":"simulate_click_at_table_cell", "table":N, "row":N, "col":N,
//                                              "relX":F, "relY":F}
//   {"action":"open_modal_at_table_cell", "table":N, "row":N, "col":N}
//   {"action":"set_modal_text",  "text":"..."}
//   {"action":"commit_modal"}
//   {"action":"cancel_modal"}
//
// Atomic file writes are required when the driver uses this poller —
// we read once per tick and silently drop on JSON-parse fail (mirrors
// the spike's poller behavior). Use mv-from-.tmp on the driver side.

#if DEBUG

import AppKit
import Foundation

@MainActor
final class HarnessCommandPoller {
    static let shared = HarnessCommandPoller()

    private let commandPath = "/tmp/mdeditor-command.json"
    private var timer: Timer?
    private var started = false

    /// D13 — set by EditorContainer.Coordinator at editor creation so
    /// harness actions can drive overlay show/commit/cancel directly.
    weak var cellEditController: CellEditController?
    /// D13 — modal popout controller for right-click testing.
    weak var cellEditModalController: CellEditModalController?

    private init() {}

    /// Idempotent — start() is safe to call repeatedly. First call
    /// installs a 200ms timer; subsequent calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NSLog("[TEST-HARNESS] poller started; watching \(commandPath)")
    }

    private func tick() {
        guard FileManager.default.fileExists(atPath: commandPath) else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: commandPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            try? FileManager.default.removeItem(atPath: commandPath)
            return
        }
        NSLog("[TEST-HARNESS] action=\(action)")
        dispatch(action: action, params: obj)
        // Remove AFTER dispatch so external drivers can use the command
        // file's disappearance as a synchronization signal: file gone =
        // command processed AND result file written. All dispatch
        // handlers are synchronous (no async hops inside), so this is
        // safe. (D14/D15 contract — 2026-04-26.)
        try? FileManager.default.removeItem(atPath: commandPath)
    }

    private func dispatch(action: String, params: [String: Any]) {
        switch action {
        case "dump_state":
            writeStateDump(to: params["path"] as? String
                ?? "/tmp/mdeditor-state.json")
        case "snapshot":
            writeSnapshot(to: params["path"] as? String
                ?? "/tmp/mdeditor-shot.png")
        case "window_info":
            writeWindowInfo(to: params["path"] as? String
                ?? "/tmp/mdeditor-window.json")
        case "set_text":
            if let text = params["text"] as? String,
               let tv = HarnessActiveSink.shared.activeTextView {
                tv.string = text
                NSLog("[TEST-HARNESS] set_text → \(text.count) chars")
            }
        case "reset_text":
            // Convention: send an empty string to clear; callers that
            // want a specific reset should use set_text.
            if let tv = HarnessActiveSink.shared.activeTextView {
                tv.string = ""
            }
        case "set_selection":
            if let loc = params["location"] as? Int,
               let tv = HarnessActiveSink.shared.activeTextView {
                let len = params["length"] as? Int ?? 0
                tv.setSelectedRange(NSRange(location: loc, length: len))
            }
        case "scroll_info":
            writeScrollInfo(to: params["path"] as? String
                ?? "/tmp/mdeditor-scroll.json")
        case "set_scroll":
            if let tv = HarnessActiveSink.shared.activeTextView,
               let scrollView = tv.enclosingScrollView {
                let y = (params["y"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["y"] as? Int) ?? 0)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        case "insert_text":
            if let text = params["text"] as? String,
               let tv = HarnessActiveSink.shared.activeTextView {
                tv.insertText(text, replacementRange: tv.selectedRange())
            }
        case "save_focused_doc":
            saveFocusedDoc(to: params["path"] as? String
                ?? "/tmp/mdeditor-save-result.json")
        case "save_as_focused_doc":
            if let newURL = params["newURL"] as? String {
                saveAsFocusedDoc(newURLPath: newURL,
                                 resultPath: params["path"] as? String
                                    ?? "/tmp/mdeditor-save-result.json")
            }
        case "focused_doc_info":
            writeFocusedDocInfo(to: params["path"] as? String
                ?? "/tmp/mdeditor-doc.json")
        case "show_overlay_at_table_cell":
            if let tableIdx = params["table"] as? Int,
               let row = params["row"] as? Int,
               let col = params["col"] as? Int {
                let caret = params["caret"] as? Int
                showOverlayAtTableCell(tableIndex: tableIdx,
                                       rowIdx: row, colIdx: col,
                                       initialCaret: caret)
            }
        case "type_in_overlay":
            if let text = params["text"] as? String {
                typeInOverlay(text)
            }
        case "set_overlay_text":
            if let text = params["text"] as? String {
                setOverlayText(text)
            }
        case "commit_overlay":
            cellEditController?.commit()
        case "cancel_overlay":
            cellEditController?.cancel()
        case "open_modal_at_table_cell":
            if let tableIdx = params["table"] as? Int,
               let row = params["row"] as? Int,
               let col = params["col"] as? Int {
                openModalAtTableCell(tableIndex: tableIdx,
                                     rowIdx: row, colIdx: col)
            }
        case "set_modal_text":
            if let text = params["text"] as? String,
               let modal = cellEditModalController, modal.isActive {
                setModalText(text)
            }
        case "commit_modal":
            commitModal()
        case "cancel_modal":
            cancelModal()
        case "advance_overlay_tab":
            let backward = (params["backward"] as? Bool) ?? false
            advanceOverlayTab(backward: backward)
        case "simulate_click_at_table_cell":
            // D13 Phase 3 — simulate a real mouseDown on the cell at
            // (table, row, col) at cell-content-local (relX, relY).
            // Drives the production mouseDown path end-to-end without
            // synthetic mouse events.
            if let tableIdx = params["table"] as? Int,
               let row = params["row"] as? Int,
               let col = params["col"] as? Int {
                let relX = (params["relX"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["relX"] as? Int) ?? 0)
                let relY = (params["relY"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["relY"] as? Int) ?? 0)
                simulateClickAtTableCell(
                    tableIndex: tableIdx, rowIdx: row, colIdx: col,
                    relX: relX, relY: relY)
            }
        case "query_caret_for_click":
            // D13 Phase 1 — exercise TableLayout.cellLocalCaretIndex
            // without needing a full overlay mount.
            if let tableIndex = params["table"] as? Int,
               let row = params["row"] as? Int,
               let col = params["col"] as? Int {
                let relX = (params["relX"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["relX"] as? Int) ?? 0)
                let relY = (params["relY"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["relY"] as? Int) ?? 0)
                let path = (params["path"] as? String)
                    ?? "/tmp/mdeditor-caret.json"
                queryCaretForClick(tableIndex: tableIndex,
                                   rowIdx: row, colIdx: col,
                                   relX: relX, relY: relY,
                                   to: path)
            }
        default:
            NSLog("[TEST-HARNESS] unknown action: \(action)")
        }
    }

    // MARK: - Action implementations

    private func writeStateDump(to path: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView else {
            try? Data("{\"error\":\"no active text view\"}".utf8)
                .write(to: URL(fileURLWithPath: path))
            return
        }
        let source = tv.string
        let sel = tv.selectedRange()
        var payload: [String: Any] = [
            "source": source,
            "sourceLength": (source as NSString).length,
            "selection": ["location": sel.location, "length": sel.length]
        ]
        // D13: surface overlay state so harness tests can verify
        // show / commit / cancel lifecycle.
        if let controller = cellEditController, controller.isActive {
            payload["overlay"] = [
                "active": true,
                "row": controller.activeRow,
                "col": controller.activeCol,
                "cellRangeLocation": controller.activeCellRange.location,
                "cellRangeLength": controller.activeCellRange.length
            ]
        } else {
            payload["overlay"] = ["active": false]
        }
        // D13 Phase 5: surface modal state.
        if let modal = cellEditModalController, modal.isActive {
            payload["modal"] = ["active": true]
        } else {
            payload["modal"] = ["active": false]
        }
        if let frame = tv.window?.frame {
            payload["windowFrame"] = [
                "x": frame.origin.x, "y": frame.origin.y,
                "w": frame.width, "h": frame.height
            ]
        }

        // D12 — surface table structure for any TableLayouts present in
        // the storage. Walks unique TableLayout instances so we report
        // each table once with its full cellRanges + tableRange.
        if let storage = tv.textStorage {
            var seenLayouts: Set<ObjectIdentifier> = []
            var tables: [[String: Any]] = []
            storage.enumerateAttribute(
                TableAttributeKeys.rowAttachmentKey,
                in: NSRange(location: 0, length: storage.length),
                options: []
            ) { value, _, _ in
                guard let attachment = value as? TableRowAttachment else { return }
                let id = ObjectIdentifier(attachment.layout)
                guard !seenLayouts.contains(id) else { return }
                seenLayouts.insert(id)
                let layout = attachment.layout
                let cellRangesPayload: [[[String: Int]]] =
                    layout.cellRanges.map { row in
                        row.map { ["location": $0.location, "length": $0.length] }
                    }
                tables.append([
                    "tableRange": [
                        "location": layout.tableRange.location,
                        "length": layout.tableRange.length
                    ],
                    "columnCount": layout.columnCount,
                    "cellRanges": cellRangesPayload
                ])
            }
            if !tables.isEmpty {
                payload["tables"] = tables
            }
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("[TEST-HARNESS] state → \(path) (\(data.count) bytes)")
        }
    }

    private func writeSnapshot(to path: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let window = tv.window,
              let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        NSLog("[TEST-HARNESS] snapshot → \(path) (\(data.count) bytes)")
    }

    /// D13 Phase 2 — programmatically mount the overlay on the
    /// (tableIndex, rowIdx, colIdx) cell. Bypasses screen-coord math
    /// so harness tests don't depend on synthetic clicks.
    private func showOverlayAtTableCell(tableIndex: Int, rowIdx: Int,
                                        colIdx: Int, initialCaret: Int?) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let storage = tv.textStorage,
              let tlm = tv.textLayoutManager,
              let controller = cellEditController else { return }
        // Walk unique TableLayouts in document order, retain row attachments.
        var layoutsByOrder: [(ObjectIdentifier, TableLayout, [(NSRange, TableRowAttachment)])] = []
        storage.enumerateAttribute(
            TableAttributeKeys.rowAttachmentKey,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let att = value as? TableRowAttachment else { return }
            let id = ObjectIdentifier(att.layout)
            if let idx = layoutsByOrder.firstIndex(where: { $0.0 == id }) {
                layoutsByOrder[idx].2.append((range, att))
            } else {
                layoutsByOrder.append((id, att.layout, [(range, att)]))
            }
        }
        guard tableIndex < layoutsByOrder.count else { return }
        let rows = layoutsByOrder[tableIndex].2
        let nonSep = rows.filter { $0.1.kind != .separator }
        guard rowIdx < nonSep.count,
              let cci = nonSep[rowIdx].1.cellContentIndex else { return }
        let (rowRange, attachment) = nonSep[rowIdx]

        // Locate the row's fragment.
        guard let docStart = tlm.textContentManager?.documentRange.location,
              let rowStart = tlm.location(docStart, offsetBy: rowRange.location),
              let frag = tlm.textLayoutFragment(for: rowStart) else { return }

        controller.showOverlay(
            attachment: attachment,
            rowIdx: cci, colIdx: colIdx,
            tableRowSourceRange: rowRange,
            localCaretIndex: initialCaret ?? 0,
            fragmentFrame: frag.layoutFragmentFrame)
    }

    private func typeInOverlay(_ text: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let ov = tv.subviews.compactMap({ $0 as? CellEditOverlay }).first
        else { return }
        ov.insertText(text, replacementRange: ov.selectedRange())
    }

    /// D13 Phase 5 — open modal popout on (table, row, col) directly,
    /// bypassing the right-click menu. Emulates the menu-action chain
    /// (commit overlay if active on a different cell, then open modal).
    private func openModalAtTableCell(tableIndex: Int, rowIdx: Int, colIdx: Int) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let storage = tv.textStorage,
              let modal = cellEditModalController else { return }
        // Commit any active overlay first (per spec §3.13 row 2).
        if let ctl = cellEditController, ctl.isActive {
            ctl.commit()
        }
        // Locate cell.
        var layouts: [(ObjectIdentifier, TableLayout, [(NSRange, TableRowAttachment)])] = []
        storage.enumerateAttribute(
            TableAttributeKeys.rowAttachmentKey,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let att = value as? TableRowAttachment else { return }
            let id = ObjectIdentifier(att.layout)
            if let idx = layouts.firstIndex(where: { $0.0 == id }) {
                layouts[idx].2.append((range, att))
            } else {
                layouts.append((id, att.layout, [(range, att)]))
            }
        }
        guard tableIndex < layouts.count else { return }
        let layout = layouts[tableIndex].1
        let nonSep = layouts[tableIndex].2.filter { $0.1.kind != .separator }
        guard rowIdx < nonSep.count,
              let cci = nonSep[rowIdx].1.cellContentIndex,
              colIdx < layout.cellRanges[cci].count else { return }
        let cellRange = layout.cellRanges[cci][colIdx]
        let cellSource = (tv.string as NSString).substring(with: cellRange)
        modal.openModal(
            forCellRange: cellRange,
            originalContent: cellSource,
            rowLabel: "Row \(rowIdx)",
            colLabel: "Col \(colIdx + 1)")
    }

    private func setModalText(_ text: String) {
        // Modal's NSTextView is not exposed publicly; use a runtime
        // approach: find the modal window's textview via subview walk.
        guard let modal = cellEditModalController, modal.isActive else { return }
        for win in NSApp.windows where win.title.hasPrefix("Edit Cell") {
            if let scrollView = win.contentView?.subviews
                .compactMap({ $0 as? NSScrollView }).first,
               let tv = scrollView.documentView as? NSTextView {
                tv.string = text
                return
            }
        }
    }

    private func commitModal() {
        guard let modal = cellEditModalController, modal.isActive else { return }
        // Modal's saveAction is private; trigger via the Save button's
        // target/action chain by walking the contentView.
        for win in NSApp.windows where win.title.hasPrefix("Edit Cell") {
            if let saveBtn = win.contentView?.subviews
                .compactMap({ $0 as? NSButton })
                .first(where: { $0.title == "Save" }) {
                saveBtn.performClick(nil)
                return
            }
        }
    }

    private func cancelModal() {
        guard let modal = cellEditModalController, modal.isActive else { return }
        for win in NSApp.windows where win.title.hasPrefix("Edit Cell") {
            if let cancelBtn = win.contentView?.subviews
                .compactMap({ $0 as? NSButton })
                .first(where: { $0.title == "Cancel" }) {
                cancelBtn.performClick(nil)
                return
            }
        }
    }

    /// D13 Phase 4 — drive Tab/Shift+Tab via the overlay's delegate.
    private func advanceOverlayTab(backward: Bool) {
        guard let controller = cellEditController, controller.isActive,
              let tv = HarnessActiveSink.shared.activeTextView,
              let ov = tv.subviews.compactMap({ $0 as? CellEditOverlay }).first
        else { return }
        controller.overlayAdvanceTab(ov, backward: backward)
    }

    /// D13 Phase 3 — locate the cell, compute its container-coords
    /// click point, build an NSEvent at that point, dispatch via the
    /// text view's `mouseDown(with:)`. Drives the production mouseDown
    /// integration end-to-end (cell hit-test, click-to-caret math,
    /// overlay show) without depending on synthetic mouse input.
    private func simulateClickAtTableCell(tableIndex: Int, rowIdx: Int,
                                          colIdx: Int,
                                          relX: CGFloat, relY: CGFloat) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let storage = tv.textStorage,
              let tlm = tv.textLayoutManager else { return }
        // Walk unique TableLayouts in document order.
        var layoutsByOrder: [(ObjectIdentifier, TableLayout, [(NSRange, TableRowAttachment)])] = []
        storage.enumerateAttribute(
            TableAttributeKeys.rowAttachmentKey,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let att = value as? TableRowAttachment else { return }
            let id = ObjectIdentifier(att.layout)
            if let idx = layoutsByOrder.firstIndex(where: { $0.0 == id }) {
                layoutsByOrder[idx].2.append((range, att))
            } else {
                layoutsByOrder.append((id, att.layout, [(range, att)]))
            }
        }
        guard tableIndex < layoutsByOrder.count else { return }
        let layout = layoutsByOrder[tableIndex].1
        let rows = layoutsByOrder[tableIndex].2
        let nonSep = rows.filter { $0.1.kind != .separator }
        guard rowIdx < nonSep.count,
              let cci = nonSep[rowIdx].1.cellContentIndex else { return }
        let rowRange = nonSep[rowIdx].0
        guard colIdx < layout.contentWidths.count,
              let docStart = tlm.textContentManager?.documentRange.location,
              let rowStart = tlm.location(docStart, offsetBy: rowRange.location),
              let frag = tlm.textLayoutFragment(for: rowStart) else { return }

        // Compute view-coord click point from cell-content-local (relX, relY).
        let inset = tv.textContainerInset
        let viewX = frag.layoutFragmentFrame.origin.x
            + layout.columnLeadingX[colIdx] + relX + inset.width
        let viewY = frag.layoutFragmentFrame.origin.y
            + layout.cellInset.top + relY + inset.height

        // Convert view coords to window coords (NSEvent expects window-local).
        let viewPoint = NSPoint(x: viewX, y: viewY)
        let windowPoint = tv.convert(viewPoint, to: nil)

        // Construct a synthetic mouseDown event.
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: tv.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0)
        else { return }
        tv.mouseDown(with: event)
        NSLog("[TEST-HARNESS] simulate_click_at_table_cell → table=\(tableIndex) row=\(rowIdx) col=\(colIdx) viewPoint=\(viewPoint)")
    }

    private func setOverlayText(_ text: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let ov = tv.subviews.compactMap({ $0 as? CellEditOverlay }).first
        else { return }
        ov.string = text
        ov.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    /// D13 Phase 1 — locate the Nth distinct TableLayout by document
    /// order, pick its body row at `rowIdx` (skipping separator), and
    /// invoke `cellLocalCaretIndex(rowIdx:colIdx:relX:relY:)`. Result
    /// includes the cell content + length so external test drivers can
    /// validate the math against expected values.
    private func queryCaretForClick(tableIndex: Int,
                                    rowIdx: Int, colIdx: Int,
                                    relX: CGFloat, relY: CGFloat,
                                    to path: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let storage = tv.textStorage else {
            writeJSONError(["error": "no active text view"], to: path)
            return
        }
        // Walk unique TableLayouts in document order.
        var rowsByLayout: [(ObjectIdentifier,
                            TableLayout,
                            [(NSRange, TableRowAttachment)])] = []
        storage.enumerateAttribute(
            TableAttributeKeys.rowAttachmentKey,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let att = value as? TableRowAttachment else { return }
            let id = ObjectIdentifier(att.layout)
            if let idx = rowsByLayout.firstIndex(where: { $0.0 == id }) {
                rowsByLayout[idx].2.append((range, att))
            } else {
                rowsByLayout.append((id, att.layout, [(range, att)]))
            }
        }
        guard tableIndex < rowsByLayout.count else {
            writeJSONError([
                "error": "tableIndex out of range",
                "tableIndex": tableIndex,
                "tableCount": rowsByLayout.count
            ], to: path)
            return
        }
        let (_, layout, rows) = rowsByLayout[tableIndex]
        // Skip separator rows; pick the rowIdx'th remaining (header=0,
        // body=1, body=2, ...).
        let nonSep = rows.filter { $0.1.kind != .separator }
        guard rowIdx < nonSep.count,
              let cci = nonSep[rowIdx].1.cellContentIndex else {
            writeJSONError([
                "error": "rowIdx out of range",
                "rowIdx": rowIdx,
                "rowCount": nonSep.count
            ], to: path)
            return
        }
        let caret = layout.cellLocalCaretIndex(
            rowIdx: cci, colIdx: colIdx, relX: relX, relY: relY)
        let cellContent: String
        let cellLength: Int
        if cci < layout.cellContentPerRow.count,
           colIdx < layout.cellContentPerRow[cci].count {
            cellContent = layout.cellContentPerRow[cci][colIdx].string
            cellLength = layout.cellContentPerRow[cci][colIdx].length
        } else {
            cellContent = ""
            cellLength = 0
        }
        let payload: [String: Any] = [
            "tableIndex": tableIndex,
            "rowIdx": rowIdx,
            "cci": cci,
            "colIdx": colIdx,
            "relX": Double(relX),
            "relY": Double(relY),
            "localCaretIndex": caret,
            "cellContent": cellContent,
            "cellContentLength": cellLength
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("[TEST-HARNESS] query_caret_for_click → \(caret) of \(cellLength)")
        }
    }

    private func writeJSONError(_ payload: [String: Any], to path: String) {
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// D14 harness — invoke save() on the focused doc and write
    /// success/error info. Bypasses the menu chain so we can validate
    /// the EditorDocument.save() write path without driving NSMenu.
    private func saveFocusedDoc(to path: String) {
        let store = WorkspaceStore.shared
        guard let doc = store.tabs.focused else {
            writeJSONError(["error": "no focused doc"], to: path)
            return
        }
        do {
            try doc.save()
            let payload: [String: Any] = [
                "saved": true,
                "url": doc.url?.path ?? "",
                "sourceLength": (doc.source as NSString).length
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        } catch {
            writeJSONError([
                "saved": false,
                "error": "\(error)"
            ], to: path)
        }
    }

    private func saveAsFocusedDoc(newURLPath: String, resultPath: String) {
        let store = WorkspaceStore.shared
        guard let doc = store.tabs.focused else {
            writeJSONError(["error": "no focused doc"], to: resultPath)
            return
        }
        let newURL = URL(fileURLWithPath: newURLPath)
        do {
            try doc.saveAs(to: newURL)
            let payload: [String: Any] = [
                "saved": true,
                "newURL": doc.url?.path ?? "",
                "sourceLength": (doc.source as NSString).length
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: resultPath))
            }
        } catch {
            writeJSONError([
                "saved": false,
                "error": "\(error)"
            ], to: resultPath)
        }
    }

    private func writeFocusedDocInfo(to path: String) {
        let store = WorkspaceStore.shared
        guard let doc = store.tabs.focused else {
            writeJSONError(["error": "no focused doc"], to: path)
            return
        }
        let payload: [String: Any] = [
            "url": doc.url?.path ?? "",
            "displayName": doc.displayName,
            "sourceLength": (doc.source as NSString).length,
            "externallyDeleted": doc.externallyDeleted
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func writeScrollInfo(to path: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let scrollView = tv.enclosingScrollView else {
            writeJSONError(["error": "no scroll view"], to: path)
            return
        }
        let cv = scrollView.contentView
        let docVisible = scrollView.documentVisibleRect
        let payload: [String: Any] = [
            "contentBounds": [
                "x": cv.bounds.origin.x, "y": cv.bounds.origin.y,
                "w": cv.bounds.size.width, "h": cv.bounds.size.height
            ],
            "documentVisibleRect": [
                "x": docVisible.origin.x, "y": docVisible.origin.y,
                "w": docVisible.size.width, "h": docVisible.size.height
            ],
            "scrollY": cv.bounds.origin.y
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func writeWindowInfo(to path: String) {
        guard let tv = HarnessActiveSink.shared.activeTextView,
              let window = tv.window,
              let screen = NSScreen.screens.first else { return }
        let wf = window.frame
        let cf = window.contentView?.frame ?? .zero
        let payload: [String: Any] = [
            "windowFrame": [
                "x": wf.origin.x, "y": wf.origin.y,
                "w": wf.width, "h": wf.height
            ],
            "contentViewFrame": [
                "x": cf.origin.x, "y": cf.origin.y,
                "w": cf.width, "h": cf.height
            ],
            "titleBarHeight": wf.height - cf.height,
            "screenHeight": screen.frame.height,
            "contentTopLeftScreenCoords": [
                "x": wf.origin.x,
                "y": screen.frame.height - wf.origin.y - wf.height
                    + (wf.height - cf.height)
            ]
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("[TEST-HARNESS] window_info → \(path)")
        }
    }
}

#endif
