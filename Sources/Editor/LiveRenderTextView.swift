import AppKit
import Foundation

/// NSTextView subclass for the live-render markdown editor.
///
/// **TextKit 1 host** as of D17. Constructed via the explicit storage
/// → layout-manager → container chain so the text view never picks up
/// `NSTextLayoutManager` (TK2). The pre-D17 standard prohibited
/// touching `.layoutManager` because that demoted us from the TK2
/// path; post-D17 the standard is inverted — we are deliberately on
/// TK1 (see `docs/current_work/specs/d17_textkit1_migration_spec.md`
/// § 2 for citations) and `.layoutManager` is the supported path.
///
/// Cell-aware behavior for table rows (Tab/Shift+Tab between cells)
/// is reinstated atop TK1 in D17 phase 6. This file is intentionally
/// minimal post-phase-3+4 cleanup; only TK1 init, scroll suppression
/// (a D15.1 carryover that phase 5 retires), and debug-HUD click
/// recording remain.
final class LiveRenderTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    /// D17 phase 1 — designated init that builds an explicit TK1
    /// text-storage chain. Use this everywhere instead of relying on
    /// `NSTextView`'s default initializer, which on macOS 12+ may
    /// pick up `NSTextLayoutManager` (TK2).
    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        // Runtime trip wire: confirm we did not accidentally end up
        // on TK2. If this assertion fires the construction chain
        // above is wrong.
        assert(self.textLayoutManager == nil,
               "LiveRenderTextView ended up on TextKit 2 — D17 standard violated")
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        recordClickForDebugProbe(event: event)
        super.mouseDown(with: event)
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        if let binding = KeyboardBindings.match(event: event),
           CommandDispatcher.shared.dispatch(
            identifier: binding.commandIdentifier, in: self) {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Debug HUD instrumentation

    /// Feed click coords + resolved-paragraph info into
    /// `DebugProbe.shared`. Cheap and side-effect-free; the HUD only
    /// renders when toggled on in View menu.
    private func recordClickForDebugProbe(event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerY = viewPoint.y - textContainerInset.height
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: containerY)

        var tableRow: Int = -1
        var tableCol: Int = -1
        var fragKind: String = "—"
        var fragOriginY: CGFloat = 0
        var fragmentClass: String = "—"

        if let lm = layoutManager,
           let container = textContainer,
           lm.numberOfGlyphs > 0 {
            let glyphIndex = lm.glyphIndex(
                for: containerPoint, in: container,
                fractionOfDistanceThroughGlyph: nil)
            let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
            // Line-fragment rect for fragOriginY readout.
            let safeGlyphIndex = min(glyphIndex, lm.numberOfGlyphs - 1)
            var effective: NSRange = NSRange(location: 0, length: 0)
            let rect = lm.lineFragmentRect(
                forGlyphAt: safeGlyphIndex,
                effectiveRange: &effective)
            fragOriginY = rect.origin.y
            fragmentClass = "NSTextLineFragment"

            // Detect cell paragraph from paragraphStyle.textBlocks.
            if let storage = textStorage,
               charIndex < storage.length {
                let attrs = storage.attributes(at: charIndex,
                                               effectiveRange: nil)
                if let pStyle = attrs[.paragraphStyle] as? NSParagraphStyle,
                   let block = pStyle.textBlocks.first(where: {
                       $0 is NSTextTableBlock
                   }) as? NSTextTableBlock {
                    fragKind = "tbl"
                    tableRow = block.startingRow
                    tableCol = block.startingColumn
                } else {
                    fragKind = "para"
                }
            }
        }

        let line = lineNumberForOffset(containerPoint: containerPoint)
        DebugProbe.shared.recordClick(
            viewPoint: viewPoint,
            containerY: containerY,
            line: line,
            fragKind: fragKind,
            fragOriginY: fragOriginY,
            tableRow: tableRow,
            tableCol: tableCol,
            fragmentClass: fragmentClass)
    }

    /// 1-based line number at the click point, derived from glyph
    /// position. Unlike pre-D17 (which used TK2 fragment ranges),
    /// the line number is computed by counting newlines in the
    /// rendered storage up to the click's character index. Cell
    /// paragraphs each count as their own logical line in storage —
    /// the value is reasonable for the HUD but does not match
    /// markdown source line numbers when tables are present.
    private func lineNumberForOffset(containerPoint: NSPoint) -> Int {
        guard let lm = layoutManager,
              let container = textContainer,
              lm.numberOfGlyphs > 0 else {
            return 0
        }
        let glyphIndex = lm.glyphIndex(
            for: containerPoint, in: container,
            fractionOfDistanceThroughGlyph: nil)
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        let source = self.string as NSString
        var line = 1
        var i = 0
        let limit = min(charIndex, source.length)
        while i < limit {
            if source.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }
}
