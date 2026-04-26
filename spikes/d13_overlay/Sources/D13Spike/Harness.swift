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
        let payload: [String: Any] = [
            "source": tv.string,
            "selection": sel,
            "windowFrame": frameDict(window?.frame ?? .zero)
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
