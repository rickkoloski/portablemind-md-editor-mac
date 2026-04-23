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
