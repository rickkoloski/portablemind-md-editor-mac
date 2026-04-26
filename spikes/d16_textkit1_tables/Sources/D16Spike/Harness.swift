// D16 harness — file-based command poller. Mirrors d13_overlay/Harness.
// Drives the spike from outside the process so phase verification can
// be scripted.
//
// Action paths:
//   /tmp/d16-command.json   — driver writes; poller consumes (tick = 200ms)
//   /tmp/d16-state.json     — state dump (scrollY, selection, length)
//   /tmp/d16-cells.json     — cellRanges + per-cell live frame
//   /tmp/d16-shot.png       — window-content snapshot
//
// Synchronization contract: command file disappears AFTER dispatch +
// any result file is written. Driver pattern: write command → poll
// for file disappearance → read result.

import AppKit
import Foundation

final class HarnessCommandPoller {
    static let shared = HarnessCommandPoller()
    private let commandPath = "/tmp/d16-command.json"
    weak var window: NSWindow?
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    private var timer: Timer?

    func start(window: NSWindow, textView: NSTextView, scrollView: NSScrollView) {
        self.window = window
        self.textView = textView
        self.scrollView = scrollView
        try? FileManager.default.removeItem(atPath: commandPath)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        print("[D16] harness started")
    }

    private func tick() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: commandPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            // Stale or unparseable file — wipe and move on.
            try? FileManager.default.removeItem(atPath: commandPath)
            return
        }
        print("[D16] action=\(action)")
        dispatch(action: action, params: obj)
        try? FileManager.default.removeItem(atPath: commandPath)
    }

    private func dispatch(action: String, params: [String: Any]) {
        switch action {
        case "dump_state":
            dumpState(to: (params["path"] as? String) ?? "/tmp/d16-state.json")
        case "dump_cells":
            dumpCells(to: (params["path"] as? String) ?? "/tmp/d16-cells.json")
        case "snapshot":
            writeSnapshot(to: (params["path"] as? String) ?? "/tmp/d16-shot.png")
        case "set_scroll":
            if let tv = textView, let sv = scrollView {
                let y = (params["y"] as? Double).map { CGFloat($0) }
                    ?? CGFloat((params["y"] as? Int) ?? 0)
                sv.contentView.scroll(to: NSPoint(x: 0, y: y))
                sv.reflectScrolledClipView(sv.contentView)
                _ = tv
            }
        case "set_selection":
            if let tv = textView,
               let loc = params["location"] as? Int {
                let len = params["length"] as? Int ?? 0
                tv.setSelectedRange(NSRange(location: loc, length: len))
            }
        case "insert_text":
            if let tv = textView,
               let text = params["text"] as? String {
                tv.insertText(text, replacementRange: tv.selectedRange())
            }
        case "synthesize_click":
            // NSTextView.mouseDown enters a tracking loop waiting for
            // mouseUp. Calling tv.mouseDown directly hangs. Instead,
            // resolve the click point to a character index and set
            // selection programmatically — same end result for the
            // four canonical scenarios (the goal is to verify what
            // CLICK position resolves to, not to drag-select).
            if let tv = textView,
               let lm = tv.layoutManager,
               let container = tv.textContainer,
               let viewX = (params["viewX"] as? Double),
               let viewY = (params["viewY"] as? Double) {
                let inset = tv.textContainerInset
                let containerPoint = NSPoint(
                    x: viewX - inset.width,
                    y: viewY - inset.height)
                let glyphIndex = lm.glyphIndex(
                    for: containerPoint, in: container,
                    fractionOfDistanceThroughGlyph: nil)
                let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
                tv.setSelectedRange(NSRange(location: charIndex, length: 0))
                let cell = TK1TextView.cell(forCharIndex: charIndex)
                if let cell {
                    print("[D16] synthesize_click viewPoint=(\(viewX),\(viewY)) → " +
                          "charIndex=\(charIndex) → cell row=\(cell.row) col=\(cell.col) " +
                          "range=\(cell.range)")
                } else {
                    print("[D16] synthesize_click viewPoint=(\(viewX),\(viewY)) → " +
                          "charIndex=\(charIndex) → NO CELL (plain-text region)")
                }
            }
        default:
            print("[D16] unknown action: \(action)")
        }
    }

    private func dumpState(to path: String) {
        guard let tv = textView, let sv = scrollView else { return }
        let payload: [String: Any] = [
            "scrollY": sv.contentView.bounds.origin.y,
            "selection": [
                "location": tv.selectedRange().location,
                "length": tv.selectedRange().length
            ],
            "sourceLength": tv.string.count,
            "windowFrame": [
                "x": window?.frame.origin.x ?? 0,
                "y": window?.frame.origin.y ?? 0,
                "w": window?.frame.size.width ?? 0,
                "h": window?.frame.size.height ?? 0
            ]
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func dumpCells(to path: String) {
        // Each cell's source range + live bounding rect from the
        // layout manager (TK1's authoritative position source).
        guard let tv = textView,
              let lm = tv.layoutManager,
              let container = tv.textContainer else {
            return
        }
        var cells: [[String: Any]] = []
        for entry in TK1TextView.cellRanges {
            let glyphRange = lm.glyphRange(forCharacterRange: entry.range,
                                           actualCharacterRange: nil)
            let bounds = lm.boundingRect(forGlyphRange: glyphRange,
                                         in: container)
            cells.append([
                "row": entry.row,
                "col": entry.col,
                "rangeLocation": entry.range.location,
                "rangeLength": entry.range.length,
                "bounds": [
                    "x": bounds.origin.x,
                    "y": bounds.origin.y,
                    "w": bounds.size.width,
                    "h": bounds.size.height
                ]
            ])
        }
        let payload: [String: Any] = ["cells": cells]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func writeSnapshot(to path: String) {
        guard let win = window,
              let content = win.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("[D16] snapshot → \(path) (\(data.count) bytes)")
    }
}
