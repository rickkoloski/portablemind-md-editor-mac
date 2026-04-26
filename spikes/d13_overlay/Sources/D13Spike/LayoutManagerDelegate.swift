// Spike: NSTextLayoutManagerDelegate that returns a TableRowFragment
// for any text element whose source range carries a TableRowAttachment.

import AppKit
import Foundation

final class TableLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ tlm: NSTextLayoutManager,
                           textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        guard let textRange = textElement.elementRange,
              let tcm = tlm.textContentManager else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // Need access to attributed string of the text element to read
        // attributes — go through the content manager's storage.
        guard let storage = (tcm as? NSTextContentStorage)?.textStorage else {
            return NSTextLayoutFragment(textElement: textElement, range: textRange)
        }

        let nsRange = nsRange(from: textRange, in: tlm)
        guard nsRange.location != NSNotFound,
              nsRange.location < storage.length else {
            return NSTextLayoutFragment(textElement: textElement, range: textRange)
        }

        let attrs = storage.attributes(at: nsRange.location, effectiveRange: nil)
        if let attachment = attrs[SpikeAttributeKeys.rowAttachmentKey] as? TableRowAttachment {
            return TableRowFragment(textElement: textElement,
                                    range: textRange,
                                    attachment: attachment)
        }
        return NSTextLayoutFragment(textElement: textElement, range: textRange)
    }

    private func nsRange(from textRange: NSTextRange,
                         in tlm: NSTextLayoutManager) -> NSRange {
        guard let tcm = tlm.textContentManager else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let docStart = tcm.documentRange.location
        let loc = tlm.offset(from: docStart, to: textRange.location)
        let len = tlm.offset(from: textRange.location, to: textRange.endLocation)
        return NSRange(location: loc, length: len)
    }
}
