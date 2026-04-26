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
