import AppKit
import Foundation

/// Manages the cursor-on-line reveal. When the caret is on a given
/// logical line, delimiter ranges on that line are "revealed" (shown
/// in full font/color). When the caret leaves, delimiters on the line
/// "collapse" (0.1pt font, foreground = background → visually invisible
/// while leaving source text intact).
///
/// D2 adds `collapseAllDelimiters(in:)` for finding #2: the initial
/// render should pre-collapse the whole document so readers see the
/// formatted result first, with source revealed only on caret entry.
final class CursorLineTracker {
    private var revealedLineRange: NSRange?

    /// Pre-collapse every delimiter-tagged range across the full text
    /// storage. Called once after each full re-render so the initial
    /// (pre-cursor-movement) view shows formatted content, not source.
    func collapseAllDelimiters(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(Typography.syntaxRoleKey, in: fullRange, options: []) { value, range, _ in
            if (value as? String) == "delimiter" {
                applyCollapsed(to: storage, range: range)
            }
        }
        storage.endEditing()
        revealedLineRange = nil
    }

    /// Update delimiter visibility given the text view's current
    /// selection. Safe to call on every selection change.
    func updateVisibility(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selectedRange = textView.selectedRange()
        let nsText = storage.string as NSString
        guard selectedRange.location <= nsText.length else { return }

        // Default: current line is the paragraph containing the caret.
        var currentLineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))

        // Reveal-scope extension: if the caret's character carries a
        // revealScopeKey attribute, use its attached NSRange instead.
        // This is how fenced code blocks reveal their fence lines when
        // the caret enters the (line-separated) content.
        let scopeProbeIndex = min(selectedRange.location, max(0, storage.length - 1))
        if storage.length > 0,
           let scope = storage.attribute(Typography.revealScopeKey, at: scopeProbeIndex, effectiveRange: nil) as? NSValue {
            currentLineRange = scope.rangeValue
        }

        if let existing = revealedLineRange, NSEqualRanges(existing, currentLineRange) {
            return
        }

        storage.beginEditing()

        if let previous = revealedLineRange {
            enumerateDelimiters(in: storage, lineRange: previous) { delimiterRange in
                applyCollapsed(to: storage, range: delimiterRange)
            }
        }

        enumerateDelimiters(in: storage, lineRange: currentLineRange) { delimiterRange in
            applyRevealed(to: storage, range: delimiterRange)
        }

        storage.endEditing()
        revealedLineRange = currentLineRange
    }

    /// Called after a full re-render so the next selection-change
    /// refreshes the current line even if line-range numbers match.
    func invalidate() {
        revealedLineRange = nil
    }

    // MARK: - Attribute application

    private func applyCollapsed(to storage: NSTextStorage, range: NSRange) {
        storage.addAttributes([
            .font: NSFont.systemFont(ofSize: 0.1),
            .foregroundColor: NSColor.textBackgroundColor
        ], range: range)
    }

    private func applyRevealed(to storage: NSTextStorage, range: NSRange) {
        storage.addAttributes([
            .font: Typography.baseFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: range)
    }

    private func enumerateDelimiters(
        in storage: NSTextStorage,
        lineRange: NSRange,
        _ body: (NSRange) -> Void
    ) {
        let clipped = NSIntersectionRange(lineRange, NSRange(location: 0, length: storage.length))
        guard clipped.length > 0 else { return }
        storage.enumerateAttribute(Typography.syntaxRoleKey, in: clipped, options: []) { value, range, _ in
            if (value as? String) == "delimiter" {
                body(range)
            }
        }
    }
}
