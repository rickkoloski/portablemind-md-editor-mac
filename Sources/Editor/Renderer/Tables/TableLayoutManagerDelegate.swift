import AppKit
import Foundation

/// `NSTextLayoutManagerDelegate` that intercepts paragraph layout and
/// substitutes `TableRowFragment` for paragraphs whose source range
/// carries a `TableRowAttachment`.
///
/// Retained by the `EditorContainer.Coordinator` for the text view's
/// lifetime (delegate isn't strongly held by the layout manager).
final class TableLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        if let paragraph = textElement as? NSTextParagraph,
           let attachment = tableAttachment(in: paragraph) {
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
