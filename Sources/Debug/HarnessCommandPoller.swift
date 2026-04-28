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
// D17 retired the D13-era cell overlay / modal / inspect actions
// alongside the TK2 fragment system. Cell editing is in-place via
// stock NSTextView + NSTextTable; the overlay's harness surface is
// no longer needed. The harness pattern survives as the diagnostic
// surface for any future TK1 layout question.
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
        case "set_scroll_via_wheel":
            // D15.1 — programmatic scroll(to:) does NOT post the
            // willStartLiveScroll / didLiveScroll / didEndLiveScroll
            // notification chain that NSScrollView emits during real
            // wheel scrolls. Some downstream code (and TextKit 2's own
            // lazy-layout invalidation) reacts to those signals. This
            // action mirrors the full notification sequence so harness
            // tests can repro post-wheel-scroll bugs.
            if let tv = HarnessActiveSink.shared.activeTextView,
               let scrollView = tv.enclosingScrollView {
                let y = (params["y"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["y"] as? Int) ?? 0)
                NotificationCenter.default.post(
                    name: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                NotificationCenter.default.post(
                    name: NSScrollView.didLiveScrollNotification,
                    object: scrollView)
                NotificationCenter.default.post(
                    name: NSScrollView.didEndLiveScrollNotification,
                    object: scrollView)
            }
        case "insert_text":
            if let text = params["text"] as? String,
               let tv = HarnessActiveSink.shared.activeTextView {
                tv.insertText(text, replacementRange: tv.selectedRange())
            }
        case "synthesize_keypress":
            // D15.1 reproduction path: real keyDown event so scroll-jump
            // bug surfaces. `insertText` bypasses the keyDown path that
            // NSTextView's internal auto-scroll-to-caret hooks into;
            // synthesizing an NSEvent and dispatching via keyDown(with:)
            // exercises the same machinery as a physical keystroke.
            if let tv = HarnessActiveSink.shared.activeTextView {
                tv.window?.makeFirstResponder(tv)
                let chars = (params["chars"] as? String) ?? " "
                let keyCode = UInt16((params["keyCode"] as? Int) ?? 49) // space
                var modifierFlags: NSEvent.ModifierFlags = []
                if (params["shift"] as? Bool) == true {
                    modifierFlags.insert(.shift)
                }
                if (params["option"] as? Bool) == true {
                    modifierFlags.insert(.option)
                }
                if (params["command"] as? Bool) == true {
                    modifierFlags.insert(.command)
                }
                if (params["control"] as? Bool) == true {
                    modifierFlags.insert(.control)
                }
                let evt = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: modifierFlags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: tv.window?.windowNumber ?? 0,
                    context: nil,
                    characters: chars,
                    charactersIgnoringModifiers: chars,
                    isARepeat: false,
                    keyCode: keyCode)
                if let evt {
                    tv.keyDown(with: evt)
                }
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
        // D17 — overlay/modal/cell-table actions retired with the TK2
        // fragment + cell-edit-overlay code (phases 3+4). Cell editing
        // is now in-place via stock NSTextView + NSTextTable.
        // D18 phase 2 — PortableMind API client + Keychain token store.
        case "pm_token_set":
            pmTokenSet(token: params["token"] as? String,
                       resultPath: params["path"] as? String
                        ?? "/tmp/mdeditor-pm-token-set.json")
        case "pm_token_dump":
            pmTokenDump(to: params["path"] as? String
                ?? "/tmp/mdeditor-pm-token.json")
        case "pm_api_smoke":
            // ASYNC: kicks off Task.detached, returns immediately.
            // Driver waits for the result file to be non-empty rather
            // than for command-file disappearance.
            pmApiSmoke(to: params["path"] as? String
                ?? "/tmp/mdeditor-pm-api.json")
        case "connector_save_focused":
            // D19 phase 3 — async; calls doc.save() on the focused
            // tab (routes through the connector). Result envelope
            // emits ok / error / dirty / isReadOnly so the driver
            // can verify the save path end-to-end.
            // D19 phase 4 — optional `force: true` skips the conflict
            // check (drives the Overwrite path without the dialog).
            let force = (params["force"] as? Bool) ?? false
            connectorSaveFocused(
                force: force,
                to: params["path"] as? String
                    ?? "/tmp/mdeditor-save-result.json")
        case "pm_save_smoke":
            // D19 phase 2 — ASYNC; writes `text` as the new content
            // of the LlmFile with id `fileID`. Result envelope at
            // `path` includes ok / byteCount / freshUrl / updatedAt
            // so the driver can verify the write end-to-end. Optional
            // `filename` is passed to the multipart body so the
            // ActiveStorage blob keeps a sensible filename (defaults
            // to the LlmFile's existing title via a fetch round-trip
            // when omitted).
            let fileID: Int = {
                if let i = params["fileID"] as? Int { return i }
                if let s = params["fileID"] as? String, let i = Int(s) { return i }
                return -1
            }()
            pmSaveSmoke(fileID: fileID,
                        text: (params["text"] as? String) ?? "",
                        filename: params["filename"] as? String,
                        to: params["path"] as? String
                            ?? "/tmp/mdeditor-pm-save.json")
        // D18 phase 3 — sidebar / connector tree inspection.
        case "dump_sidebar_state":
            dumpSidebarState(to: params["path"] as? String
                ?? "/tmp/mdeditor-sidebar.json")
        case "expand_sidebar_path":
            expandSidebarPath(connectorID: params["connectorID"] as? String,
                              path: params["path"] as? String)
        case "collapse_sidebar_path":
            collapseSidebarPath(connectorID: params["connectorID"] as? String,
                                path: params["path"] as? String)
        case "dump_connector_tree":
            // ASYNC: bypasses UI, calls connector.children directly.
            dumpConnectorTree(connectorID: params["connectorID"] as? String,
                              parentPath: params["parentPath"] as? String,
                              to: params["path"] as? String
                                ?? "/tmp/mdeditor-connector-tree.json")
        // D18 phase 5 — file open via connector + read-only state.
        case "connector_open_file":
            // ASYNC: triggers connector.openFile, opens a tab on
            // success. Driver waits for `dump_focused_tab_info` to
            // reflect the new tab.
            connectorOpenFile(connectorID: params["connectorID"] as? String,
                              path: params["path"] as? String,
                              resultPath: params["resultPath"] as? String
                                ?? "/tmp/mdeditor-open-result.json")
        case "dump_command_state":
            dumpCommandState(to: params["path"] as? String
                ?? "/tmp/mdeditor-commands.json")
        // D19 phase 4 — conflict-detection harness affordances.
        case "dump_save_state":
            dumpSaveState(to: params["path"] as? String
                ?? "/tmp/mdeditor-save-state.json")
        case "dismiss_conflict_dialog":
            dismissConflictDialog(
                choice: params["choice"] as? String,
                resultPath: params["path"] as? String
                    ?? "/tmp/mdeditor-conflict-dismiss.json")
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
        if let frame = tv.window?.frame {
            payload["windowFrame"] = [
                "x": frame.origin.x, "y": frame.origin.y,
                "w": frame.width, "h": frame.height
            ]
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

    // D17 — overlay/modal/cell-table action implementations retired
    // along with their TK2-shaped types. Private helpers below survive
    // (writeJSONError, etc.) because they're used by the actions that
    // remain.

    private func writeJSONError(_ payload: [String: Any], to path: String) {
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// D14 harness — invoke save() on the focused doc and write
    /// success/error info. Bypasses the menu chain so we can validate
    /// the EditorDocument.save() write path without driving NSMenu.
    /// D19 phase 3 — save() is now async (PM saves over the network);
    /// this wraps the call in a Task and writes the result file when
    /// the save resolves. Driver waits for the result file as the
    /// completion signal, not command-file disappearance.
    private func saveFocusedDoc(to path: String) {
        try? Data().write(to: URL(fileURLWithPath: path))
        Task { @MainActor in
            let store = WorkspaceStore.shared
            guard let doc = store.tabs.focused else {
                Self.writeJSONErrorStatic(
                    ["error": "no focused doc"], to: path)
                return
            }
            do {
                try await doc.save()
                let payload: [String: Any] = [
                    "saved": true,
                    "url": doc.url?.path ?? "",
                    "sourceLength": (doc.source as NSString).length
                ]
                if let data = try? JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            } catch {
                Self.writeJSONErrorStatic([
                    "saved": false,
                    "error": "\(error)"
                ], to: path)
            }
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
        var origin: [String: Any] = ["kind": "local"]
        if case .portableMind(let cid, let fid, let dpath) = doc.origin {
            origin = [
                "kind": "portablemind",
                "connectorID": cid,
                "fileID": fid,
                "displayPath": dpath
            ]
        }
        let lastSeen = doc.connectorNode?.lastSeenUpdatedAt
            .map { ISO8601DateFormatter.fractional.string(from: $0) }
            ?? ""
        let payload: [String: Any] = [
            "url": doc.url?.path ?? "",
            "displayName": doc.displayName,
            "isReadOnly": doc.isReadOnly,
            "isSaving": doc.isSaving,
            "dirty": doc.dirty,
            "lastSeenUpdatedAt": lastSeen,
            "origin": origin,
            "sourceLength": (doc.source as NSString).length,
            "externallyDeleted": doc.externallyDeleted
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// `connector_save_focused` (D19 phase 3) — call doc.save() on the
    /// focused tab. Async; the driver waits for the result file to be
    /// non-empty.
    ///
    /// D19 phase 4 — when `force == true` is passed, the connector
    /// skips the GET-before-PATCH conflict check (used by the harness
    /// to drive the Overwrite path without an interactive dialog).
    /// When the connector throws `.conflictDetected`, the envelope
    /// reports `conflictDetected: true` plus `serverUpdatedAt` instead
    /// of the generic `error: "conflictDetected"` form — lets test
    /// drivers branch cleanly.
    private func connectorSaveFocused(force: Bool, to path: String) {
        try? Data().write(to: URL(fileURLWithPath: path))
        Task { @MainActor in
            let store = WorkspaceStore.shared
            guard let doc = store.tabs.focused else {
                Self.writeJSONErrorStatic(
                    ["ok": false, "error": "no focused doc"], to: path)
                return
            }
            let payload: [String: Any]
            do {
                try await doc.save(force: force)
                payload = [
                    "ok": true,
                    "displayName": doc.displayName,
                    "dirty": doc.dirty,
                    "isReadOnly": doc.isReadOnly,
                    "conflictDetected": false
                ]
            } catch ConnectorError.conflictDetected(let serverUpdatedAt) {
                payload = [
                    "ok": false,
                    "conflictDetected": true,
                    "serverUpdatedAt": ISO8601DateFormatter.fractional
                        .string(from: serverUpdatedAt),
                    "displayName": doc.displayName,
                    "dirty": doc.dirty
                ]
            } catch let serr as EditorDocument.SaveError {
                payload = [
                    "ok": false,
                    "error": "saveError",
                    "message": serr.errorDescription ?? "\(serr)"
                ]
            } catch {
                payload = [
                    "ok": false,
                    "error": "\(error)"
                ]
            }
            if let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// `dump_save_state` (D19 phase 4) — emit the save-related state
    /// the test driver needs to branch on conflict-detection scenarios.
    /// Includes the dialog-shown flag so a driver can poll until the
    /// modal sheet is up before issuing `dismiss_conflict_dialog`.
    private func dumpSaveState(to path: String) {
        let store = WorkspaceStore.shared
        guard let doc = store.tabs.focused else {
            writeJSONError(["error": "no focused doc"], to: path)
            return
        }
        let lastSeen = doc.connectorNode?.lastSeenUpdatedAt
            .map { ISO8601DateFormatter.fractional.string(from: $0) }
            ?? ""
        let payload: [String: Any] = [
            "displayName": doc.displayName,
            "dirty": doc.dirty,
            "isSaving": doc.isSaving,
            "isReadOnly": doc.isReadOnly,
            "lastSeenUpdatedAt": lastSeen,
            "conflictDialogShown": ConflictDialogPresenter.shared.isShowing
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// `dismiss_conflict_dialog` (D19 phase 4) — programmatically
    /// click the matching button on the active conflict NSAlert. Returns
    /// `dismissed: false` if no dialog is currently showing (driver
    /// should poll `dump_save_state` first).
    private func dismissConflictDialog(choice: String?, resultPath: String) {
        let parsed: ConflictDialogPresenter.Choice
        switch (choice ?? "").lowercased() {
        case "overwrite": parsed = .overwrite
        case "cancel":    parsed = .cancel
        default:
            writeJSONError(
                ["dismissed": false,
                 "error": "missing or invalid choice (expected overwrite or cancel)"],
                to: resultPath)
            return
        }
        let dismissed = ConflictDialogPresenter.shared.dismiss(choice: parsed)
        let payload: [String: Any] = [
            "dismissed": dismissed,
            "choice": parsed == .overwrite ? "overwrite" : "cancel"
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: resultPath))
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

    // MARK: - D18 phase 2: PortableMind API client + Keychain

    /// `pm_token_set` → write a bearer token to the Keychain. Always
    /// emits a small JSON envelope to `resultPath` so the driver can
    /// distinguish "saved" from "save failed".
    private func pmTokenSet(token: String?, resultPath: String) {
        guard let token, !token.isEmpty else {
            writeJSONError(["saved": false, "error": "missing or empty token"],
                           to: resultPath)
            return
        }
        do {
            try KeychainTokenStore.shared.save(token: token)
            // Mirror Debug menu behavior: nudge the workspace to
            // re-evaluate its connector list so the PortableMind root
            // appears immediately.
            WorkspaceStore.shared.reconcileConnectors()
            writeJSONError(["saved": true, "length": token.count],
                           to: resultPath)
        } catch {
            writeJSONError(["saved": false, "error": "\(error)"],
                           to: resultPath)
        }
    }

    /// `pm_token_dump` → emit `{present: bool, length: Int}`. Never
    /// returns the token itself.
    private func pmTokenDump(to path: String) {
        do {
            if let token = try KeychainTokenStore.shared.load(), !token.isEmpty {
                writeJSONError(["present": true, "length": token.count],
                               to: path)
            } else {
                writeJSONError(["present": false, "length": 0], to: path)
            }
        } catch {
            writeJSONError(["present": false, "error": "\(error)"], to: path)
        }
    }

    // MARK: - D18 phase 3: sidebar / connector tree inspection

    /// `dump_sidebar_state` — emit each connector's root, expansion
    /// state, and any loaded subtrees. Recursive: only loaded
    /// subtrees materialize; unloaded ones show `loaded: false`.
    private func dumpSidebarState(to path: String) {
        let store = WorkspaceStore.shared
        let connectors = store.connectors
        var roots: [[String: Any]] = []
        for connector in connectors {
            guard let model = store.treeViewModels[connector.id] else { continue }
            let rootNode = connector.rootNode
            roots.append(serializeNode(rootNode, viewModel: model))
        }
        let payload: [String: Any] = ["roots": roots]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("[TEST-HARNESS] dump_sidebar_state → \(path)")
        }
    }

    private func serializeNode(_ node: ConnectorNode,
                               viewModel: ConnectorTreeViewModel) -> [String: Any] {
        var dict: [String: Any] = [
            "connectorID": viewModel.connector.id,
            "id": node.id,
            "name": node.name,
            "path": node.path,
            "kind": node.kind == .directory ? "directory" : "file",
            "supported": node.isSupported,
            "expanded": viewModel.isExpanded(node.path),
            "loading": viewModel.isLoading(node.path),
        ]
        if let count = node.fileCount { dict["fileCount"] = count }
        if let tenant = node.tenant {
            dict["tenant"] = [
                "id": tenant.id,
                "name": tenant.name,
                "enterpriseIdentifier": tenant.enterpriseIdentifier
            ]
            // Phase 4 — derive badge state for assertion. Badge
            // visible iff cross-tenant (node.tenant != current user).
            if viewModel.isCrossTenant(node) {
                dict["tenantBadge"] = [
                    "initials": TenantInitialsBadge.initials(from: tenant.name),
                    "tooltip": tenant.name,
                    "fgHex": "#E5007E",
                    "bgHex": "#FCE4EC"
                ]
            }
        }
        if let error = viewModel.errorMessage(at: node.path) {
            dict["error"] = error
        }
        if node.kind == .directory {
            if let kids = viewModel.childrenIfLoaded(at: node.path) {
                dict["loaded"] = true
                if viewModel.isExpanded(node.path) {
                    dict["children"] = kids.map { serializeNode($0, viewModel: viewModel) }
                }
            } else {
                dict["loaded"] = false
            }
        }
        return dict
    }

    /// `expand_sidebar_path` — programmatically expand a path on the
    /// connector's tree. Triggers async load if needed; harness
    /// driver waits for `dump_sidebar_state` to show `loading: false`
    /// before asserting.
    private func expandSidebarPath(connectorID: String?, path: String?) {
        guard let connectorID, let path,
              let model = WorkspaceStore.shared.treeViewModels[connectorID]
        else { return }
        Task { @MainActor in
            await model.expand(path: path)
        }
    }

    /// `collapse_sidebar_path` — programmatically collapse a path.
    /// Preserves cached children for instant re-expand.
    private func collapseSidebarPath(connectorID: String?, path: String?) {
        guard let connectorID, let path,
              let model = WorkspaceStore.shared.treeViewModels[connectorID]
        else { return }
        model.collapse(path: path)
    }

    /// `dump_connector_tree` — bypass the UI; call
    /// `connector.children(of: parentPath)` directly. Lets the
    /// harness distinguish API-level failure from UI-level failure.
    /// Async; driver waits for the result file to be non-empty.
    private func dumpConnectorTree(connectorID: String?,
                                   parentPath: String?,
                                   to path: String) {
        try? Data().write(to: URL(fileURLWithPath: path))
        guard let connectorID,
              let connector = WorkspaceStore.shared.connectors.first(
                where: { $0.id == connectorID })
        else {
            writeJSONError(
                ["ok": false, "error": "no connector with id \(connectorID ?? "<nil>")"],
                to: path)
            return
        }
        Task.detached {
            let payload: [String: Any]
            do {
                let kids = try await connector.children(of: parentPath)
                payload = [
                    "ok": true,
                    "count": kids.count,
                    "children": kids.map { node in
                        var dict: [String: Any] = [
                            "id": node.id,
                            "name": node.name,
                            "path": node.path,
                            "kind": node.kind == .directory ? "directory" : "file",
                            "supported": node.isSupported,
                        ]
                        if let count = node.fileCount { dict["fileCount"] = count }
                        if let tenant = node.tenant {
                            dict["tenant"] = [
                                "id": tenant.id,
                                "name": tenant.name,
                                "enterpriseIdentifier": tenant.enterpriseIdentifier
                            ]
                        }
                        return dict
                    }
                ]
            } catch ConnectorError.unauthenticated {
                payload = ["ok": false, "error": "unauthenticated"]
            } catch ConnectorError.network(let underlying) {
                payload = ["ok": false, "error": "network: \(underlying)"]
            } catch ConnectorError.server(let status, let message) {
                payload = ["ok": false, "error": "server",
                           "status": status, "message": message ?? ""]
            } catch {
                payload = ["ok": false, "error": "\(error)"]
            }
            if let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// `connector_open_file` — programmatically open a file via a
    /// connector. Drives the same flow as a row click. Async; writes
    /// a small status envelope to `resultPath` so the driver can
    /// distinguish open-success from open-failure.
    private func connectorOpenFile(connectorID: String?,
                                   path: String?,
                                   resultPath: String) {
        try? Data().write(to: URL(fileURLWithPath: resultPath))
        guard let connectorID, let path else {
            writeJSONError(["ok": false, "error": "missing params"],
                           to: resultPath)
            return
        }
        let store = WorkspaceStore.shared
        guard let connector = store.connectors.first(
            where: { $0.id == connectorID }),
              let model = store.treeViewModels[connectorID]
        else {
            writeJSONError(["ok": false,
                            "error": "no connector with id \(connectorID)"],
                           to: resultPath)
            return
        }
        // Resolve a ConnectorNode by walking already-loaded children
        // (the harness usually expands the parent path via
        // `expand_sidebar_path` before opening). For Local the node is
        // synthesized from the path; for PM we need the loaded node so
        // we get the correct `id` (which encodes the LlmFile id).
        Task.detached {
            let node = await Self.findOrSynthesizeNode(
                connector: connector,
                viewModel: model,
                path: path)
            guard let node else {
                Self.writeJSONErrorStatic(
                    ["ok": false,
                     "error": "no node found for path \(path); expand the parent first"],
                    to: resultPath)
                return
            }
            do {
                let (bytes, refreshedNode) = try await connector.openFile(node)
                let text = String(data: bytes, encoding: .utf8) ?? ""
                await MainActor.run {
                    if connector.id == "local" {
                        _ = store.tabs.open(
                            fileURL: URL(fileURLWithPath: node.path))
                    } else {
                        // D19 phase 3 — openFromConnector derives the
                        // origin from the node and computes
                        // isReadOnly from connector.canWrite. D19 phase 4
                        // — refreshedNode carries `lastSeenUpdatedAt`
                        // from the meta call so save-time conflict
                        // detection has a baseline.
                        store.tabs.openFromConnector(
                            content: text, node: refreshedNode)
                    }
                }
                Self.writeJSONErrorStatic(
                    ["ok": true,
                     "displayName": refreshedNode.name,
                     "byteCount": bytes.count],
                    to: resultPath)
            } catch {
                Self.writeJSONErrorStatic(
                    ["ok": false, "error": "\(error)"],
                    to: resultPath)
            }
        }
    }

    /// Search the view-model's loaded subtree for a node matching
    /// `path`; if not found and the connector is Local, synthesize
    /// one (the local filesystem accepts the path directly).
    @MainActor
    private static func findOrSynthesizeNode(
        connector: any Connector,
        viewModel: ConnectorTreeViewModel,
        path: String
    ) -> ConnectorNode? {
        // BFS through the loaded paths. childrenIfLoaded returns sync
        // results for local; for PM, returns nil if not loaded.
        var queue: [String] = [connector.rootNode.path]
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            guard let kids = viewModel.childrenIfLoaded(at: parent) else {
                continue
            }
            for kid in kids {
                if kid.path == path { return kid }
                if kid.kind == .directory { queue.append(kid.path) }
            }
        }
        // Fallback for Local: build a node directly. For PM this would
        // miss the file id; require an expanded subtree first.
        if connector.id == "local" {
            return ConnectorNode(
                id: "\(connector.id):\(path)",
                name: (path as NSString).lastPathComponent,
                path: path,
                kind: .file,
                fileCount: nil,
                tenant: nil,
                isSupported: path.lowercased().hasSuffix(".md"),
                connector: connector)
        }
        return nil
    }

    /// Static helper used from Task.detached — JSONSerialization +
    /// atomic write. Marked `nonisolated` so it doesn't inherit the
    /// outer @MainActor isolation; harness async paths must call it
    /// from background contexts.
    nonisolated private static func writeJSONErrorStatic(
        _ payload: [String: Any], to path: String
    ) {
        if let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// `dump_command_state` — emit the enabled state of save-related
    /// menu commands. Drives Phase 5's "save disables for read-only
    /// tabs" assertion.
    private func dumpCommandState(to path: String) {
        let store = WorkspaceStore.shared
        let focused = store.tabs.focused
        let isReadOnly = focused?.isReadOnly ?? false
        let payload: [String: Any] = [
            "save": !isReadOnly && focused != nil,
            "saveAs": !isReadOnly && focused != nil,
            "reason": isReadOnly ? "focused tab is read-only"
                                  : (focused == nil ? "no focused tab" : "")
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// `pm_api_smoke` → calls `listDirectories(parentPath: nil)` and
    /// writes the result to `path`. Async — kicks off a detached Task,
    /// returns immediately. Driver waits for the result file to be
    /// non-empty (rather than for the command file to disappear).
    private func pmApiSmoke(to path: String) {
        // Truncate the result path to zero length so the driver's
        // "wait for non-empty" check is reliable.
        try? Data().write(to: URL(fileURLWithPath: path))
        Task.detached {
            let client = PortableMindAPIClient()
            let payload: [String: Any]
            do {
                let dirs = try await client.listDirectories(parentPath: nil)
                payload = [
                    "ok": true,
                    "count": dirs.count,
                    "directories": dirs.map { d in
                        [
                            "id": d.id,
                            "name": d.name,
                            "path": d.path,
                            "subdirectory_count": d.subdirectory_count ?? 0,
                            "file_count": d.file_count ?? 0,
                            "tenant_id": d.tenant_id,
                            "tenant_enterprise_identifier":
                                d.tenant_enterprise_identifier ?? "",
                            "tenant_name": d.tenant_name ?? ""
                        ] as [String: Any]
                    }
                ]
            } catch ConnectorError.unauthenticated {
                payload = ["ok": false, "error": "unauthenticated"]
            } catch ConnectorError.network(let underlying) {
                payload = ["ok": false, "error": "network: \(underlying)"]
            } catch ConnectorError.server(let status, let message) {
                payload = ["ok": false,
                           "error": "server",
                           "status": status,
                           "message": message ?? ""]
            } catch {
                payload = ["ok": false, "error": "\(error)"]
            }
            if let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
                NSLog("[TEST-HARNESS] pm_api_smoke → \(path) (\(data.count) bytes)")
            }
        }
    }

    /// `pm_save_smoke` (D19 phase 2) — writes `text` as new content
    /// of `fileID` via `PortableMindAPIClient.updateFile`. Async; the
    /// driver waits for the result file to be non-empty.
    ///
    /// `filename` is optional; if nil, the smoke fetches the file's
    /// title via `fetchFileMeta` first and uses that as the multipart
    /// filename. Keeps ActiveStorage blob's filename aligned with the
    /// LlmFile's title rather than leaking the client-side default.
    private func pmSaveSmoke(fileID: Int,
                             text: String,
                             filename: String?,
                             to path: String) {
        try? Data().write(to: URL(fileURLWithPath: path))
        Task.detached {
            let client = PortableMindAPIClient()
            let payload: [String: Any]
            do {
                guard fileID > 0 else {
                    Self.writeJSONErrorStatic(
                        ["ok": false, "error": "missing or invalid fileID"],
                        to: path)
                    return
                }
                let resolvedFilename: String
                if let f = filename, !f.isEmpty {
                    resolvedFilename = f
                } else if let meta = try? await client.fetchFileMeta(
                    fileID: fileID) {
                    resolvedFilename = meta.title
                } else {
                    resolvedFilename = "content.md"
                }
                let bytes = Data(text.utf8)
                let updated = try await client.updateFile(
                    fileID: fileID,
                    bytes: bytes,
                    filename: resolvedFilename)
                payload = [
                    "ok": true,
                    "fileID": updated.id,
                    "byteCount": bytes.count,
                    "filename": resolvedFilename,
                    "freshUrl": updated.url ?? "",
                    "updatedAt": updated.updated_at ?? "",
                    "title": updated.title
                ]
            } catch ConnectorError.unauthenticated {
                payload = ["ok": false, "error": "unauthenticated"]
            } catch ConnectorError.writeForbidden(let body) {
                payload = ["ok": false, "error": "writeForbidden",
                           "body": body]
            } catch ConnectorError.storageQuotaExceeded(let body) {
                payload = ["ok": false, "error": "storageQuotaExceeded",
                           "body": body]
            } catch ConnectorError.network(let underlying) {
                payload = ["ok": false, "error": "network: \(underlying)"]
            } catch ConnectorError.server(let status, let message) {
                payload = ["ok": false, "error": "server",
                           "status": status, "message": message ?? ""]
            } catch {
                payload = ["ok": false, "error": "\(error)"]
            }
            if let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
                NSLog("[TEST-HARNESS] pm_save_smoke → \(path) (\(data.count) bytes)")
            }
        }
    }
}

#endif
