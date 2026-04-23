import AppKit
import Foundation

/// Manages the cursor-on-line reveal — the litmus behavior for the
/// spike. When the caret is on a given logical line, delimiter ranges
/// on that line are "revealed" (shown in full font/color). When the
/// caret leaves, delimiters on the line "collapse" (small, same-color-
/// as-background to read as invisible).
///
/// Delimiter ranges are identified via the `SpikeTypography.syntaxRoleKey`
/// attribute that MarkdownRenderer stamps on them during render.
final class CursorLineTracker {

    /// The last line range we revealed. We keep this so we can re-collapse
    /// it when the caret moves elsewhere.
    private var revealedLineRange: NSRange?

    /// Update visibility given the text view's current selection.
    /// Safe to call on every selection change.
    func updateVisibility(in textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let selectedRange = textView.selectedRange()
        let nsText = textStorage.string as NSString
        guard selectedRange.location <= nsText.length else { return }

        let currentLineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))

        // If we're still on the same line as last time, nothing to do.
        if let existing = revealedLineRange, NSEqualRanges(existing, currentLineRange) {
            return
        }

        textStorage.beginEditing()

        // 1. Collapse the previously-revealed line's delimiters, if any.
        if let previous = revealedLineRange {
            applyCollapsed(to: textStorage, in: previous)
        }

        // 2. Reveal the delimiters on the current line.
        applyRevealed(to: textStorage, in: currentLineRange)

        textStorage.endEditing()

        revealedLineRange = currentLineRange
    }

    /// The tracker only knows about lines it has already seen via
    /// updateVisibility. If the document is re-rendered (new AST run),
    /// call this so the next selection-change re-reveals the current
    /// line even if the line-range numbers stayed the same.
    func invalidate() {
        revealedLineRange = nil
    }

    // MARK: - Delimiter visibility attributes

    /// Collapsed: very small font, foreground = background.
    /// Leaves the text in the storage intact (so undo/paste/external-edit
    /// all stay coherent) but effectively hides it visually.
    private func applyCollapsed(to storage: NSTextStorage, in lineRange: NSRange) {
        enumerateDelimiters(in: storage, lineRange: lineRange) { delimiterRange in
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: 0.1),
                .foregroundColor: NSColor.textBackgroundColor
            ], range: delimiterRange)
        }
    }

    /// Revealed: restore normal body font and label color for delimiters.
    private func applyRevealed(to storage: NSTextStorage, in lineRange: NSRange) {
        enumerateDelimiters(in: storage, lineRange: lineRange) { delimiterRange in
            storage.addAttributes([
                .font: SpikeTypography.baseFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: delimiterRange)
        }
    }

    private func enumerateDelimiters(
        in storage: NSTextStorage,
        lineRange: NSRange,
        _ body: (NSRange) -> Void
    ) {
        let clipped = NSIntersectionRange(
            lineRange,
            NSRange(location: 0, length: storage.length)
        )
        guard clipped.length > 0 else { return }
        storage.enumerateAttribute(SpikeTypography.syntaxRoleKey, in: clipped, options: []) { value, range, _ in
            if (value as? String) == "delimiter" {
                body(range)
            }
        }
    }
}
