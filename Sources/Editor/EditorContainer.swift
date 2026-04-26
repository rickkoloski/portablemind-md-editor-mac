import AppKit
import Combine
import SwiftUI

/// SwiftUI → AppKit bridge hosting the live-render editor for a
/// single `EditorDocument`.
///
/// D6 refactor: takes an `EditorDocument` reference instead of a
/// fileURL binding. `WorkspaceView` gives each EditorContainer a
/// stable `.id(doc.id)` so SwiftUI rebuilds the container (and thus
/// the NSTextView) when the focused document changes. Keeps state
/// cleanly scoped per-document without having to manage cross-doc
/// swapping inside a single NSTextView.
///
/// **TextKit 1 host** as of D17. The explicit init chain on
/// `LiveRenderTextView` ensures `textLayoutManager` is never present;
/// the runtime assert in that init is the trip wire. See
/// `docs/current_work/specs/d17_textkit1_migration_spec.md` § 2.
struct EditorContainer: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    @ObservedObject var settings: AppSettings = .shared

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

        let textView = LiveRenderTextView()
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

        // D17 phase 1: TK2-specific setup retired (table layout
        // delegate, cell-selection data source, double-click reveal,
        // cell-edit overlay/modal). Tables will render incorrectly
        // until phase 2 ports the markdown renderer to emit native
        // NSTextTable attributes; non-table content renders normally.
        // Tripwire: assertion in LiveRenderTextView.init() will fire
        // if the text view ends up on TK2 by accident.

        // Seed the text view from the document. The renderer reads
        // `document.source` directly and produces a fully-attributed
        // string that replaces storage; we don't pre-load `string`
        // here because that would seed the storage with raw markdown
        // (pipes etc.) which the renderer would then have to re-
        // initialize anyway.
        context.coordinator.renderCurrentText(in: textView)

        // Publish this text view as the active dispatch target so the
        // global toolbar / menu commands route here.
        EditorDispatcherRegistry.shared.register(for: textView)

        // TEST-HARNESS: register this text view with the debug harness
        // sink so the autonomous test driver can inspect / drive editor
        // state. Compiled out of release builds.
        #if DEBUG
        HarnessActiveSink.shared.register(textView)
        #endif

        scroll.documentView = textView
        syncLineNumberRuler(in: scroll, textView: textView,
                            coordinator: context.coordinator)

        // D15.1 — feed scroll position into the debug HUD probe.
        // Observe `boundsDidChange` on the contentView (clip view); set
        // contentView.postsBoundsChangedNotifications first.
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView,
            queue: .main
        ) { [weak scroll] _ in
            guard let scroll else { return }
            DebugProbe.shared.recordScroll(scroll.contentView.bounds.origin.y)
        }
        DebugProbe.shared.recordScroll(scroll.contentView.bounds.origin.y)

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Focused-document changes rebuild this view via the
        // `.id(doc.id)` modifier on WorkspaceView's detail. No
        // cross-document swap here. Within-document state changes
        // (text reloaded from disk, etc.) flow through the Combine
        // subscription wired in `wireDocumentSubscription()`.
        if let textView = nsView.documentView as? LiveRenderTextView {
            syncLineNumberRuler(in: nsView, textView: textView,
                                coordinator: context.coordinator)
        }
    }

    /// Attach or detach the line-number ruler based on current
    /// settings. Idempotent — called from both makeNSView and
    /// updateNSView.
    private func syncLineNumberRuler(in scroll: NSScrollView,
                                     textView: LiveRenderTextView,
                                     coordinator: Coordinator) {
        if settings.lineNumbersVisible {
            if coordinator.ruler == nil {
                scroll.hasVerticalRuler = true
                let ruler = LineNumberRulerView(textView: textView)
                scroll.verticalRulerView = ruler
                scroll.rulersVisible = true
                coordinator.ruler = ruler
            }
        } else {
            if coordinator.ruler != nil {
                scroll.rulersVisible = false
                scroll.verticalRulerView = nil
                scroll.hasVerticalRuler = false
                coordinator.ruler = nil
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: LiveRenderTextView?
        var ruler: LineNumberRulerView?
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
                    // D17: when the source changes BECAUSE we just
                    // serialized a user edit (textDidChange path),
                    // skip the re-render — storage is already correct.
                    // Re-rendering would replace storage and reset
                    // the caret.
                    if self.isApplyingUserEditToSource { return }
                    self.renderCurrentText(in: textView)
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
            guard let textView = notification.object as? LiveRenderTextView,
                  let storage = textView.textStorage else { return }
            // D17: storage is the rendered form (cell paragraphs for
            // tables, source-text for non-tables). Serialize the
            // storage back to canonical markdown and update
            // `document.source`. We deliberately do NOT call
            // `renderCurrentText` here — that would replace storage
            // and reset the user's caret on every keystroke.
            // Storage stays internally consistent for editing; source
            // is updated incrementally so save/load round-trip
            // correctly.
            let serialized = TK1Serializer.serialize(storage)
            if document.source != serialized {
                // Suppress the Combine sink loop: setting source
                // would normally trigger wireDocumentSubscription's
                // sink → renderCurrentText → reset caret. Mark this
                // assignment as "from-edit" so the sink can short-
                // circuit.
                isApplyingUserEditToSource = true
                defer { isApplyingUserEditToSource = false }
                document.source = serialized
            }
            ruler?.invalidate()
        }

        /// D17 — set during `textDidChange` while we sync the user's
        /// edit back into `document.source`. The wireDocumentSubscription
        /// sink reads this to skip the re-render that would otherwise
        /// fire on every keystroke and reset the caret.
        var isApplyingUserEditToSource: Bool = false

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? LiveRenderTextView else { return }
            cursorTracker.updateVisibility(in: textView)
        }

        // MARK: - Rendering

        func renderCurrentText(in textView: LiveRenderTextView) {
            guard let textStorage = textView.textStorage else { return }
            // D17: render from `document.source` (the canonical
            // markdown), NOT from `textStorage.string`. After the user
            // types in a cell, storage's text differs from source for
            // the table region; rendering from storage here would
            // double-encode. The renderer is called only on full
            // refresh paths (initial open, external file change), so
            // pulling source directly is the right semantic.
            let source = document.source
            let result = document.documentType.render(source)

            // Preserve the user's selection across the storage replace
            // so cursor position is stable when an external edit fires
            // a re-render.
            let prevSelection = textView.selectedRange()

            textStorage.beginEditing()
            textStorage.setAttributedString(result.attributedString)
            textStorage.endEditing()

            // Clamp the selection to the new storage length and re-
            // apply. This is best-effort — storage length may have
            // changed (table replacements shift offsets); for D17's
            // full-refresh paths the user wasn't actively typing so
            // exact preservation isn't essential.
            let clampedLoc = min(prevSelection.location, textStorage.length)
            let clampedLen = min(prevSelection.length,
                                 textStorage.length - clampedLoc)
            textView.setSelectedRange(NSRange(location: clampedLoc,
                                              length: clampedLen))

            cursorTracker.invalidate()
            cursorTracker.collapseAllDelimiters(in: textView)
            cursorTracker.updateVisibility(in: textView)
        }
    }
}
