// D16 spike — TextKit 1 native tables.
// Logs go to /tmp/d16-spike.log so harness scripts and CC can see
// diagnostic output without needing Console.app.
// Hosts a single window with an NSScrollView + NSTextView wired to
// NSLayoutManager (TextKit 1, NOT the modern NSTextLayoutManager).
// The text view is loaded with a hard-coded NSAttributedString
// containing one table built from NSTextTable / NSTextTableBlock,
// and ≥100 lines of plain text both above and below so the table
// sits below the initial viewport.

import AppKit
import Foundation

// Redirect stdout/stderr to a log file so we can read diagnostics
// from outside the app.
private let logPath = "/tmp/d16-spike.log"
freopen(logPath, "w", stdout)
freopen(logPath, "w", stderr)
setbuf(stdout, nil)
setbuf(stderr, nil)

// MARK: - TextKit 1 setup
//
// Build the storage / layout manager / container chain explicitly so
// we know we're on TextKit 1. Constructing NSTextView via the (frame:
// textContainer:) initializer with our pre-built container guarantees
// it adopts our NSLayoutManager rather than lazy-creating a TK2
// NSTextLayoutManager.

func makeTK1TextView(frame: NSRect) -> (NSTextView, NSScrollView) {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(
        width: frame.width,
        height: .greatestFiniteMagnitude as CGFloat))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)

    let textView = TK1TextView(frame: frame, textContainer: container)
    textView.minSize = NSSize(width: 0, height: frame.height)
    textView.maxSize = NSSize(width: .greatestFiniteMagnitude as CGFloat,
                              height: .greatestFiniteMagnitude as CGFloat)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.allowsUndo = true
    textView.isRichText = true   // need rich for paragraph attributes
    textView.font = NSFont.systemFont(ofSize: 13)
    textView.textContainerInset = NSSize(width: 12, height: 12)

    let scrollView = NSScrollView(frame: frame)
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.documentView = textView
    scrollView.autoresizingMask = [.width, .height]

    return (textView, scrollView)
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var scrollView: NSScrollView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "D16 — TextKit 1 tables spike"
        window.center()

        let content = NSView(frame: frame)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let (tv, sv) = makeTK1TextView(frame: content.bounds)
        textView = tv
        scrollView = sv
        content.addSubview(sv)

        // Verify TK1 — if `.textLayoutManager` is non-nil we picked up
        // TK2 by accident; bail loudly so we know.
        if textView.textLayoutManager != nil {
            print("FATAL: text view picked up NSTextLayoutManager (TK2)")
            print("       expected NSLayoutManager (TK1)")
            exit(1)
        }
        print("[D16] confirmed TK1: layoutManager=\(type(of: textView.layoutManager!))")

        // Load Phase-2 content if available, else Phase-1 placeholder.
        let attributed = SpikeDoc.buildAttributedString()
        textView.textStorage?.setAttributedString(attributed)

        // Force layout of everything up-front so initial paint is
        // complete. TK1 has its own version of lazy layout but it's
        // simpler to control.
        if let lm = textView.layoutManager,
           let _ = textView.textContainer {
            lm.ensureLayout(for: lm.textContainers[0])
        }

        // Window setup, present.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("[D16] viewport=\(scrollView.contentView.bounds)")
        print("[D16] textView frame=\(textView.frame)")

        // Start file-based command poller for harness-driven phase
        // verification.
        HarnessCommandPoller.shared.start(
            window: window, textView: textView, scrollView: scrollView)
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
