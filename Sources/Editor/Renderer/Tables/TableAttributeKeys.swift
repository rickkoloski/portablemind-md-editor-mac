import Foundation

enum TableAttributeKeys {
    /// Attribute key applied to the source-range of each table row.
    /// When the layout-manager delegate encounters a text paragraph
    /// whose range carries this attribute, it substitutes a
    /// `TableRowFragment` that renders the row as part of a grid.
    ///
    /// Value: `TableRowAttachment` (carries the shared `TableLayout`
    /// plus row-specific info).
    ///
    /// **TK2 vintage** — retired in D17. Kept only because `TableLayout`
    /// and `TableRowAttachment` source files remain in the tree until
    /// phase 3 deletes them.
    static let rowAttachmentKey = NSAttributedString.Key("MdEditorTableRowAttachment")

    /// D17 — every paragraph in the rendered text storage carries this
    /// attribute (NSValue wrapping NSRange). Value points to the
    /// paragraph's contribution in `document.source`. On user edit,
    /// `textDidChange` looks up the affected paragraph's source range
    /// and splices the paragraph's current text into source at that
    /// location, keeping the markdown canonical without a full re-
    /// render. Resets each render cycle.
    static let paragraphSourceRangeKey = NSAttributedString.Key("D17.paragraphSourceRange")

    /// D17 — applied to every cell paragraph within a TK1 NSTextTable.
    /// Value (NSValue wrapping NSRange) points to the cell's source
    /// range — between pipes, content only, no surrounding whitespace.
    /// Where present, this OVERRIDES `paragraphSourceRangeKey` for
    /// edit propagation: edits inside the cell paragraph splice into
    /// the cell range so surrounding pipe characters in the markdown
    /// source stay intact.
    static let cellSourceRangeKey = NSAttributedString.Key("D17.cellSourceRange")
}
