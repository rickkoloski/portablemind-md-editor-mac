// SpikeDoc — hard-coded NSAttributedString containing:
//   - Plain-text preamble (≥100 lines) so the table sits below the
//     initial viewport on a normal-sized window.
//   - One TextKit 1 table built via NSTextTable + NSTextTableBlock,
//     4 columns, 12 body rows + header row. One body row's content
//     is intentionally long enough to wrap at the configured column
//     width, so Scenario 4 (wrapped-cell click) has data to test.
//   - Plain-text postamble so the table is in the doc's middle.
//
// Cell ranges are recorded into TK1TextView.cellRanges so the
// click-to-caret scenarios can verify which cell the caret lands in.

import AppKit

enum SpikeDoc {
    static let columnCount = 4
    /// Roughly the column-width assumption used to construct the
    /// table; actual wrap depends on TK1's layout once it has the
    /// container width. The "long row" content is sized to wrap.
    static let columnContentWidth: CGFloat = 200

    static func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Preamble — 100 short lines so the table is below the
        // initial viewport. Number them so we can see scrolling.
        for i in 0..<100 {
            let s = "preamble line \(i)\n"
            result.append(NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: 13)
            ]))
        }

        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13)
        ]))

        // Build the table.
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.collapsesBorders = false
        table.hidesEmptyCells = false

        let header = ["#", "Item", "Description", "Status"]
        let rows: [[String]] = [
            ["1", "alpha", "short body row", "ok"],
            ["2", "beta",  "medium length cell content here", "ok"],
            ["3", "gamma", "another short", "pending"],
            // intentional WRAP target — Scenario 4. Content long
            // enough to wrap at columnContentWidth ≈ 200pt.
            ["4", "delta", "this is a deliberately long cell body so that TextKit 1 has to wrap it onto a second visual line, giving us a chance to click on line two and verify the caret lands in the latter half of the cell range", "wrap-row"],
            ["5", "epsilon", "another short row", "ok"],
            ["6", "zeta", "filler", "ok"],
            ["7", "eta", "filler row content", "ok"],
            ["8", "theta", "yet more content", "ok"],
            ["9", "iota", "still going", "ok"],
            ["10", "kappa", "approaching the end", "ok"],
            ["11", "lambda", "second to last", "ok"],
            ["12", "mu", "final body row", "ok"]
        ]

        // Cell range tracking — populated as we append cells.
        var cellRanges: [(row: Int, col: Int, range: NSRange)] = []

        // Header row.
        for (col, text) in header.enumerated() {
            let (cellAS, range) = makeCell(
                text: text, table: table, row: 0, column: col,
                isHeader: true, currentLength: result.length)
            result.append(cellAS)
            cellRanges.append((row: 0, col: col, range: range))
        }
        // Body rows.
        for (rowIdx, row) in rows.enumerated() {
            for (col, text) in row.enumerated() {
                let (cellAS, range) = makeCell(
                    text: text, table: table, row: rowIdx + 1, column: col,
                    isHeader: false, currentLength: result.length)
                result.append(cellAS)
                cellRanges.append((row: rowIdx + 1, col: col, range: range))
            }
        }

        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13)
        ]))

        // Postamble — 30 lines of trailing content.
        for i in 0..<30 {
            let s = "postamble line \(i)\n"
            result.append(NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: 13)
            ]))
        }

        TK1TextView.cellRanges = cellRanges
        print("[D16] built table: \(rows.count + 1) rows × \(columnCount) cols, " +
              "\(cellRanges.count) cells, source length=\(result.length)")
        for entry in cellRanges where entry.row == 4 {
            print("  WRAP-ROW cell row=\(entry.row) col=\(entry.col) range=\(entry.range)")
        }
        return result
    }

    private static func makeCell(text: String,
                                 table: NSTextTable,
                                 row: Int,
                                 column: Int,
                                 isHeader: Bool,
                                 currentLength: Int)
        -> (NSAttributedString, NSRange)
    {
        let block = NSTextTableBlock(
            table: table,
            startingRow: row, rowSpan: 1,
            startingColumn: column, columnSpan: 1)
        block.setBorderColor(.separatorColor)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.setContentWidth(columnContentWidth, type: .absoluteValueType)

        let para = NSMutableParagraphStyle()
        para.textBlocks = [block]

        let font: NSFont = isHeader
            ? NSFont.boldSystemFont(ofSize: 13)
            : NSFont.systemFont(ofSize: 13)

        // Each cell is one paragraph — terminated by a newline so
        // TK1 advances to the next cell. This is the convention.
        let body = "\(text)\n"
        let cellAS = NSAttributedString(string: body, attributes: [
            .paragraphStyle: para,
            .font: font,
            .foregroundColor: NSColor.labelColor
        ])
        // Range of the cell's TEXT (excluding the trailing \n) in
        // the final document. Used by click-routing tests.
        let range = NSRange(
            location: currentLength,
            length: text.count)
        return (cellAS, range)
    }
}
