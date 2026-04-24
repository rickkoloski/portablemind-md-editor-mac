import AppKit
import Foundation
import Markdown

/// Parses markdown with swift-markdown and produces a `RenderResult` —
/// a list of NSTextStorage attribute assignments plus a list of syntax
/// spans so the cursor-on-line tracker can find delimiter ranges later
/// without re-parsing.
///
/// D2 scope (same as D1 spike): Heading, Strong, Emphasis, InlineCode,
/// Link, CodeBlock. Enough to exercise the live-render patterns named
/// in the vision.
///
/// D2 fixes over the spike:
/// - Finding #3: InlineCode delimiter tagging now looks up the actual
///   backtick characters in the source rather than assuming the
///   swift-markdown `range` is backtick-inclusive (it isn't always).
/// - Finding #4: CodeBlock opening and closing fence lines are tagged
///   as delimiters; multiline range conversion uses the shared
///   SourceLocationConverter so the range spans real content lines.
final class MarkdownRenderer {
    func render(_ source: String) -> RenderResult {
        let nsSource = source as NSString
        let converter = SourceLocationConverter(source: source)
        let visitor = RenderVisitor(nsSource: nsSource, converter: converter)

        // Base body attributes first; specific elements overwrite.
        let fullRange = NSRange(location: 0, length: nsSource.length)
        visitor.assignments.append(AttributeAssignment(
            range: fullRange,
            attributes: [
                .font: Typography.baseFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.textBackgroundColor
            ]
        ))

        let document = Document(parsing: source)
        visitor.walk(document)

        return RenderResult(assignments: visitor.assignments, spans: visitor.spans)
    }
}

/// Hand-rolled traversal over swift-markdown's AST. MarkupWalker's
/// protocol extension uses mutating-flavored semantics that fight
/// class-based accumulation; explicit type-check dispatch is simpler
/// and equally clear.
private final class RenderVisitor {
    let nsSource: NSString
    let converter: SourceLocationConverter
    var assignments: [AttributeAssignment] = []
    var spans: [SyntaxSpan] = []
    /// Nesting state — inline formatting (Strong / Emphasis) inside a
    /// heading should preserve the heading's font size, not shrink
    /// back to body size. Set on entry to a Heading, restored on exit.
    private var currentHeadingLevel: Int = 0

    init(nsSource: NSString, converter: SourceLocationConverter) {
        self.nsSource = nsSource
        self.converter = converter
    }

    func walk(_ markup: any Markup) {
        switch markup {
        case let heading as Heading: visitHeading(heading)
        case let strong as Strong: visitStrong(strong)
        case let emphasis as Emphasis: visitEmphasis(emphasis)
        case let inlineCode as InlineCode: visitInlineCode(inlineCode)
        case let link as Link: visitLink(link)
        case let codeBlock as CodeBlock: visitCodeBlock(codeBlock)
        case let table as Table:
            visitTable(table)
        default:
            for child in markup.children { walk(child) }
        }
    }

    // MARK: - Node handlers

