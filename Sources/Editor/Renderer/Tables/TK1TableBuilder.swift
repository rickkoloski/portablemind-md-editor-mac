// D17 — Builds the TK1 attributed-string segment for a markdown table.
// Replaces the source-range of a markdown Table node (header line +
// separator line + body row lines) with one cell paragraph per cell:
// each cell terminated by `\n`, paragraphStyle.textBlocks set to the
// cell's NSTextTableBlock pointing into a shared NSTextTable.
//
// Each cell paragraph carries `cellSourceRangeKey` (NSValue → NSRange)
// pointing at the cell's content range in the original source. Edit
// propagation uses this to splice user edits back into the markdown
// source between the original pipe characters.
//
// Reference shape: `spikes/d16_textkit1_tables/Sources/D16Spike/SpikeDoc.swift`.

import AppKit
import Foundation
import Markdown

enum TK1TableBuilder {

    /// Build the cell-paragraphs attributed string for `table`.
    ///
    /// - Parameters:
    ///   - table: parsed `Markdown.Table` node.
    ///   - tableSourceRange: NSRange in `nsSource` covering the table's
    ///     full source span (header + separator + body lines).
    ///   - nsSource: the markdown source as NSString, used to locate
    ///     cell content ranges between pipes.
    /// - Returns: an NSAttributedString whose paragraphs are cells.
    ///   Last paragraph is terminated by `\n` like the rest so the
    ///   table flows naturally with the surrounding content.
    static func build(table: Table,
                      tableSourceRange: NSRange,
                      nsSource: NSString) -> NSAttributedString {
        // 1. Derive cell content + per-cell source ranges from each
        //    row's source line.
        let headerCells: [Markdown.Table.Cell] = table.head.children
            .compactMap { $0 as? Markdown.Table.Cell }
        let bodyRows: [Markdown.Table.Row] = table.body.children
            .compactMap { $0 as? Markdown.Table.Row }
        let bodyCells: [[Markdown.Table.Cell]] = bodyRows.map { row in
            row.children.compactMap { $0 as? Markdown.Table.Cell }
        }
        let columnCount = max(
            headerCells.count,
            bodyCells.map(\.count).max() ?? 0)
        guard columnCount > 0 else {
            // Degenerate table — emit nothing (caller leaves source
            // text in place). Shouldn't happen with well-formed GFM.
            return NSAttributedString(string: "")
        }

        // 2. Locate each row's source line (clamped to the table's span)
        //    so we can parse cell source ranges between pipes.
        let rowLineRanges = locateRowLineRanges(
            for: table,
            tableSourceRange: tableSourceRange,
            nsSource: nsSource,
            includeSeparator: false)

        // 3. Parse cell source ranges (between pipes) per row line.
        // rowCellRanges[0]    = header row's per-cell source ranges
        // rowCellRanges[1..n] = body row N's per-cell source ranges
        let rowCellRanges: [[NSRange]] = rowLineRanges.map { lineRange in
            parseCellSourceRanges(
                in: nsSource, rowLineRange: lineRange)
        }

        // 4. Build the shared NSTextTable.
        let table1 = NSTextTable()
        table1.numberOfColumns = columnCount
        table1.collapsesBorders = false
        table1.hidesEmptyCells = false

        // 5. Pick a column content width. Mirror the legacy renderer's
        //    column-cap logic: max natural cell width capped at 320pt.
        let columnContentWidths = computeColumnWidths(
            headerCells: headerCells,
            bodyCells: bodyCells,
            columnCount: columnCount)

        // 6. Emit cell paragraphs row-by-row. Header → body rows.
        let result = NSMutableAttributedString()

        // Header row.
        for col in 0..<columnCount {
            let cellAS = makeCell(
                text: cellText(headerCells, atColumn: col, nsSource: nsSource),
                cellSourceRange: rowCellRanges[0].count > col
                    ? rowCellRanges[0][col]
                    : NSRange(location: tableSourceRange.location, length: 0),
                table: table1,
                row: 0, column: col,
                contentWidth: columnContentWidths[col],
                isHeader: true)
            result.append(cellAS)
        }
        // Body rows.
        for (bodyIdx, rowCells) in bodyCells.enumerated() {
            let rowIdx = bodyIdx + 1   // header is row 0
            for col in 0..<columnCount {
                let rangeRow = bodyIdx + 1   // header occupies index 0 in rowCellRanges
                let cellSrc = (rangeRow < rowCellRanges.count
                               && rowCellRanges[rangeRow].count > col)
                    ? rowCellRanges[rangeRow][col]
                    : NSRange(location: tableSourceRange.location, length: 0)
                let cellAS = makeCell(
                    text: cellText(rowCells, atColumn: col, nsSource: nsSource),
                    cellSourceRange: cellSrc,
                    table: table1,
                    row: rowIdx, column: col,
                    contentWidth: columnContentWidths[col],
                    isHeader: false)
                result.append(cellAS)
            }
        }

        return result
    }

    // MARK: - Cell paragraph

