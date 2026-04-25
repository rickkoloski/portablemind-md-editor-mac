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
            // D8: install the table layout delegate. It swaps in custom
            // TableRowFragment instances for paragraphs tagged with the
            // table row attachment attribute.
            let tableDelegate = TableLayoutManagerDelegate()
            context.coordinator.tableLayoutDelegate = tableDelegate
            tlm.delegate = tableDelegate
        } else {
            NSLog("TEXTKIT2-WARNING: textLayoutManager is nil — NOT on TextKit 2 code path")
        }

        // Seed the text view from the document, then render once.
        textView.string = document.source
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
        /// D8: strong ref so the NSTextLayoutManager delegate stays
        /// alive for the text view's lifetime.
        var tableLayoutDelegate: TableLayoutManagerDelegate?
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
            ruler?.invalidate()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? LiveRenderTextView else { return }
            cursorTracker.updateVisibility(in: textView)
            updateTableReveal(in: textView)
        }

        // MARK: - D8.1 table reveal

        /// Tracks which table (if any) is currently in source-reveal
        /// mode. When the caret crosses a table boundary, toggle the
        /// delegate's `revealedTables` set and invalidate the affected
        /// source ranges so TextKit 2 re-asks the delegate for
        /// fragments (grid → default or default → grid).
        private var revealedTableLayoutID: ObjectIdentifier?

        private func updateTableReveal(in textView: LiveRenderTextView) {
            guard let storage = textView.textStorage,
                  let tlm = textView.textLayoutManager,
                  let tcm = tlm.textContentManager,
                  let delegate = tlm.delegate as? TableLayoutManagerDelegate
            else { return }

            let selection = textView.selectedRange()
            let probeLocation = min(selection.location, max(0, storage.length - 1))
            let newAttachment: TableRowAttachment? = {
                guard storage.length > 0, probeLocation < storage.length else {
                    return nil
                }
                return storage.attribute(TableAttributeKeys.rowAttachmentKey,
                                         at: probeLocation,
                                         effectiveRange: nil) as? TableRowAttachment
            }()
            let newLayoutID = newAttachment.map { ObjectIdentifier($0.layout) }
            if newLayoutID == revealedTableLayoutID { return }

            // Collect (range, desired-state) so we can strip or restore
            // the grid-height paragraph style as part of the same edit
            // transaction that forces TextKit 2 to re-fragment.
            struct Target {
                let range: NSRange
                /// `true` if this table is now revealed (strip
                /// paragraph style so source mode uses natural line
                /// height); `false` if returning to grid (restore the
                /// height paragraph style per row).
                let revealed: Bool
            }
            var targets: [Target] = []
            if let oldID = revealedTableLayoutID {
                delegate.revealedTables.remove(oldID)
                if let oldRange = findTableRange(for: oldID, in: storage) {
                    targets.append(Target(range: oldRange, revealed: false))
                }
            }
            if let newID = newLayoutID, let newAttachment {
                delegate.revealedTables.insert(newID)
                targets.append(Target(
                    range: newAttachment.layout.tableRange,
                    revealed: true))
            }
            revealedTableLayoutID = newLayoutID

            // Force TextKit 2 to re-fragment. `invalidateLayout(for:)`
            // alone keeps cached fragments and the delegate never gets
            // re-called. Signaling `.editedAttributes` on the storage
            // makes NSTextContentStorage tell the layout manager that
            // attributes changed in the range, which drops cached
            // fragments and re-invokes the delegate.
            storage.beginEditing()
            for target in targets {
                let clamped = NSIntersectionRange(
                    target.range,
                    NSRange(location: 0, length: storage.length)
                )
                guard clamped.length > 0 else { continue }
                adjustParagraphStyles(in: clamped,
                                      revealed: target.revealed,
                                      storage: storage)
                storage.edited(.editedAttributes,
                               range: clamped,
                               changeInLength: 0)
                if let textRange = textRange(for: clamped, in: tcm) {
                    tlm.invalidateLayout(for: textRange)
                }
            }
            storage.endEditing()
            tlm.textViewportLayoutController.layoutViewport()
            textView.needsDisplay = true
        }

        /// When revealing: strip `.paragraphStyle` from each row so
        /// source mode uses natural line heights. When un-revealing:
        /// restore a paragraph style whose line height matches the
        /// row's grid height (same math the renderer used at initial
        /// render).
        private func adjustParagraphStyles(in tableRange: NSRange,
                                           revealed: Bool,
                                           storage: NSTextStorage) {
            storage.enumerateAttribute(
                TableAttributeKeys.rowAttachmentKey,
                in: tableRange,
                options: []
            ) { value, range, _ in
                guard let attachment = value as? TableRowAttachment else { return }
                if revealed {
                    storage.removeAttribute(.paragraphStyle, range: range)
                } else {
                    let height = paragraphHeight(for: attachment)
                    let style = NSMutableParagraphStyle()
                    style.minimumLineHeight = height
                    style.maximumLineHeight = height
                    storage.addAttribute(.paragraphStyle,
                                         value: style,
                                         range: range)
                }
            }
        }

        private func paragraphHeight(for attachment: TableRowAttachment) -> CGFloat {
            switch attachment.kind {
            case .separator:
                return 3
            case .header, .body:
                guard let idx = attachment.cellContentIndex,
                      idx < attachment.layout.rowHeight.count
                else { return 20 }
                return attachment.layout.rowHeight[idx]
            }
        }

        /// Scan storage for any row tagged with a matching layout ID
        /// so we can reconstruct the table's source range even after
        /// a re-render replaced the previous `TableLayout` instance
        /// with a new one.
        private func findTableRange(for id: ObjectIdentifier,
                                    in storage: NSTextStorage) -> NSRange? {
            var found: NSRange?
            storage.enumerateAttribute(
                TableAttributeKeys.rowAttachmentKey,
                in: NSRange(location: 0, length: storage.length),
                options: []
            ) { value, _, stop in
                if let attachment = value as? TableRowAttachment,
                   ObjectIdentifier(attachment.layout) == id {
                    found = attachment.layout.tableRange
                    stop.pointee = true
                }
            }
            return found
        }

        private func textRange(for nsRange: NSRange,
                               in tcm: NSTextContentManager) -> NSTextRange? {
            guard let start = tcm.location(tcm.documentRange.location,
                                           offsetBy: nsRange.location),
                  let end = tcm.location(start, offsetBy: nsRange.length)
            else { return nil }
            return NSTextRange(location: start, end: end)
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
