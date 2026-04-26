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
        /// D8: strong ref so the NSTextLayoutManager delegate stays
        /// alive for the text view's lifetime.
        var tableLayoutDelegate: TableLayoutManagerDelegate?
        /// D12: strong ref so the custom NSTextSelectionDataSource
        /// stays alive (the navigation holds it weakly).
        var cellSelectionDataSource: CellSelectionDataSource?
        /// D13: per-cell edit overlay controller. Mounts the overlay
        /// on single-click of a table cell.
        var cellEditController: CellEditController?
        /// D13: modal popout controller — opened via right-click menu.
        var cellEditModalController: CellEditModalController?
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

        /// D12 step 5: retired the caret-in-range auto-reveal. This
        /// method now only handles UN-reveal: when the caret leaves
        /// the currently-revealed table, snap that table back to
        /// grid mode. Reveal is triggered explicitly via
        /// `revealRow(for:in:)` from the text view's double-click.
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

            struct Target {
                let range: NSRange
                let revealed: Bool
            }
            var targets: [Target] = []
            // Only un-reveal when the caret crosses out of the
            // currently-revealed table. Un-reveal also fires when the
            // caret moves to a DIFFERENT table — but doesn't auto-
            // reveal the new one. Double-click is the only way to
            // enter source mode now.
            if let oldID = revealedTableLayoutID,
               oldID != newLayoutID {
                delegate.revealedTables.remove(oldID)
                if let oldRange = findTableRange(for: oldID, in: storage) {
                    targets.append(Target(range: oldRange, revealed: false))
                }
                revealedTableLayoutID = nil
            }
            if targets.isEmpty { return }

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

        /// D12 step 5: explicit reveal triggered by double-click on a
        /// table cell. Toggles the row's table to source mode by
        /// inserting the layout ID into `revealedTables` and forcing
        /// the affected source range to re-fragment.
        func revealRow(for attachment: TableRowAttachment,
                       in textView: LiveRenderTextView?) {
            guard let textView,
                  let storage = textView.textStorage,
                  let tlm = textView.textLayoutManager,
                  let tcm = tlm.textContentManager,
                  let delegate = tlm.delegate as? TableLayoutManagerDelegate
            else { return }
            let newID = ObjectIdentifier(attachment.layout)
            // If we're already revealing this same table, no-op.
            if revealedTableLayoutID == newID { return }
            // Un-reveal whatever was previously revealed.
            var unrevealRange: NSRange?
            if let oldID = revealedTableLayoutID {
                delegate.revealedTables.remove(oldID)
                unrevealRange = findTableRange(for: oldID, in: storage)
            }
            delegate.revealedTables.insert(newID)
            revealedTableLayoutID = newID

            storage.beginEditing()
            if let r = unrevealRange {
                let clamped = NSIntersectionRange(
                    r, NSRange(location: 0, length: storage.length))
                if clamped.length > 0 {
                    adjustParagraphStyles(in: clamped,
                                          revealed: false,
                                          storage: storage)
                    storage.edited(.editedAttributes,
                                   range: clamped,
                                   changeInLength: 0)
                    if let textRange = textRange(for: clamped, in: tcm) {
                        tlm.invalidateLayout(for: textRange)
                    }
                }
            }
            let revealRange = NSIntersectionRange(
                attachment.layout.tableRange,
                NSRange(location: 0, length: storage.length))
            if revealRange.length > 0 {
                adjustParagraphStyles(in: revealRange,
                                      revealed: true,
                                      storage: storage)
                storage.edited(.editedAttributes,
                               range: revealRange,
                               changeInLength: 0)
                if let textRange = textRange(for: revealRange, in: tcm) {
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
                } else if attachment.kind == .separator {
                    // Only separators get the line-height clamp on
                    // un-reveal — they need a 3pt-clamped line for the
                    // thin divider. Header/body rows DON'T need it
                    // (D12 routes clicks via fragment hit-test rather
                    // than line-fragment height; the clamp made the
                    // caret + selection-highlight render as full row
                    // height, which is wrong for multi-line cells).
                    let style = NSMutableParagraphStyle()
                    style.minimumLineHeight = 3
                    style.maximumLineHeight = 3
                    storage.addAttribute(.paragraphStyle,
                                         value: style,
                                         range: range)
                }
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

            // Capture scroll Y BEFORE the storage edit. The full-storage
            // re-attribute below causes TextKit 2 to re-fragment the
            // entire document, which moves the visible viewport. Without
            // this preserve+restore, every keystroke can jump the scroll
            // position by hundreds of points (D15 fix, 2026-04-26).
            let preservedScrollY: CGFloat? = textView.enclosingScrollView
                .map { $0.contentView.bounds.origin.y }

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

            // D15.1: force TextKit 2 to lay out the ENTIRE document
            // now, not lazily as scroll reveals new regions. Without
            // this, fragments outside the initial viewport keep
            // `layoutFragmentFrame.origin = (0,0)` until the viewport
            // reaches them — and during the transition the user sees
            // blank space where the table should be (CD repro:
            // scroll one detent past the visible region → only the
            // active cell-edit overlay renders, surrounding rows are
            // missing for one frame). Up-front full layout is O(N)
            // on the doc but amortizes across the whole session.
            if let tlm = textView.textLayoutManager,
               let tcm = tlm.textContentManager {
                tlm.ensureLayout(for: tcm.documentRange)
            }

            cursorTracker.invalidate()
            cursorTracker.collapseAllDelimiters(in: textView)
            cursorTracker.updateVisibility(in: textView)

            // Restore scroll Y on the next runloop tick so layout
            // settles before we override. Skip if the restore would
            // overshoot the document height (e.g., text was deleted).
            if let scrollView = textView.enclosingScrollView,
               let target = preservedScrollY {
                DispatchQueue.main.async {
                    let docHeight = scrollView.documentView?.frame.size.height
                        ?? scrollView.contentView.bounds.size.height
                    let visibleH = scrollView.contentView.bounds.size.height
                    let maxY = max(0, docHeight - visibleH)
                    let clampedY = min(max(0, target), maxY)
                    scrollView.contentView.scroll(
                        to: NSPoint(x: scrollView.contentView.bounds.origin.x,
                                    y: clampedY))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }
    }
}
