// D17 — Walks a TK1-shaped attributed string (cell paragraphs + non-
// cell paragraphs) and emits canonical markdown source. Inverse of
// `MarkdownRenderer.buildAttributedString`'s output, so:
//
//   markdown source -> render -> attributed string -> serialize -> markdown source
//
// is an identity round trip (modulo whitespace normalization).
//
// On every user edit, the editor coordinator reads
// `textView.textStorage` through this serializer and writes the
// result to `document.source`. Save then writes that already-
// canonical markdown to disk, no extra step.
//
// NOTE: this is NOT a general markdown serializer. It only knows how
// to round-trip the shapes our renderer produces:
//   - non-cell paragraphs: text passes through verbatim, terminated
//     by newline.
//   - cell paragraphs: grouped by their NSTextTable instance, output
//     as a GFM table (`| c1 | c2 |\n|---|---|\n| ... |\n`).

import AppKit
import Foundation

enum TK1Serializer {

    static func serialize(_ storage: NSAttributedString) -> String {
        let nsString = storage.string as NSString
        let n = nsString.length
        var output = ""

        // Pending-table accumulator. We collect all cell paragraphs of
        // a contiguous table and flush as one block when we hit a non-
        // cell paragraph or end-of-doc.
        var pendingTable: NSTextTable?
        var pendingCells: [Int: [Int: String]] = [:]   // row → col → text

        func flushTable() {
            guard let table = pendingTable else { return }
            let columnCount = table.numberOfColumns
            let rows = pendingCells.keys.sorted()
            for (idx, row) in rows.enumerated() {
                guard let rowCells = pendingCells[row] else { continue }
                var rowTexts: [String] = []
                for col in 0..<columnCount {
                    rowTexts.append(rowCells[col] ?? "")
                }
                output += "| " + rowTexts.joined(separator: " | ") + " |\n"
                // Emit separator after first row (the header) — GFM
                // convention.
                if idx == 0 {
                    let sep = Array(repeating: "---", count: columnCount)
                        .joined(separator: " | ")
                    output += "| " + sep + " |\n"
                }
            }
            pendingTable = nil
            pendingCells = [:]
        }

        var i = 0
        while i < n {
            // Locate this paragraph's range. Paragraph terminator is
            // a newline character (LF). Tail span without trailing
            // newline still counts as a paragraph.
            var end = i
            while end < n, nsString.character(at: end) != 0x0A { end += 1 }
            let paraRange = NSRange(location: i, length: end - i)
            let paraText = paraRange.length > 0
                ? nsString.substring(with: paraRange)
                : ""
            // Inspect first character's paragraph style for cell info.
            let cellInfo: (table: NSTextTable, row: Int, col: Int)? = {
                guard paraRange.length > 0 else { return nil }
                let attrs = storage.attributes(at: paraRange.location,
                                               effectiveRange: nil)
                guard let pStyle = attrs[.paragraphStyle] as? NSParagraphStyle
                else { return nil }
                for block in pStyle.textBlocks {
                    if let tableBlock = block as? NSTextTableBlock {
                        return (tableBlock.table,
                                tableBlock.startingRow,
                                tableBlock.startingColumn)
                    }
                }
                return nil
            }()

            if let (table, row, col) = cellInfo {
                if pendingTable !== table {
                    flushTable()
                    pendingTable = table
                }
                let escaped = paraText
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "|", with: "\\|")
                if pendingCells[row] == nil {
                    pendingCells[row] = [:]
                }
                pendingCells[row]?[col] = escaped
            } else {
                flushTable()
                output += paraText + "\n"
            }

            // Advance past the paragraph, including the trailing \n
            // if present. End-of-doc has no trailing \n.
            i = end + (end < n ? 1 : 0)
        }
        flushTable()

        // Strip a single trailing newline so we round-trip files that
        // didn't end with one. Two-newline tail is preserved (some
        // editors write trailing-newline; common to keep).
        if output.hasSuffix("\n") && !output.hasSuffix("\n\n") {
            output.removeLast()
        }
        return output
    }
}
