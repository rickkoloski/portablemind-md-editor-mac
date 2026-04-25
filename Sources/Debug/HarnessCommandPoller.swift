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
        // Delete BEFORE executing so re-entry can't loop.
        try? FileManager.default.removeItem(atPath: commandPath)
        NSLog("[TEST-HARNESS] action=\(action)")
        dispatch(action: action, params: obj)
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
