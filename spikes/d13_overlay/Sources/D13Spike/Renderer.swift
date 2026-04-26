// Spike: minimal markdown renderer that scans for table blocks
// (consecutive lines starting with `|`), builds a TableLayout per
// block, and applies TableRowAttachments to the matching source
// ranges. Headings + non-table content render as plain text via
// NSTextView's default behavior — we just leave their attributes
// alone.

import AppKit
import Foundation

enum SpikeRenderer {
    /// Maximum width a cell will grow to before wrapping kicks in.
    /// Production uses ~320; we mirror that.
    static let maxCellWidth: CGFloat = 320

    /// Replace all attributes in `storage` so that:
    ///   - default text (headings, paragraphs) gets a body font.
    ///   - table rows get a TableRowAttachment + a paragraph style
    ///     that prevents NSTextView from claiming line height for them
    ///     (the fragment owns the row's geometry).
    static func render(into storage: NSTextStorage) {
        storage.beginEditing()
        defer { storage.endEditing() }

        let full = NSRange(location: 0, length: storage.length)
        let baseFont = NSFont.systemFont(ofSize: 14)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]
        storage.setAttributes(baseAttrs, range: full)

        let ns = storage.string as NSString
        let length = ns.length

        // Walk lines. Group consecutive lines starting with `|` (after
        // skipping leading whitespace) into a table block. A valid
        // table block needs at least 3 lines (header + separator + 1+
        // body), where line 2 must look like `|---|---|`.
        var lineStart = 0
        var blocks: [[Int]] = []   // each block: [line-start offsets]
        var currentBlock: [Int] = []

        while lineStart < length {
            var lineEnd = lineStart
            while lineEnd < length, ns.character(at: lineEnd) != 0x0a {
                lineEnd += 1
            }
            // lineEnd now at \n or length.
            // Skip leading whitespace for the test only.
            var probe = lineStart
            while probe < lineEnd, ns.character(at: probe) == 0x20 {
                probe += 1
            }
            if probe < lineEnd, ns.character(at: probe) == 0x7c {
                currentBlock.append(lineStart)
            } else {
                if currentBlock.count >= 3 { blocks.append(currentBlock) }
                currentBlock.removeAll()
            }
            // Advance to next line (past the \n).
            lineStart = (lineEnd < length) ? lineEnd + 1 : length
        }
        if currentBlock.count >= 3 { blocks.append(currentBlock) }

        // Process each block: parse cells; verify line 2 is separator;
        // build a TableLayout; apply attachments.
        for block in blocks {
            guard block.count >= 3 else { continue }

            // Parse each line's cell ranges.
            var perLineCells: [[NSRange]] = []
            for ls in block {
                let lineLen = lineLength(in: ns, startingAt: ls)
                let cells = TableLayout.parseCellRanges(in: ns,
                                                        rowStart: ls,
                                                        rowLength: lineLen)
                perLineCells.append(cells)
            }

            // Verify line 2 is a separator (`---` content per cell).
            guard perLineCells.count >= 3 else { continue }
            let sepCells = perLineCells[1]
            let sepLooksValid = !sepCells.isEmpty && sepCells.allSatisfy { range in
                let s = ns.substring(with: range)
                let t = s.trimmingCharacters(in: .whitespaces)
                return t.allSatisfy { $0 == "-" || $0 == ":" }
            }
            guard sepLooksValid else { continue }

            // Build cell content per row (skip separator).
            // Header is row 0, body is rows 2+. We index the layout's
            // `cellContentPerRow` by header→0, body→1..N.
            var contentPerRow: [[NSAttributedString]] = []
            var cellRanges: [[NSRange]] = []
            // Header
            let headerAS = perLineCells[0].map { range -> NSAttributedString in
                NSAttributedString(string: ns.substring(with: range),
                                   attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
                                                .foregroundColor: NSColor.labelColor])
            }
            contentPerRow.append(headerAS)
            cellRanges.append(perLineCells[0])
            // Body
            for i in 2..<perLineCells.count {
                let bodyAS = perLineCells[i].map { range -> NSAttributedString in
                    NSAttributedString(string: ns.substring(with: range),
                                       attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                                                    .foregroundColor: NSColor.labelColor])
                }
                contentPerRow.append(bodyAS)
                cellRanges.append(perLineCells[i])
            }

            // Compute per-column max content width (capped at maxCellWidth).
            let columnCount = contentPerRow.first?.count ?? 0
            guard columnCount > 0 else { continue }
            var widths: [CGFloat] = Array(repeating: 0, count: columnCount)
            for row in contentPerRow {
                for (col, cell) in row.enumerated() where col < columnCount {
                    let unwrappedW = cell.size().width
                    widths[col] = max(widths[col], min(unwrappedW, maxCellWidth))
                }
            }
            // Ensure a min width so empty cells still have geometry.
            widths = widths.map { max($0, 24) }

            // Compute table source range (block.first ... last line + len).
            let firstLine = block.first!
            let lastLine = block.last!
            let lastLen = lineLength(in: ns, startingAt: lastLine)
            let tableRange = NSRange(location: firstLine,
                                     length: (lastLine + lastLen) - firstLine)

            let layout = TableLayout(
                columnCount: columnCount,
                contentWidths: widths,
                alignments: Array(repeating: .left, count: columnCount),
                cellContentPerRow: contentPerRow,
                tableRange: tableRange,
                cellRanges: cellRanges)

            // Apply TableRowAttachment to each line's source range.
            // Header is line 0; separator is line 1; body is lines 2+.
            let totalLines = block.count
            for (lineIdx, ls) in block.enumerated() {
                let lineLen = lineLength(in: ns, startingAt: ls)
                let kind: TableRowAttachment.Kind
                let cci: Int?
                if lineIdx == 0 {
                    kind = .header
                    cci = 0
                } else if lineIdx == 1 {
                    kind = .separator
                    cci = nil
                } else {
                    kind = .body
                    cci = lineIdx - 1   // header at 0, body starts at 1 in cellContentPerRow
                }
                let attachment = TableRowAttachment(
                    layout: layout,
                    kind: kind,
                    cellContentIndex: cci,
                    isFirstRow: lineIdx == 0,
                    isLastRow: lineIdx == totalLines - 1)

                // Apply: include the trailing newline (if any) so the
                // fragment claims it.
                let attachLen = (ls + lineLen < length) ? lineLen + 1 : lineLen
                let attachRange = NSRange(location: ls, length: attachLen)
                storage.addAttribute(SpikeAttributeKeys.rowAttachmentKey,
                                     value: attachment,
                                     range: attachRange)
                // Strip default font sizing from the row range so the
                // fragment owns rendering.
                storage.addAttribute(.font,
                                     value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                                     range: attachRange)
            }
        }
    }

    private static func lineLength(in ns: NSString, startingAt start: Int) -> Int {
        var i = start
        let length = ns.length
        while i < length, ns.character(at: i) != 0x0a {
            i += 1
        }
        return i - start
    }
}