    private func visitHeading(_ heading: Heading) {
        if let range = sourceNSRange(heading) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [.font: Typography.headingFont(level: heading.level)]
            ))
            if let markerRange = leadingHashRange(in: range, expectedHashes: heading.level) {
                tagDelimiter(markerRange)
            }
        }
        let prior = currentHeadingLevel
        currentHeadingLevel = heading.level
        for child in heading.children { walk(child) }
        currentHeadingLevel = prior
    }

    private func visitStrong(_ strong: Strong) {
        if let range = sourceNSRange(strong) {
            // D4 finding: when Strong is inside a Heading, applying the
            // body-sized bold font overwrites the heading font and
            // shrinks the text. Keep the heading font (already bold by
            // construction) in that case.
            let font: NSFont = currentHeadingLevel > 0
                ? Typography.headingFont(level: currentHeadingLevel)
                : Typography.boldFont
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [.font: font]
            ))
            tagWrappingDelimiters(range: range, markerLength: 2)
        }
        for child in strong.children { walk(child) }
    }

    private func visitEmphasis(_ emphasis: Emphasis) {
        if let range = sourceNSRange(emphasis) {
            // Same reasoning as Strong: inside a heading, keep the
            // heading's font so the size stays correct. (Proper bold-
            // italic trait composition deferred as polish.)
            let font: NSFont = currentHeadingLevel > 0
                ? Typography.headingFont(level: currentHeadingLevel)
                : Typography.italicFont
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [.font: font]
            ))
            tagWrappingDelimiters(range: range, markerLength: 1)
        }
        for child in emphasis.children { walk(child) }
    }

    private func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = sourceNSRange(inlineCode) else { return }
        assignments.append(AttributeAssignment(
            range: range,
            attributes: [
                .font: Typography.codeFont,
                .backgroundColor: Typography.codeBackground
            ]
        ))
        // Finding #3 fix: swift-markdown's `range` for InlineCode may be
        // content-only (no backticks) in some cases. Find the actual
        // backtick delimiters by scanning the source adjacent to `range`.
        if let (leading, trailing) = locateBacktickDelimiters(around: range) {
            tagDelimiter(leading)
            tagDelimiter(trailing)
        }
    }

    private func visitLink(_ link: Link) {
        if let range = sourceNSRange(link) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [
                    .foregroundColor: Typography.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            ))
        }
        for child in link.children { walk(child) }
    }

    private func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = sourceNSRange(codeBlock) else { return }
        assignments.append(AttributeAssignment(
            range: range,
            attributes: [
                .font: Typography.codeFont,
                .backgroundColor: Typography.codeBackground
            ]
        ))
        // Finding #4 fix: tag opening and closing fence lines as
        // delimiters so they collapse/reveal like other markdown syntax.
        tagFenceLines(in: range)
        // Extend the reveal scope across the whole block so clicking
        // into the content reveals the fences (which otherwise sit on
        // collapsed, unclickable lines).
        assignments.append(AttributeAssignment(
            range: range,
            attributes: [Typography.revealScopeKey: NSValue(range: range)]
        ))
    }

    /// D8: precompute a `TableLayout` for this table and tag each
    /// source line (head, separator, body rows) with a
    /// `TableRowAttachment`. The layout-manager delegate swaps in
    /// `TableRowFragment` instances at render time.
    ///
    /// swift-markdown `Table.Head` is itself the header row (a
    /// `TableCellContainer`, not a wrapper around a `Table.Row`). Its
    /// cells live directly under it. `Table.Body` wraps multiple
    /// rows. We treat head as row-with-cells for layout purposes.
    ///
    /// Row source ranges reported by swift-markdown can overshoot the
    /// single logical line (trailing newline, next-row prefix). We
    /// clamp each row to its source line via newline detection so the
    /// attachment attribute doesn't leak into the next paragraph.
    private func visitTable(_ table: Table) {
        guard let tableRange = sourceNSRange(table), tableRange.length > 0
        else {
            for child in table.children { walk(child) }
            return
        }

        // Extract cells from each row. Head IS the header row.
        let headCells: [Table.Cell] = table.head.children.compactMap { $0 as? Table.Cell }
        let bodyRows: [Table.Row] = table.body.children.compactMap { $0 as? Table.Row }
        let bodyRowCells: [[Table.Cell]] = bodyRows.map { row in
            row.children.compactMap { $0 as? Table.Cell }
        }

        let columnCount = max(headCells.count,
                              bodyRowCells.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return }

        // Build per-row cell attributed strings. V1 cell renderer =
        // plain source substring (trimmed), with bold font on header.
        var cellContentPerRow: [[NSAttributedString]] = []
        cellContentPerRow.append(
            renderCells(headCells,
                        font: Typography.boldFont,
                        padTo: columnCount)
        )
        for rowCells in bodyRowCells {
            cellContentPerRow.append(
                renderCells(rowCells,
                            font: Typography.baseFont,
                            padTo: columnCount)
            )
        }

        // Measure column widths: max natural width per column, capped
        // so a single wide cell doesn't eat the viewport. Cells wider
        // than the cap wrap within the column.
        let columnCap: CGFloat = 320
        var widths: [CGFloat] = Array(repeating: 0, count: columnCount)
        for rowCells in cellContentPerRow {
            for (col, cell) in rowCells.enumerated() where col < columnCount {
                widths[col] = max(widths[col], min(cell.size().width, columnCap))
            }
        }
        widths = widths.map { max($0, 60) }

        let layout = TableLayout(
            columnCount: columnCount,
            contentWidths: widths,
            alignments: table.columnAlignments,
            cellContentPerRow: cellContentPerRow,
            tableRange: tableRange
        )

        // Build a paragraph style that reserves the target row height
        // via minimumLineHeight. Without this, the underlying text
        // line only has natural ~18pt height → clicks in the grid's
        // "dead zone" between 18pt and our claimed layoutFragmentFrame
        // height don't hit any line fragment and no caret placement
        // happens. With the paragraph style, hit-testing bounds match
        // the visual bounds.
        func paragraphStyle(for height: CGFloat) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            return style
        }

        let headerLineRange = clampedLineRange(
            startingNear: sourceNSRange(table.head)?.location ?? tableRange.location,
            within: tableRange
        )
        if let headerLineRange = headerLineRange {
            let headerHeight = layout.rowHeight.first ?? 20
            assignments.append(AttributeAssignment(
                range: headerLineRange,
                attributes: [
                    TableAttributeKeys.rowAttachmentKey: TableRowAttachment(
                        layout: layout,
                        kind: .header,
                        cellContentIndex: 0,
                        isFirstRow: true,
                        isLastRow: false),
                    .paragraphStyle: paragraphStyle(for: headerHeight)
                ]
            ))

            // Separator line is the line immediately after the header.
            let afterHeader = NSMaxRange(headerLineRange) + 1 // skip the \n
            if let sepLineRange = clampedLineRange(
                startingNear: afterHeader,
                within: tableRange
            ) {
                assignments.append(AttributeAssignment(
                    range: sepLineRange,
                    attributes: [
                        TableAttributeKeys.rowAttachmentKey: TableRowAttachment(
                            layout: layout,
                            kind: .separator,
                            cellContentIndex: nil,
                            isFirstRow: false,
                            isLastRow: false),
                        .paragraphStyle: paragraphStyle(for: 3)
                    ]
                ))
            }
        }

        // Body rows — tag each clamped to its own line.
        let totalRowCount = 1 + bodyRows.count
        for (bodyIdx, row) in bodyRows.enumerated() {
            let rawStart = sourceNSRange(row)?.location ?? 0
            guard let clamped = clampedLineRange(
                startingNear: rawStart,
                within: tableRange
            ) else { continue }
            let rowIdx = bodyIdx + 1 // index 0 = header
            let isLast = rowIdx == totalRowCount - 1
            let rowHeight = rowIdx < layout.rowHeight.count
                ? layout.rowHeight[rowIdx]
                : 20
            assignments.append(AttributeAssignment(
                range: clamped,
                attributes: [
                    TableAttributeKeys.rowAttachmentKey: TableRowAttachment(
                        layout: layout,
                        kind: .body,
                        cellContentIndex: rowIdx,
                        isFirstRow: false,
                        isLastRow: isLast),
                    .paragraphStyle: paragraphStyle(for: rowHeight)
                ]
            ))
        }
    }

    /// Render a list of cells to attributed strings and pad out to
    /// `columnCount` with empty cells if the row is short.
    private func renderCells(_ cells: [Table.Cell],
                             font: NSFont,
                             padTo columnCount: Int) -> [NSAttributedString] {
        var out: [NSAttributedString] = []
        for cell in cells {
            out.append(cellContent(for: cell, font: font))
        }
        while out.count < columnCount {
            out.append(NSAttributedString(
                string: "",
                attributes: [.font: font,
                             .foregroundColor: NSColor.labelColor]))
        }
        return out
    }

    /// Find the line range starting at or after `startingNear`,
    /// clamped so it stops at the first newline (exclusive). Line
    /// must begin within `tableRange`. Returns `nil` if the start is
    /// out of bounds.
    private func clampedLineRange(startingNear start: Int,
                                  within tableRange: NSRange) -> NSRange? {
        let length = nsSource.length
        let tableEnd = NSMaxRange(tableRange)
        let newline = unichar(UnicodeScalar("\n").value)
        var begin = start
        // If `start` landed mid-line, rewind to the start of that line.
        while begin > 0, begin - 1 < length,
              nsSource.character(at: begin - 1) != newline {
            begin -= 1
            if begin <= tableRange.location { break }
        }
        guard begin < length, begin < tableEnd else { return nil }
        var end = begin
        while end < length, end < tableEnd, nsSource.character(at: end) != newline {
            end += 1
        }
        let len = end - begin
        guard len > 0 else { return nil }
        return NSRange(location: begin, length: len)
    }

    /// Extract plain-text cell content from source by taking only the
    /// first line (cell's range can overshoot into the next row in
    /// swift-markdown's representation for trailing cells) and
    /// stripping surrounding `|` + whitespace. V1 default renderer.
    private func cellContent(for cell: Table.Cell, font: NSFont) -> NSAttributedString {
        let range = sourceNSRange(cell) ?? NSRange(location: 0, length: 0)
        let rawText: String
        if range.length > 0, NSMaxRange(range) <= nsSource.length {
            rawText = nsSource.substring(with: range)
        } else {
            rawText = cell.plainText
        }
        let firstLine = rawText.components(separatedBy: "\n").first ?? rawText
        let trimmed = firstLine.trimmingCharacters(in: .init(charactersIn: "| \t"))
        return NSAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ])
    }

    // MARK: - Range helpers

    private func sourceNSRange(_ markup: Markup) -> NSRange? {
        guard let sr = markup.range else { return nil }
        return converter.nsRange(for: sr)
    }

    private func leadingHashRange(in range: NSRange, expectedHashes: Int) -> NSRange? {
        var index = range.location
        let end = range.location + range.length
        var hashes = 0
        let hashChar = unichar(UnicodeScalar("#").value)
        let spaceChar = unichar(UnicodeScalar(" ").value)
        while index < end, nsSource.character(at: index) == hashChar {
            hashes += 1
            index += 1
        }
        guard hashes == expectedHashes else { return nil }
        if index < end, nsSource.character(at: index) == spaceChar {
            index += 1
        }
        return NSRange(location: range.location, length: index - range.location)
    }

    /// For Strong and Emphasis — the range reported by swift-markdown
    /// includes the wrapping `**`/`*` markers, so we tag the first and
    /// last `markerLength` characters as delimiters.
    private func tagWrappingDelimiters(range: NSRange, markerLength: Int) {
        guard range.length >= markerLength * 2 else { return }
        let leading = NSRange(location: range.location, length: markerLength)
        let trailing = NSRange(location: range.location + range.length - markerLength, length: markerLength)
        tagDelimiter(leading)
        tagDelimiter(trailing)
    }

    /// Finding #3 fix. Given a range that may or may not include
    /// backticks, find the single backtick delimiters immediately
    /// adjacent to the content. Returns (leading, trailing) ranges.
    private func locateBacktickDelimiters(around range: NSRange) -> (NSRange, NSRange)? {
        let backtick = unichar(UnicodeScalar("`").value)
        let length = nsSource.length

        // If range starts with a backtick, it's inclusive. Otherwise,
        // the backtick is the char just before range.location.
        var leading: NSRange?
        if range.location < length, nsSource.character(at: range.location) == backtick {
            leading = NSRange(location: range.location, length: 1)
        } else if range.location - 1 >= 0, nsSource.character(at: range.location - 1) == backtick {
            leading = NSRange(location: range.location - 1, length: 1)
        }

        var trailing: NSRange?
        let endIndex = range.location + range.length
        if endIndex - 1 >= 0, endIndex - 1 < length, nsSource.character(at: endIndex - 1) == backtick {
            trailing = NSRange(location: endIndex - 1, length: 1)
        } else if endIndex < length, nsSource.character(at: endIndex) == backtick {
            trailing = NSRange(location: endIndex, length: 1)
        }

        if let l = leading, let t = trailing {
            return (l, t)
        }
        return nil
    }

    /// Finding #4 fix. Find the `` ``` `` (or `` ~~~ ``) fence lines
    /// bounding a code block's range and tag them as delimiters. Works
    /// by scanning from `range.location` forward to the first newline
    /// (opening fence line) and from the end backward to find the last
    /// fence line.
    private func tagFenceLines(in range: NSRange) {
        let length = nsSource.length
        guard range.length > 0, range.location + range.length <= length else { return }
        let backtick = unichar(UnicodeScalar("`").value)
        let tilde = unichar(UnicodeScalar("~").value)
        let newline = unichar(UnicodeScalar("\n").value)
        let rangeEnd = range.location + range.length

        // Helper: is `position` the start of a fence line (3+ backticks or tildes)?
        func isFenceChar(_ ch: unichar) -> Bool { ch == backtick || ch == tilde }

        func fenceLineRange(startingAt pos: Int) -> NSRange? {
            guard pos < length else { return nil }
            let ch = nsSource.character(at: pos)
            guard isFenceChar(ch) else { return nil }
            var count = 0
            var i = pos
            while i < length, nsSource.character(at: i) == ch {
                count += 1
                i += 1
            }
            guard count >= 3 else { return nil }
            // Consume rest of line up to (not including) newline.
            while i < length, nsSource.character(at: i) != newline {
                i += 1
            }
            return NSRange(location: pos, length: i - pos)
        }

        // Opening fence: at range.location.
        if let opening = fenceLineRange(startingAt: range.location) {
            tagDelimiter(opening)
        }

        // Closing fence: find the last newline before rangeEnd, then
        // check if the line that follows it begins with a fence char.
        var lastLineStart = range.location
        var i = range.location
        while i < rangeEnd {
            if nsSource.character(at: i) == newline {
                lastLineStart = i + 1
            }
            i += 1
        }
        if let closing = fenceLineRange(startingAt: lastLineStart) {
            tagDelimiter(closing)
        }
    }

    private func tagDelimiter(_ range: NSRange) {
        assignments.append(AttributeAssignment(
            range: range,
            attributes: [Typography.syntaxRoleKey: "delimiter"]
        ))
        spans.append(SyntaxSpan(range: range, role: .delimiter))
    }
}
