// Spike: minimal port of production TableLayout / TableRowAttachment.
// Goal is to render a three-table seed buffer with cell wrapping so
// that the cell-edit overlay can be tested. Not a full rewrite of
// production — only the pieces needed for click-to-caret + draw.

import AppKit
import Foundation

enum SpikeAttributeKeys {
    static let rowAttachmentKey = NSAttributedString.Key("d13.spike.tableRowAttachment")
}

// Per-column alignment derived from the separator row's `:---:` cues.
enum CellAlignment {
    case left, right, center, none
}

// Pre-computed layout for one table. Mirrors production TableLayout's
// shape (columnLeadingX, columnTrailingX, contentWidths, rowHeight,
// cellRanges, cellContentPerRow). Excludes alignment for spike brevity
// (alignment is left-only in the spike).
final class TableLayout {
    let columnCount: Int
    let contentWidths: [CGFloat]
    let alignments: [CellAlignment]
    let cellInset = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    let separatorColor: NSColor = NSColor.separatorColor
    let bodyFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let headerFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)

    var totalWidth: CGFloat {
        contentWidths.reduce(0) { $0 + $1 + cellInset.left + cellInset.right }
    }

    let columnLeadingX: [CGFloat]
    let columnTrailingX: [CGFloat]
    let cellContentPerRow: [[NSAttributedString]]
    let rowHeight: [CGFloat]
    let tableRange: NSRange
    let cellRanges: [[NSRange]]

    init(columnCount: Int,
         contentWidths: [CGFloat],
         alignments: [CellAlignment],
         cellContentPerRow: [[NSAttributedString]],
         tableRange: NSRange,
         cellRanges: [[NSRange]]) {
        self.columnCount = columnCount
        self.contentWidths = contentWidths
        self.alignments = alignments
        self.cellContentPerRow = cellContentPerRow
        self.tableRange = tableRange
        self.cellRanges = cellRanges

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

extension TableLayout {
    /// Cell-content-local x offset for a given local character offset
    /// within `cellContentPerRow[rowIdx][colIdx]`. Caller adds
    /// `columnLeadingX[colIdx]` to get fragment-local x.
    func charXOffset(rowIdx: Int, colIdx: Int, localOffset: Int) -> CGFloat {
        guard rowIdx < cellContentPerRow.count,
              colIdx < cellContentPerRow[rowIdx].count
        else { return 0 }
        let cell = cellContentPerRow[rowIdx][colIdx]
        guard cell.length > 0 else { return 0 }
        let line = CTLineCreateWithAttributedString(cell)
        let clamped = max(0, min(localOffset, cell.length))
        return CTLineGetOffsetForStringIndex(line, clamped, nil)
    }

    /// Convert a click point in cell-content-local coords (relative to the
    /// top-left of the cell's content area, AFTER cellInset) to a local
    /// character index in `cellContentPerRow[rowIdx][colIdx]`.
    ///
    /// Algorithm per D13 spec §3.5:
    ///  1. Build CTFramesetter on the cell's NSAttributedString.
    ///  2. Suggest a frame at columnWidth × ∞ — produces wrap-correct lines.
    ///  3. Stack lines from the top, accumulating per-line height
    ///     (ascent + descent + leading).
    ///  4. Find the line containing relY. If found, return
    ///     CTLineGetStringIndexForPosition(line, CGPoint(relX, 0)).
    ///  5. Click below all lines → cell.length (caret at end).
    ///  6. Click above first line / negative relY → 0.
    ///
    /// Returned index is clamped to `[0, cell.length]`.
    func cellLocalCaretIndex(rowIdx: Int,
                             colIdx: Int,
                             relX: CGFloat,
                             relY: CGFloat) -> Int {
        guard rowIdx < cellContentPerRow.count,
              colIdx < cellContentPerRow[rowIdx].count,
              colIdx < contentWidths.count
        else { return 0 }
        let cell = cellContentPerRow[rowIdx][colIdx]
        let length = cell.length
        if length == 0 { return 0 }
        if relY < 0 { return 0 }

        let columnWidth = contentWidths[colIdx]
        let framesetter = CTFramesetterCreateWithAttributedString(cell)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: columnWidth, height: 100_000),
            transform: nil)
        let ctFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil)
        guard let lines = CTFrameGetLines(ctFrame) as? [CTLine] else {
            return min(length, 0)
        }

        var accumulatedY: CGFloat = 0
        for line in lines {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let lineHeight = ascent + descent + leading
            if relY >= accumulatedY && relY < accumulatedY + lineHeight {
                let idx = CTLineGetStringIndexForPosition(
                    line,
                    CGPoint(x: relX, y: 0))
                if idx == kCFNotFound { return 0 }
                return max(0, min(idx, length))
            }
            accumulatedY += lineHeight
        }
        // Click below all lines.
        return length
    }

    /// Parse a row's source line into per-cell content ranges.
    /// Algorithm: tokenize on pipes; trim each cell's whitespace;
    /// record empty cells as zero-length ranges. Drops trailing
    /// phantom cell after the closing pipe.
    static func parseCellRanges(in ns: NSString,
                                rowStart: Int,
                                rowLength: Int) -> [NSRange] {
        var ranges: [NSRange] = []
        let PIPE: unichar = 0x7c
        let SPACE: unichar = 0x20
        let NEWLINE: unichar = 0x0a
        let rowEnd = rowStart + rowLength

        var i = rowStart
        if i < rowEnd, ns.character(at: i) == PIPE {
            i += 1
        } else {
            return []
        }

        while i < rowEnd {
            if ns.character(at: i) == NEWLINE { break }

            let spanStart = i
            while i < rowEnd,
                  ns.character(at: i) != PIPE,
                  ns.character(at: i) != NEWLINE {
                i += 1
            }
            let spanEnd = i

            var contentStart = spanStart
            while contentStart < spanEnd,
                  ns.character(at: contentStart) == SPACE {
                contentStart += 1
            }
            var contentEnd = spanEnd
            while contentEnd > contentStart,
                  ns.character(at: contentEnd - 1) == SPACE {
                contentEnd -= 1
            }
            ranges.append(NSRange(location: contentStart,
                                  length: contentEnd - contentStart))

            if i < rowEnd, ns.character(at: i) == PIPE {
                i += 1
            } else {
                break
            }
        }

        if let last = ranges.last, last.length == 0,
           last.location >= rowEnd - 1 {
            ranges.removeLast()
        }
        return ranges
    }
}

final class TableRowAttachment: NSObject {
    enum Kind { case header, separator, body }

    let layout: TableLayout
    let kind: Kind
    let cellContentIndex: Int?
    let isFirstRow: Bool
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
