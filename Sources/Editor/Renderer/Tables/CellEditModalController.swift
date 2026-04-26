// D13 spec §3.12: Modal popout fallback. A centered NSWindow with a
// plain NSTextView for editing the cell's source content. Always-
// available power option AND the future home for content the overlay's
// math can't handle (inline images, complex inline markdown).
//
// V1: explicit user choice via right-click → "Edit Cell in Popout…".
// Auto-detection of unhandled content types is V1.x.
//
// Lifecycle:
//   - openModal(forCellRange:originalContent:rowLabel:colLabel:host:render:)
//     centered ~600×400 window, content un-escapes \| → | for display.
//   - Save (button or ⌘+Return) → applyCommit (re-escape + splice +
//     re-render).
//   - Cancel (button or Escape) → close without splice.
//
// Handoff with overlay (spec §3.13) is enforced by the menu-action
// hook in LiveRenderTextView: if an overlay is active, the menu commits
// it BEFORE this modal opens.

import AppKit
import Foundation

@MainActor
final class CellEditModalController: NSObject, NSWindowDelegate {
    private weak var hostView: NSTextView?
    private let renderHook: (NSTextView) -> Void

    private var window: NSWindow?
    private var textView: NSTextView?
    private var activeCellRange: NSRange = NSRange(location: 0, length: 0)

    init(hostView: NSTextView, renderHook: @escaping (NSTextView) -> Void) {
        self.hostView = hostView
        self.renderHook = renderHook
        super.init()
    }

    var isActive: Bool { window != nil }

    func openModal(forCellRange cellRange: NSRange,
                   originalContent: String,
                   rowLabel: String,
                   colLabel: String) {
        // If a modal is already open, treat this as a request to
        // commit the current modal first.
        if isActive { applyCommit() }

        self.activeCellRange = cellRange
        // Un-escape pipes for display: \| → |, \\ → \.
        // Production round-trip: re-escape on commit.
        let displayContent = originalContent
            .replacingOccurrences(of: "\\\\", with: "\u{0001}")  // sentinel
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\u{0001}", with: "\\")

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        win.title = "Edit Cell — \(rowLabel) \(colLabel)"
        win.delegate = self
        win.isReleasedWhenClosed = false

        // Build content view: scroll-hosted NSTextView + Save / Cancel.
        let content = NSView(frame: win.contentRect(forFrameRect: win.frame))
        content.autoresizesSubviews = true

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let tv = NSTextView()
        tv.string = displayContent
        tv.isEditable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 8, height: 8)

        scroll.documentView = tv

        let saveButton = NSButton(title: "Save",
                                  target: self,
                                  action: #selector(saveAction(_:)))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.keyEquivalent = "\r"  // Return
        saveButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: "Cancel",
                                    target: self,
                                    action: #selector(cancelAction(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\u{1B}"  // Escape
        cancelButton.bezelStyle = .rounded

        content.addSubview(scroll)
        content.addSubview(saveButton)
        content.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        win.contentView = content

        // Center on key screen.
        win.center()

        self.window = win
        self.textView = tv

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(tv)
    }

    @objc private func saveAction(_ sender: Any?) {
        applyCommit()
    }

    @objc private func cancelAction(_ sender: Any?) {
        close()
    }

    private func applyCommit() {
        guard let host = hostView,
              let storage = host.textStorage,
              let tv = textView else {
            close()
            return
        }
        // Re-escape on commit. Same order as overlay's commit.
        let escaped = tv.string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
        storage.replaceCharacters(in: activeCellRange, with: escaped)
        renderHook(host)
        close()
    }

    private func close() {
        window?.close()
        window = nil
        textView = nil
        activeCellRange = NSRange(location: 0, length: 0)
    }

    // NSWindowDelegate — close button == cancel.
    func windowWillClose(_ notification: Notification) {
        if window != nil {
            // Window is closing for any reason (close button, NSApp);
            // clear our refs.
            window = nil
            textView = nil
            activeCellRange = NSRange(location: 0, length: 0)
        }
    }
}
