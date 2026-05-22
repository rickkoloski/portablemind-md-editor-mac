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

    /// U+200B zero-width space. Seeded into empty cell paragraphs so
    /// they have non-zero content length. Without this, NSTextTable
    /// refuses to insert typed characters INTO a truly-empty cell —
    /// the character escapes the cell and lands as a sibling non-
    /// table paragraph, breaking the table on the next serializer pass.
    ///
    /// The serializer strips ZWS from cell paragraphs at save time
    /// (see `TK1Serializer.serialize`), so the markdown source on
    /// disk never sees this character.
    ///
    /// — Considered alternative (Option B, kept on file for future
    ///   debugging) — overriding `insertText(_:)` in `LiveRenderTextView`
    ///   to detect caret-in-empty-cell and explicitly set
    ///   `typingAttributes` from the cell paragraph's style. Rejected
    ///   for the first fix because it couples the input pipeline (paste,
    ///   IME composition, drag-drop, selection-replace all need
    ///   separate handling) and is hypothesis-driven about *why*
    ///   NSTextTable breaks out of empty cells. The ZWS workaround is
    ///   the canonical pattern used by production NSTextTable editors
    ///   and is contained to two files. If a future failure mode
    ///   surfaces that ZWS can't address (e.g., IME composition in an
    ///   empty cell behaves differently), revisit Option B then.
    ///   Full diagnosis + decision lives at
    ///   `docs/current_work/issues/table_typing_bug_diagnostic.md`.
    static let emptyCellPlaceholder = "\u{200B}"

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
    /// Per-cell visible framing overhead added outside the cell's content
    /// box: 2 × 1pt border + 2 × 6pt padding (set on NSTextTableBlock
    /// in `makeCell`).
    static let cellBorderPaddingOverhead: CGFloat = 14   // 2*1 + 2*6

    /// NSTextContainer.lineFragmentPadding (default 5pt on macOS) is
    /// applied INSIDE each cell's content area at render time, eating
    /// 2 × 5 = 10pt off the usable text width. Our natural-width
    /// measurement (NSAttributedString.size) doesn't account for this.
    /// Both the cell's setContentWidth call AND the distribute target
    /// subtraction add 2 × this value so the algorithm-applied width
    /// equals the actual rendered text area (D24.2 phase 3 fix —
    /// previously latent because D24's lock-in algorithm always gave
    /// short-token columns ≥3pt of headroom; Q8 lock-at-max made the
    /// edge case visible as flicker-during-resize / wrap-on-fixed).
    static let cellLineFragmentPadding: CGFloat = 5

    /// Total per-cell width overhead (visual framing + lineFragment
    /// padding compensation). Subtract `cellFramingOverhead × N` from
    /// `viewportWidth` to get the distribution target so the rendered
    /// table fits end-to-end.
    static let cellFramingOverhead: CGFloat =
        cellBorderPaddingOverhead + 2 * cellLineFragmentPadding   // 24

    static func build(table: Table,
                      tableSourceRange: NSRange,
                      nsSource: NSString,
                      viewportWidth: CGFloat) -> NSAttributedString {
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

        // 5. D24 phase 4 — responsive column widths. Pre-cap each
        //    column's natural width at the viewport (Q8); subtract per-
        //    cell framing from the distribute target so the rendered
        //    table fits within `viewportWidth` end-to-end; let the
        //    distribution algorithm produce per-column applied widths.
        let columnContentWidths = computeColumnWidths(
            headerCells: headerCells,
            bodyCells: bodyCells,
            columnCount: columnCount,
            viewportWidth: viewportWidth)

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
        // D24.2 phase 3 — pad the block's content width by the host
        // text container's lineFragmentPadding (×2) so the usable text
        // area inside the cell equals the algorithm-applied column
        // width. See cellLineFragmentPadding doc comment.
        block.setContentWidth(
            contentWidth + 2 * Self.cellLineFragmentPadding,
            type: .absoluteValueType)

        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [block]
        // D24 Q9 — multi-line word wrap inside cells. URLs and paths
        // wrap at internal break opportunities (-, /, .); pathological
        // no-punctuation tokens fall through to TextKit's char-wrap
        // last resort, lossless.
        paragraph.lineBreakMode = .byWordWrapping

        let font: NSFont = isHeader
            ? Typography.boldFont
            : Typography.baseFont

        // Cell text has trailing `\n` to terminate the paragraph; the
        // newline isn't part of the cell content range and shouldn't
        // count toward the cell's source span. The cellSourceRange
        // attribute attaches to the displayed text only (not the \n).
        //
        // Empty cells get a ZWS placeholder (see `emptyCellPlaceholder`
        // doc comment for why). The ZWS is part of the paragraph's
        // content for typing purposes but doesn't carry a source range
        // — the serializer strips it before emitting markdown.
        let displayText = text.isEmpty ? Self.emptyCellPlaceholder : text
        let body = "\(displayText)\n"
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let cellAS = NSMutableAttributedString(string: body, attributes: attrs)
        if !text.isEmpty {
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

    /// D24.2 phase 2: per-column applied widths via the Q8 + slack-
    /// proportional algorithm. Each column's `maxContent` is pre-capped
    /// at `viewportWidth` per D24's Q8 (viewport cap, distinct from
    /// D24.2's narrow-threshold Q8). Distribution target subtracts the
    /// per-cell framing overhead × column count so the rendered table
    /// fits inside `viewportWidth` end-to-end.
    private static func computeColumnWidths(
        headerCells: [Markdown.Table.Cell],
        bodyCells: [[Markdown.Table.Cell]],
        columnCount: Int,
        viewportWidth: CGFloat
    ) -> [CGFloat] {
        guard columnCount > 0 else { return [] }
        let framingTotal = cellFramingOverhead * CGFloat(columnCount)
        let target = max(0, viewportWidth - framingTotal)
        var measurements: [ColumnContentMeasurement] = []
        measurements.reserveCapacity(columnCount)
        for col in 0..<columnCount {
            let (m, _) = columnMeasurement(
                headerCells: headerCells,
                bodyCells: bodyCells,
                column: col)
            // D24 Q8 (viewport cap): pre-cap maxContent at distribution
            // target so a single super-long URL can't push the table
            // past viewport. minContent is content-derived; never capped.
            measurements.append(ColumnContentMeasurement(
                minContent: min(m.minContent, target),
                maxContent: min(m.maxContent, target)))
        }
        return TableColumnDistribution.distribute(
            measurements: measurements,
            viewportWidth: target)
    }

    // MARK: - D24.2 phase 1 — (min, max) per-column measurement (cache-aware)

    /// Per-column measurement record for the harness. Carries both the
    /// `minContent` (longest unbreakable atom per Q1) and `maxContent`
    /// (longest single-line shaped width) for a column, plus the cache-
    /// hit flag at lookup time.
    struct ColumnMeasurement {
        let column: Int
        let widths: ColumnContentMeasurement
        let cacheHit: Bool

        /// Convenience accessors for harness JSON serialization.
        var minWidth: CGFloat { widths.minContent }
        var maxWidth: CGFloat { widths.maxContent }
        var slack: CGFloat { widths.slack }
    }

    /// Public entry for the test harness. Walks the parsed table's cells
    /// exactly the way `build(...)` does and returns per-column `(min, max)`
    /// measurements plus cache-hit flags.
    static func measureNaturalWidths(table: Table,
                                     nsSource: NSString) -> [ColumnMeasurement] {
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
        var out: [ColumnMeasurement] = []
        out.reserveCapacity(columnCount)
        for col in 0..<columnCount {
            let (m, hit) = columnMeasurement(
                headerCells: headerCells,
                bodyCells: bodyCells,
                column: col)
            out.append(ColumnMeasurement(
                column: col, widths: m, cacheHit: hit))
        }
        return out
    }

    /// Per-column `(min, max)` content widths. Cached by a content hash
    /// that captures every contributing cell's plain text in render order
    /// (header first, body rows in row order). Header cell is shaped with
    /// `Typography.boldFont`; body cells with `Typography.baseFont` — same
    /// fonts the renderer uses, so measure ≈ render width.
    static func columnMeasurement(headerCells: [Markdown.Table.Cell],
                                  bodyCells: [[Markdown.Table.Cell]],
                                  column col: Int)
        -> (ColumnContentMeasurement, Bool) {
        var hasher = Hasher()
        if col < headerCells.count {
            hasher.combine("h")
            hasher.combine(headerCells[col].plainText)
        }
        for (rowIdx, row) in bodyCells.enumerated() where col < row.count {
            hasher.combine(rowIdx)
            hasher.combine(row[col].plainText)
        }
        let key = hasher.finalize()

        return TableNaturalWidthCache.shared.measurementOrCompute(
            forContentHash: key
        ) {
            var maxW: CGFloat = 0
            var minW: CGFloat = 0
            if col < headerCells.count {
                let text = cellNaturalText(headerCells[col].plainText)
                let lineW = NSAttributedString(
                    string: text,
                    attributes: [.font: Typography.boldFont]
                ).size().width
                maxW = max(maxW, lineW)
                minW = max(minW, cellMinContentWidth(text, font: Typography.boldFont))
            }
            for row in bodyCells where col < row.count {
                let text = cellNaturalText(row[col].plainText)
                let lineW = NSAttributedString(
                    string: text,
                    attributes: [.font: Typography.baseFont]
                ).size().width
                maxW = max(maxW, lineW)
                minW = max(minW, cellMinContentWidth(text, font: Typography.baseFont))
            }
            return ColumnContentMeasurement(minContent: minW, maxContent: maxW)
        }
    }

    /// Strip the cell text down to what the renderer actually displays:
    /// first source line only, with markdown-escapes for `|` and `\` undone
    /// so width measurement matches what the user sees.
    private static func cellNaturalText(_ raw: String) -> String {
        let firstLine = raw.components(separatedBy: "\n").first ?? raw
        return firstLine
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - D24.2 Q1 — min-content (longest unbreakable atom)

    /// Per Q1: split `text` on whitespace + ASCII soft-break punctuation
    /// (`-`, `/`, `.`), measure each resulting atom's CT-shaped width with
    /// `font`, return the maximum. Conservative heuristic that matches
    /// TextKit's `byWordWrapping` behavior on dogfooded markdown content.
    /// The phase-1 token-split spike validates the heuristic against
    /// TextKit's actual minimum-line-fragment behavior.
    static func cellMinContentWidth(_ text: String, font: NSFont) -> CGFloat {
        if text.isEmpty { return 0 }
        var maxAtom: CGFloat = 0
        var atomStart = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if Self.isSoftBreakChar(c) {
                if atomStart < i {
                    let atom = String(text[atomStart..<i])
                    let w = NSAttributedString(
                        string: atom,
                        attributes: [.font: font]
                    ).size().width
                    if w > maxAtom { maxAtom = w }
                }
                atomStart = text.index(after: i)
            }
            i = text.index(after: i)
        }
        if atomStart < text.endIndex {
            let atom = String(text[atomStart..<text.endIndex])
            let w = NSAttributedString(
                string: atom,
                attributes: [.font: font]
            ).size().width
            if w > maxAtom { maxAtom = w }
        }
        return maxAtom
    }

    /// Q1 break-character set: ASCII whitespace + `-`, `/`, `.`. Conservative
    /// — TextKit treats more punctuation as soft-break (`,`, `;`, `:`, etc.)
    /// but those rarely appear inside atomic content in dogfooded markdown.
    /// The spike validates whether broadening this set is warranted.
    @inline(__always)
    private static func isSoftBreakChar(_ c: Character) -> Bool {
        switch c {
        case " ", "\t", "\n", "-", "/", ".":
            return true
        default:
            return false
        }
    }
}
