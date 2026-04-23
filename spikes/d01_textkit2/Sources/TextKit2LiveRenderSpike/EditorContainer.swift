import AppKit
import SwiftUI

/// SwiftUI → AppKit bridge for the TextKit 2 NSTextView.
///
/// Spike scope: host one NSTextView configured for TextKit 2; wire up
/// delegate callbacks for text change (→ re-render), selection change
/// (→ cursor-on-line tracker), and file change (→ external-edit
/// reload). A Coordinator owns the engine pieces.
struct EditorContainer: NSViewRepresentable {
    @Binding var fileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        // Build the NSTextView on the TextKit 2 code path.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = SpikeTypography.baseFont
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.wireExternalEditCallback()

        // TextKit 2 assertion — the whole spike depends on this.
        // IMPORTANT: never access `textView.layoutManager` to check for
        // TK1 — doing so lazy-creates a TK1 layout manager and silently
        // flips the code path. Rely on textLayoutManager alone. Spike
        // finding #1: this trap is real and must stay documented.
        if let tlm = textView.textLayoutManager {
            NSLog("TEXTKIT2-OK: textLayoutManager=\(tlm)")
        } else {
            NSLog("TEXTKIT2-WARNING: textLayoutManager is nil — NOT on TextKit 2")
        }

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.loadFileIfNeeded(fileURL, into: textView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        let renderer = MarkdownRenderer()
        let cursorTracker = CursorLineTracker()
        let watcher = ExternalEditWatcher()
        private(set) var loadedFileURL: URL?

        func wireExternalEditCallback() {
            watcher.onChange = { [weak self] newText in
                guard let self, let textView = self.textView else { return }
                self.reloadBuffer(with: newText, in: textView)
            }
        }

        func loadFileIfNeeded(_ url: URL?, into textView: NSTextView) {
            guard let url else {
                if loadedFileURL != nil {
                    watcher.stop()
                    loadedFileURL = nil
                    textView.string = ""
                }
                return
            }
            if loadedFileURL == url { return }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                NSLog("EditorContainer: failed to read \(url.path)")
                return
            }
            replaceAndRender(text, in: textView)
            watcher.watch(url: url)
            loadedFileURL = url
        }

        // MARK: - Text changes

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            renderCurrentText(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            cursorTracker.updateVisibility(in: textView)
        }

        // MARK: - Helpers

        private func renderCurrentText(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let source = textStorage.string
            let result = renderer.render(source)

            textStorage.beginEditing()
            // Reset to base attributes first; then apply assignments in order.
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.setAttributes([
                .font: SpikeTypography.baseFont,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)
            for assignment in result.assignments {
                let clipped = NSIntersectionRange(assignment.range, fullRange)
                if clipped.length > 0 {
                    textStorage.addAttributes(assignment.attributes, range: clipped)
                }
            }
            textStorage.endEditing()

            cursorTracker.invalidate()
            cursorTracker.updateVisibility(in: textView)
        }

        private func replaceAndRender(_ text: String, in textView: NSTextView) {
            textView.string = text
            renderCurrentText(in: textView)
        }

        private func reloadBuffer(with newText: String, in textView: NSTextView) {
            // Spike-level reconciliation: if the text on disk differs
            // from our buffer, accept the disk version and try to preserve
            // caret position by character index.
            let previousLocation = textView.selectedRange().location
            textView.string = newText
            renderCurrentText(in: textView)
            let nsText = newText as NSString
            let clamped = min(previousLocation, nsText.length)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }
    }
}
