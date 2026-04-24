import AppKit
import Foundation

/// `NSTextLayoutManagerDelegate` that intercepts paragraph layout and
/// substitutes `TableRowFragment` for paragraphs whose source range
/// carries a `TableRowAttachment`.
///
/// D8.1 — the delegate honors `revealedTables`: when a table's layout
/// ID is in the set, the delegate returns a default fragment for its
/// rows so pipe-source becomes visible. `EditorContainer.Coordinator`
/// updates the set based on caret position.
///
/// Retained by the `EditorContainer.Coordinator` for the text view's
/// lifetime (delegate isn't strongly held by the layout manager).
final class TableLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    /// Tables currently in source-reveal mode. Keyed by
    /// `ObjectIdentifier` of the shared `TableLayout`. Rows of the
    /// same table share the same layout, so one entry reveals/hides
    /// all rows.
    var revealedTables: Set<ObjectIdentifier> = []

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        if let paragraph = textElement as? NSTextParagraph,
           let attachment = tableAttachment(in: paragraph) {
            if revealedTables.contains(ObjectIdentifier(attachment.layout)) {
                return NSTextLayoutFragment(
                    textElement: textElement,
                    range: textElement.elementRange)
            }
            return TableRowFragment(textElement: textElement,
                                    range: textElement.elementRange,
                                    attachment: attachment)
        }
        return NSTextLayoutFragment(textElement: textElement,
                                    range: textElement.elementRange)
    }

    private func tableAttachment(in paragraph: NSTextParagraph) -> TableRowAttachment? {
        let attr = paragraph.attributedString
        guard attr.length > 0 else { return nil }
        return attr.attribute(TableAttributeKeys.rowAttachmentKey,
                              at: 0, effectiveRange: nil) as? TableRowAttachment
    }
}
