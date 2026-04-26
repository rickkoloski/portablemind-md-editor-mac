// D13 Cell Edit Overlay Spike — main entry.
// Phase 1: scaffold a scroll-view-hosted NSTextView rendering three
// tables. No overlay yet. Verify build green + visual rendering before
// adding overlay infrastructure.

import AppKit
import Foundation

// File-based logging since the app runs detached from terminal.
func spikeLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/d13-spike-app.log")) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/d13-spike-app.log"))
        }
    }
}

let seedSource = """
| A | B |
|---|---|
| one | two |

| Description                         | Status |
|-------------------------------------|--------|
| This is intentionally long enough to wrap across at least two visual lines inside its column. | OK |
| Short                              | Triple-wrap candidate: this content is even longer to push it to three visual lines so the spike can validate clicks beyond line 2. |

| col1 |   | col3 |
|------|---|------|
| a    |   | c    |

"""

// MARK: - Window controller

final class SpikeWindowController: NSObject {
    let window: NSWindow
    let textView: NSTextView
    let scrollView: NSScrollView
    let layoutManagerDelegate = TableLayoutManagerDelegate()

    override init() {
        self.scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true

        // TextKit 2 NSTextView. Programmatic init.
        let textContainer = NSTextContainer(size: CGSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let textLayoutManager = NSTextLayoutManager()
        textLayoutManager.textContainer = textContainer

        let textContentStorage = NSTextContentStorage()
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textContentStorage.primaryTextLayoutManager = textLayoutManager

        let textStorage = textContentStorage.textStorage!
        textStorage.setAttributedString(NSAttributedString(string: seedSource))

        self.textView = LiveRenderTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = CGSize(width: 0, height: 0)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = CGSize(width: 16, height: 16)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = false
        textView.font = NSFont.systemFont(ofSize: 14)

        scrollView.documentView = textView
        textLayoutManager.delegate = layoutManagerDelegate

        // Window — log all screens, then explicitly place on the screen
        // with the largest visibleFrame.
        for (i, sc) in NSScreen.screens.enumerated() {
            spikeLog("screen[\(i)]: frame=\(sc.frame), visibleFrame=\(sc.visibleFrame)")
        }
        let bestScreen = NSScreen.screens.max(by: { $0.visibleFrame.size.width * $0.visibleFrame.size.height < $1.visibleFrame.size.width * $1.visibleFrame.size.height })
        spikeLog("bestScreen visibleFrame: \(bestScreen?.visibleFrame ?? .zero)")
        let sf = bestScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // contentRect uses bottom-left origin; place near top-left of best screen.
        let frame = NSRect(x: sf.origin.x + 100, y: sf.origin.y + sf.size.height - 700 - 50, width: 900, height: 700)
        spikeLog("computed window frame: \(frame)")
        self.window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "D13 Cell Edit Overlay Spike"

        super.init()

        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        window.contentView = scrollView

        // Force window onto the chosen screen — NSWindow init clamps to
        // main screen, so we explicitly setFrameOrigin after construction.
        window.setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y))
        spikeLog("post-setFrameOrigin window frame: \(window.frame)")

        SpikeRenderer.render(into: textStorage)
        textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        spikeLog("window frame: \(window.frame)")
        spikeLog("scrollView frame: \(scrollView.frame), bounds: \(scrollView.bounds)")
        spikeLog("textView frame: \(textView.frame), bounds: \(textView.bounds)")
        spikeLog("storage length: \(textStorage.length)")
        spikeLog("doc range: \(textLayoutManager.documentRange)")
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Wire cell-edit controller after textView exists.
        let controller = CellEditController(hostView: textView)
        (textView as? LiveRenderTextView)?.cellEditController = controller
        HarnessCommandPoller.shared.start(window: window, textView: textView)
        HarnessCommandPoller.shared.cellEditController = controller
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: SpikeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = SpikeWindowController()
        c.show()
        self.controller = c
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
