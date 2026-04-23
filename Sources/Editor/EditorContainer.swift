import AppKit
import Combine
import SwiftUI

/// SwiftUI → AppKit bridge hosting the TextKit 2 live-render editor
/// for a single `EditorDocument`.
///
/// D6 refactor: takes an `EditorDocument` reference instead of a
/// fileURL binding. `WorkspaceView` gives each EditorContainer a
/// stable `.id(doc.id)` so SwiftUI rebuilds the container (and thus
/// the NSTextView) when the focused document changes. Keeps state
/// cleanly scoped per-document without having to manage cross-doc
/// swapping inside a single NSTextView.
///
/// IMPORTANT (`docs/engineering-standards_ref.md` §2.2): this file
/// never references `NSTextView.layoutManager`. Only `textLayoutManager`
/// is read. Accessing `.layoutManager` lazy-creates a TextKit 1 manager
/// and flips the code path — the whole app's renderer depends on
/// being in the TextKit 2 path.
struct EditorContainer: NSViewRepresentable {
    @ObservedObject var document: EditorDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
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
        context.coordinator.wireDocumentSubscription()

        if let tlm = textView.textLayoutManager {
            NSLog("TEXTKIT2-OK: textLayoutManager=\(tlm)")
        } else {
            NSLog("TEXTKIT2-WARNING: textLayoutManager is nil — NOT on TextKit 2 code path")
        }

        // Seed the text view from the document, then render once.
        textView.string = document.source
        context.coordinator.renderCurrentText(in: textView)

        // Publish this text view as the active dispatch target so the
        // global toolbar / menu commands route here.
        EditorDispatcherRegistry.shared.register(for: textView)

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Focused-document changes rebuild this view via the
        // `.id(doc.id)` modifier on WorkspaceView's detail. No
        // cross-document swap here. Within-document state changes
        // (text reloaded from disk, etc.) flow through the Combine
        // subscription wired in `wireDocumentSubscription()`.
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: LiveRenderTextView?
        let cursorTracker = CursorLineTracker()
        private let document: EditorDocument
        private var cancellables: Set<AnyCancellable> = []

        init(document: EditorDocument) {
            self.document = document
        }

        func wireDocumentSubscription() {
            // When the document's source changes externally (e.g., an
            // agent writes to the file), reflect it into the text view
            // while preserving caret position on unchanged prefix.
            document.$source
                .dropFirst()
                .sink { [weak self] newText in
                    guard let self, let textView = self.textView else { return }
                    if textView.string != newText {
                        let previousLocation = textView.selectedRange().location
                        textView.string = newText
                        self.renderCurrentText(in: textView)
                        let clamped = min(previousLocation, (newText as NSString).length)
                        textView.setSelectedRange(NSRange(location: clamped, length: 0))
                    }
                }
                .store(in: &cancellables)

            // D9: apply pending caret focus requests (from CLI or URL
            // scheme) after the text view is seeded and laid out. We
            // don't dropFirst — @Published replays the current value on
            // subscribe, so a target set before Container creation is
            // honored. The async hop pushes the apply past initial
            // layout on fresh opens so scrollRangeToVisible has real
            // geometry to work against.
            document.$pendingFocusTarget
                .sink { [weak self] target in
                    guard let self, let target else { return }
                    self.scheduleApply(target)
                }
                .store(in: &cancellables)
        }

        /// Defer the focus-target apply until the text view is
        /// attached to a window and has completed an initial layout
        /// pass. TextKit 2's `scrollRangeToVisible` silently no-ops if
        /// the view isn't yet onscreen — which is exactly the case
        /// during the first runloop tick after `makeNSView`.
        /// Retry a bounded number of times before giving up.
        private func scheduleApply(_ target: EditorFocusTarget, attempt: Int = 0) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                if textView.window == nil {
                    if attempt < 30 { // ~30 * 16ms ≈ 0.5s ceiling
                        self.scheduleApply(target, attempt: attempt + 1)
                    }
                    return
                }
                // Force TextKit 2 layout for the visible viewport so
                // scrollRangeToVisible has real geometry.
                if let tlm = textView.textLayoutManager,
                   let content = tlm.textContentManager {
                    tlm.ensureLayout(for: content.documentRange)
                }
                self.apply(focusTarget: target, in: textView)
                // Clearing here published-changes-in-view-update if we
                // were still in a SwiftUI update. Hop once more.
                DispatchQueue.main.async {
                    self.document.pendingFocusTarget = nil
                }
            }
        }

        private func apply(focusTarget target: EditorFocusTarget,
                           in textView: LiveRenderTextView) {
            switch target {
            case let .caret(line, column):
                let location = textView.string.nsLocation(forLine: line, column: column)
                let range = NSRange(location: location, length: 0)
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
            }
        }

        // MARK: - Text changes from the user

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? LiveRenderTextView else { return }
            // Write back to the document so the TabStore and any
            // persistence layer stay in sync. Equality check avoids
            // the Combine loop with wireDocumentSubscription's sink.
            let current = textView.string
            if document.source != current {
                document.source = current
            }
            renderCurrentText(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? LiveRenderTextView else { return }
            cursorTracker.updateVisibility(in: textView)
        }

        // MARK: - Rendering

        func renderCurrentText(in textView: LiveRenderTextView) {
            guard let textStorage = textView.textStorage else { return }
            let source = textStorage.string
            let result = document.documentType.render(source)

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

            cursorTracker.invalidate()
            cursorTracker.collapseAllDelimiters(in: textView)
            cursorTracker.updateVisibility(in: textView)
        }
    }
}