    private static func makeCell(text: String,
                                 cellSourceRange: NSRange,
                                 table: NSTextTable,
                                 row: Int, column: Int,
                                 contentWidth: CGFloat,
                                 isHeader: Bool) -> NSAttributedString {
        let block = NSTextTableBlock(
            table: table,
            startingRow: row, rowSpan: 1,
            startingColumn: column, columnSpan: 1)
        block.setBorderColor(.separatorColor)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.setContentWidth(contentWidth, type: .absoluteValueType)

        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [block]

        let font: NSFont = isHeader
            ? Typography.boldFont
            : Typography.baseFont

        // Cell text has trailing `\n` to terminate the paragraph; the
        // newline isn't part of the cell content range and shouldn't
        // count toward the cell's source span. The cellSourceRange
        // attribute attaches to the displayed text only (not the \n).
        let body = "\(text)\n"
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let cellAS = NSMutableAttributedString(string: body, attributes: attrs)
        if text.count > 0 {
            let textNSLength = (text as NSString).length
            cellAS.addAttribute(
                TableAttributeKeys.cellSourceRangeKey,
                value: NSValue(range: cellSourceRange),
                range: NSRange(location: 0, length: textNSLength))
        }
        return cellAS
    }

    // MARK: - Source-range parsing

    /// Walk the source line and extract NSRanges for each cell's
    /// content between pipe characters. The ranges exclude the pipes
    /// themselves AND the surrounding whitespace, so an edit inside
    /// the cell stays bounded. Backslash-escaped pipes (`\|`) inside
    /// a cell are NOT treated as separators.
    static func parseCellSourceRanges(in nsSource: NSString,
                                      rowLineRange: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        let lineEnd = NSMaxRange(rowLineRange)
        let pipe = unichar(UnicodeScalar("|").value)
        let backslash = unichar(UnicodeScalar("\\").value)

        // Find pipe positions (not preceded by backslash). A cell's
        // content lies between consecutive unescaped pipes.
        var pipePositions: [Int] = []
        var i = rowLineRange.location
        while i < lineEnd {
            let ch = nsSource.character(at: i)
            if ch == pipe {
                if i > rowLineRange.location,
                   nsSource.character(at: i - 1) == backslash {
                    // escaped pipe — not a separator
                } else {
                    pipePositions.append(i)
                }
            }
            i += 1
        }
        // Need at least 2 pipes to form 1 cell.
        guard pipePositions.count >= 2 else { return [] }
        for k in 0..<(pipePositions.count - 1) {
            let pipeStart = pipePositions[k]
            let pipeEnd = pipePositions[k + 1]
            // Content between the pipes, then trim leading/trailing
            // whitespace.
            var contentStart = pipeStart + 1
            var contentEnd = pipeEnd
            while contentStart < contentEnd,
                  isWhitespace(nsSource.character(at: contentStart)) {
                contentStart += 1
            }
            while contentEnd > contentStart,
                  isWhitespace(nsSource.character(at: contentEnd - 1)) {
                contentEnd -= 1
            }
            ranges.append(NSRange(
                location: contentStart,
                length: contentEnd - contentStart))
        }
        return ranges
    }

    private static func isWhitespace(_ ch: unichar) -> Bool {
        return ch == 0x20 || ch == 0x09  // space, tab
    }

    /// Find each row line's source range within the table. By default
    /// the separator row (`|---|---|`) is skipped because it has no
    /// editable cell content; the caller decides whether to include
    /// it (e.g., for full-table replacement coordinates).
    private static func locateRowLineRanges(for table: Table,
                                            tableSourceRange: NSRange,
                                            nsSource: NSString,
                                            includeSeparator: Bool) -> [NSRange] {
        var lines: [NSRange] = []
        let tableEnd = NSMaxRange(tableSourceRange)
        let newline = unichar(UnicodeScalar("\n").value)
        var lineStart = tableSourceRange.location
        while lineStart < tableEnd {
            var i = lineStart
            while i < tableEnd, nsSource.character(at: i) != newline {
                i += 1
            }
            let lineLen = i - lineStart
            if lineLen > 0 {
                lines.append(NSRange(location: lineStart, length: lineLen))
            }
            lineStart = i + 1   // skip newline
        }
        // First line = header, second line = separator, rest = body.
        guard lines.count >= 2 else { return lines }
        var out: [NSRange] = [lines[0]]
        if includeSeparator {
            out.append(lines[1])
        }
        if lines.count >= 3 {
            out.append(contentsOf: lines.dropFirst(2))
        }
        return out
    }

    // MARK: - Cell text extraction

    private static func cellText(_ cells: [Markdown.Table.Cell],
                                 atColumn col: Int,
                                 nsSource: NSString) -> String {
        guard col < cells.count else { return "" }
        let plain = cells[col].plainText
            .components(separatedBy: "\n").first ?? ""
        // Un-escape backslash-pipe inside cell content for display.
        return plain
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Column width

    private static func computeColumnWidths(
        headerCells: [Markdown.Table.Cell],
        bodyCells: [[Markdown.Table.Cell]],
        columnCount: Int
    ) -> [CGFloat] {
        let columnCap: CGFloat = 320
        var widths: [CGFloat] = Array(repeating: 60, count: columnCount)
        for col in 0..<columnCount {
            var maxWidth: CGFloat = 60
            if col < headerCells.count {
                let s = NSAttributedString(
                    string: headerCells[col].plainText,
                    attributes: [.font: Typography.boldFont])
                maxWidth = max(maxWidth, min(s.size().width, columnCap))
            }
            for row in bodyCells where col < row.count {
                let s = NSAttributedString(
                    string: row[col].plainText,
                    attributes: [.font: Typography.baseFont])
                maxWidth = max(maxWidth, min(s.size().width, columnCap))
            }
            widths[col] = maxWidth
        }
        return widths
    }
}
