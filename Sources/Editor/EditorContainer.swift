import AppKit
import SwiftUI

/// SwiftUI → AppKit bridge hosting the TextKit 2 live-render editor.
///
/// A Coordinator owns the renderer, cursor tracker, and file watcher.
/// The container surfaces only what SwiftUI needs: a file-URL binding.
///
/// IMPORTANT (`docs/engineering-standards_ref.md` §2.2): this file
/// never references `NSTextView.layoutManager`. Only `textLayoutManager`
/// is read. Accessing `.layoutManager` lazy-creates a TextKit 1 manager
/// and flips the code path — the whole app's renderer depends on
/// being in the TextKit 2 path.
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

        let textView = LiveRenderTextView(usingTextLayoutManager: true)
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = Typography.baseFont
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.autoresizingMask = [.width]
        textView.setAccessibilityIdentifier(AccessibilityIdentifiers.mainEditor)

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.wireExternalEditCallback()

        if let tlm = textView.textLayoutManager {
            NSLog("TEXTKIT2-OK: textLayoutManager=\(tlm)")
        } else {
            NSLog("TEXTKIT2-WARNING: textLayoutManager is nil — NOT on TextKit 2 code path")
        }

        // Publish this text view as the active dispatch target so the
        // global SwiftUI toolbar (and View menu) can route commands to
        // it. Single-window shortcut per D5 plan; migrate to
        // @FocusedValue when multi-window lands.
        EditorDispatcherRegistry.shared.register(for: textView)

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? LiveRenderTextView else { return }
        context.coordinator.loadFileIfNeeded(fileURL, into: textView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: LiveRenderTextView?
        let cursorTracker = CursorLineTracker()
        let watcher = ExternalEditWatcher()
        private(set) var loadedFileURL: URL?
        // Default to markdown so the untitled/blank buffer live-renders
        // without requiring the user to open a file first. When a file
        // is opened, loadFileIfNeeded reassigns based on its extension.
        private var documentType: (any DocumentType)? = MarkdownDocumentType()

        func wireExternalEditCallback() {
            watcher.onChange = { [weak self] newText in
                guard let self, let textView = self.textView else { return }
                self.reloadBuffer(with: newText, in: textView)
            }
        }

        func loadFileIfNeeded(_ url: URL?, into textView: LiveRenderTextView) {
            guard let url else {
                if loadedFileURL != nil {
                    watcher.stop()
                    loadedFileURL = nil
                    documentType = nil
                    textView.string = ""
                }
                return
            }
            if loadedFileURL == url { return }

            guard let type = DocumentTypeRegistry.shared.type(for: url) else {
                NSLog("EditorContainer: no registered DocumentType for \(url.lastPathComponent)")
                return
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                NSLog("EditorContainer: failed to read \(url.path)")
                return
            }
            documentType = type
            replaceAndRender(text, in: textView)
            watcher.watch(url: url)
            loadedFileURL = url
        }

        // MARK: - Text changes

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? LiveRenderTextView else { return }
            renderCurrentText(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? LiveRenderTextView else { return }
            cursorTracker.updateVisibility(in: textView)
        }

        // MARK: - Helpers

        private func renderCurrentText(in textView: LiveRenderTextView) {
            guard let textStorage = textView.textStorage,
                  let type = documentType else { return }
            let source = textStorage.string
            let result = type.render(source)

            textStorage.beginEditing()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.setAttributes([
                .font: Typography.baseFont,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)
            for assignment in result.assignments {
                let clipped = NSIntersectionRange(assignment.range, fullRange)
                if clipped.length > 0 {
                    textStorage.addAttributes(assignment.attributes, range: clipped)
                }
            }
            textStorage.endEditing()

            // Finding #2 fix: after a full re-render, pre-collapse every
            // delimiter across the whole document. The cursor tracker
            // then reveals only the current line on the next selection
            // change. This gives readers the formatted result on open,
            // with source revealed only on caret entry.
            cursorTracker.invalidate()
            cursorTracker.collapseAllDelimiters(in: textView)
            cursorTracker.updateVisibility(in: textView)
        }

        private func replaceAndRender(_ text: String, in textView: LiveRenderTextView) {
            textView.string = text
            renderCurrentText(in: textView)
        }

        private func reloadBuffer(with newText: String, in textView: LiveRenderTextView) {
            let previousLocation = textView.selectedRange().location
            textView.string = newText
            renderCurrentText(in: textView)
            let nsText = newText as NSString
            let clamped = min(previousLocation, nsText.length)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }
    }
}
