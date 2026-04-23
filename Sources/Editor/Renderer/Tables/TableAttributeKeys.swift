import Foundation

enum TableAttributeKeys {
    /// Attribute key applied to the source-range of each table row.
    /// When the layout-manager delegate encounters a text paragraph
    /// whose range carries this attribute, it substitutes a
    /// `TableRowFragment` that renders the row as part of a grid.
    ///
    /// Value: `TableRowAttachment` (carries the shared `TableLayout`
    /// plus row-specific info).
    static let rowAttachmentKey = NSAttributedString.Key("MdEditorTableRowAttachment")
}
