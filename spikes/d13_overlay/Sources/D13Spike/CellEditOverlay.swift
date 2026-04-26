// CellEditOverlay — NSTextView subclass mounted in-place over a cell
// during edit. Captures Tab/Shift+Tab/Enter/Escape so the controller
// can commit / cancel / advance.

import AppKit
import Foundation

protocol CellEditOverlayDelegate: AnyObject {
    func overlayCommit(_ overlay: CellEditOverlay)
    func overlayCancel(_ overlay: CellEditOverlay)
    func overlayAdvanceTab(_ overlay: CellEditOverlay, backward: Bool)
}

final class CellEditOverlay: NSTextView {
    weak var commitDelegate: CellEditOverlayDelegate?

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
        // the cell's cellInset, so text inside the overlay aligns with
        // the host's cell rendering.
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        // Active-cell frame — Numbers/Excel pattern. Border thickness
        // and color tuned by the controller per-show.
        wantsLayer = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2.5
        layer?.cornerRadius = 0
    }

    override func keyDown(with event: NSEvent) {
        // Escape → cancel.
        if event.keyCode == 53 {
            commitDelegate?.overlayCancel(self)
            return
        }
        // Tab / Shift+Tab → advance.
        if event.keyCode == 48 {
            let backward = event.modifierFlags.contains(.shift)
            commitDelegate?.overlayAdvanceTab(self, backward: backward)
            return
        }
        // Enter / Return → commit.
        if event.keyCode == 36 || event.keyCode == 76 {
            commitDelegate?.overlayCommit(self)
            return
        }
        super.keyDown(with: event)
    }
}
