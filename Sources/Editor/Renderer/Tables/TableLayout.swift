import AppKit
import Foundation
import Markdown

/// Pre-computed layout for one GFM table. Shared across all
/// `TableRowFragment`s of a given table — column widths are determined
/// by the widest cell in each column, summed with cell insets to
/// produce per-column x positions.
///
/// Widths are measured in points (monospace is incidental here — the
/// calculation is font-independent so future proportional body font
/// works without rewrite).
final class TableLayout {
    /// Column count (max of `columnCount` across rows, which should
    /// all be equal in a well-formed GFM table).
    let columnCount: Int

    /// Widths of each column's content area, in points.
    let contentWidths: [CGFloat]

    /// Per-column alignment derived from the table's separator row.
    /// Missing entries (trailing columns) default to `.none` → leading.
    let alignments: [Markdown.Table.ColumnAlignment?]

    /// Padding inside each cell (applied on both horizontal and
    /// vertical sides). Header-separator line thickness drawn above
    /// the first body row is added separately.
    let cellInset = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

    /// Color of the header-row bottom separator and vertical column
    /// dividers.
    let separatorColor: NSColor = NSColor.separatorColor

    /// Font for body cells.
    let bodyFont: NSFont = Typography.baseFont

    /// Font for header cells.
    let headerFont: NSFont = Typography.boldFont

    /// Total width of the grid, including column dividers.
    var totalWidth: CGFloat {
        contentWidths.reduce(0) { $0 + $1 + cellInset.left + cellInset.right }
    }

    /// Cumulative x-offset of each column's leading content edge.
    /// `columnLeadingX[i]` is the x where column i's content starts
    /// (after the cell's left inset).
    let columnLeadingX: [CGFloat]

    /// Cumulative x-offset of each column's trailing content edge.
    let columnTrailingX: [CGFloat]

    /// Per-cell pre-rendered attributed strings per row. Used by
    /// `TableRowFragment` to draw cells without re-extracting from
    /// storage on every paint. Header row and body rows only — the
    /// separator row (`|---|---|`) is not present here.
    ///
    /// `cellContentPerRow[rowIndex][columnIndex]` = attributed content.
    let cellContentPerRow: [[NSAttributedString]]

    /// Per-row computed height based on the wrapped cell contents.
    /// `rowHeight[rowIndex]` = max cell height for that row + insets.
    let rowHeight: [CGFloat]

    /// The full source-range of the table this layout represents.
    /// Used by `EditorContainer.Coordinator` to invalidate TextKit 2
    /// layout when toggling grid ↔ source reveal state (D8.1).
    let tableRange: NSRange

    init(columnCount: Int,
         contentWidths: [CGFloat],
         alignments: [Markdown.Table.ColumnAlignment?],
         cellContentPerRow: [[NSAttributedString]],
         tableRange: NSRange) {
        self.columnCount = columnCount
        self.contentWidths = contentWidths
        self.alignments = alignments
        self.cellContentPerRow = cellContentPerRow
        self.tableRange = tableRange

        var leadings: [CGFloat] = []
        var trailings: [CGFloat] = []
        var cursor: CGFloat = 0
        for w in contentWidths {
            cursor += cellInset.left
            leadings.append(cursor)
            cursor += w
            trailings.append(cursor)
            cursor += cellInset.right
        }
        self.columnLeadingX = leadings
        self.columnTrailingX = trailings

        var heights: [CGFloat] = []
        for rowCells in cellContentPerRow {
            var maxCellHeight: CGFloat = 0
            for (col, cell) in rowCells.enumerated() where col < contentWidths.count {
                let w = contentWidths[col]
                let bounds = cell.boundingRect(
                    with: CGSize(width: w, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                maxCellHeight = max(maxCellHeight, bounds.height)
            }
            heights.append(maxCellHeight + cellInset.top + cellInset.bottom)
        }
        self.rowHeight = heights
    }
}

/// Per-row data attached to the source range of each row. Carries a
/// reference to the shared `TableLayout` plus the row's kind (header,
/// separator, body) and its index within the table.
final class TableRowAttachment: NSObject {
    enum Kind {
        case header
        case separator
        case body
    }

    let layout: TableLayout
    let kind: Kind
    /// Row's index into `layout.cellContentPerRow`. `nil` for
    /// separator rows (they have no cell content).
    let cellContentIndex: Int?
    /// `true` if this row is the FIRST row of the table (used to draw
    /// the top border only once). `false` for subsequent rows.
    let isFirstRow: Bool
    /// `true` if this row is the LAST row of the table (used to draw
    /// the bottom border only once). `false` for prior rows.
    let isLastRow: Bool

    init(layout: TableLayout,
         kind: Kind,
         cellContentIndex: Int?,
         isFirstRow: Bool,
         isLastRow: Bool) {
        self.layout = layout
        self.kind = kind
        self.cellContentIndex = cellContentIndex
        self.isFirstRow = isFirstRow
        self.isLastRow = isLastRow
    }
}
