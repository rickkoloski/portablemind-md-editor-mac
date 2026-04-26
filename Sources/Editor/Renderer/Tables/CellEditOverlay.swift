// D13: Cell-edit overlay — NSTextView subclass mounted in-place over a
// table cell while the user edits it. Replaces D12's in-cell caret and
// selection rendering for single-line and wrapped cells.
//
// Visual design (spec §3.7): overlay frame includes the cell's full
// rect (cellInset gutter included); textContainerInset = cellInset so
// text inside the overlay sits at the same screen coords as the host
// cell render. A 2pt active-accent border draws around the cell box,
// providing the Numbers/Excel "active cell" affordance without shifting
// any text position.
//
// Keyboard handling (spec §3.10):
//   - Escape (53)                → cancel — discard overlay edits.
//   - Tab (48) / Shift+Tab       → advance to next/prev cell.
//   - Return / Enter (36 / 76)   → commit + dismiss.
//   - Other                      → super (normal text editing).

import AppKit
import Foundation

protocol CellEditOverlayDelegate: AnyObject {
    func overlayCommit(_ overlay: CellEditOverlay)
    func overlayCancel(_ overlay: CellEditOverlay)
    func overlayAdvanceTab(_ overlay: CellEditOverlay, backward: Bool)
}

final class CellEditOverlay: NSTextView {
    weak var commitDelegate: CellEditOverlayDelegate?

    /// Border thickness in points. Production uses 2.0 (spike used 2.5);
    /// CD direction (2026-04-26): "build the hard thing right" — match
    /// Numbers' subtler 2pt frame.
    static let borderThickness: CGFloat = 2.0

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = false
        allowsUndo = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        // textContainerInset is set per-show by the controller to match
        // the host's cellInset, so text inside the overlay aligns with
        // the host cell rendering. lineFragmentPadding = 0 because the
        // cell already pads via cellInset; no double padding.
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        // Active-cell affordance — Numbers / Excel pattern. Border
        // draws inside the frame edge in the cell's inset gutter, so
        // it does not push text position.
        wantsLayer = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = Self.borderThickness
        layer?.cornerRadius = 0
        // Disable noise NSTextView features that don't fit cell editing.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isGrammarCheckingEnabled = false
        isContinuousSpellCheckingEnabled = false
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            commitDelegate?.overlayCancel(self)
            return
        case 48: // Tab
            let backward = event.modifierFlags.contains(.shift)
            commitDelegate?.overlayAdvanceTab(self, backward: backward)
            return
        case 36, 76: // Return / Enter
            commitDelegate?.overlayCommit(self)
            return
        default:
            super.keyDown(with: event)
        }
    }
}
