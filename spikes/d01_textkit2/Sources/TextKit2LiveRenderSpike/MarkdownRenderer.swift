import AppKit
import Foundation
import Markdown

/// Parses markdown with swift-markdown and produces a list of attribute
/// assignments keyed to UTF-16 offsets in the source string. Also
/// produces a list of syntax spans so the cursor-on-line tracker can
/// find delimiter ranges later without re-parsing.
///
/// Spike scope: Heading, Strong (bold), Emphasis (italic), InlineCode,
/// Link, CodeBlock. Enough to exercise the live-render patterns named
/// in the plan (§2 Requirements).
struct MarkdownRenderResult {
    let assignments: [AttributeAssignment]
    let spans: [SyntaxSpan]
}

final class MarkdownRenderer {
    /// Parse and render. Returns assignments in source-order; callers
    /// apply them in a single begin/endEditing block.
    func render(_ source: String) -> MarkdownRenderResult {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        let visitor = RenderVisitor(nsSource: nsSource)

        // Apply base body attributes first; specific elements overwrite.
        visitor.assignments.append(AttributeAssignment(
            range: fullRange,
            attributes: [
                .font: SpikeTypography.baseFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.textBackgroundColor
            ]
        ))

        let document = Document(parsing: source)
        visitor.walk(document)

        return MarkdownRenderResult(assignments: visitor.assignments, spans: visitor.spans)
    }
}

/// A hand-rolled traversal over swift-markdown's AST. We don't conform
/// to MarkupWalker because its protocol extension uses `mutating`
/// semantics that don't play cleanly with class-based accumulation.
/// Keeping traversal explicit is fine for a spike.
private final class RenderVisitor {
    let nsSource: NSString
    var assignments: [AttributeAssignment] = []
    var spans: [SyntaxSpan] = []

    init(nsSource: NSString) {
        self.nsSource = nsSource
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

    private func visitHeading(_ heading: Heading) {
        if let range = nsRange(for: heading) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [.font: SpikeTypography.headingFont(level: heading.level)]
            ))
        }
        if let markerRange = leadingMarkerRange(for: heading) {
            assignments.append(AttributeAssignment(
                range: markerRange,
                attributes: [SpikeTypography.syntaxRoleKey: "delimiter"]
            ))
            spans.append(SyntaxSpan(range: markerRange, role: .delimiter))
        }
        for child in heading.children { walk(child) }
    }

    private func visitStrong(_ strong: Strong) {
        if let range = nsRange(for: strong) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [.font: SpikeTypography.boldFont]
            ))
            tagDelimiters(aroundFullRange: range, marker: "**")
        }
        for child in strong.children { walk(child) }
    }

    private func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(for: emphasis) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [.font: SpikeTypography.italicFont]
            ))
            tagDelimiters(aroundFullRange: range, marker: "*")
        }
        for child in emphasis.children { walk(child) }
    }

    private func visitInlineCode(_ inlineCode: InlineCode) {
        if let range = nsRange(for: inlineCode) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [
                    .font: SpikeTypography.codeFont,
                    .backgroundColor: SpikeTypography.codeBackground
                ]
            ))
            tagDelimiters(aroundFullRange: range, marker: "`")
        }
    }

    private func visitLink(_ link: Link) {
        if let range = nsRange(for: link) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [
                    .foregroundColor: SpikeTypography.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            ))
        }
        for child in link.children { walk(child) }
    }

    private func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = nsRange(for: codeBlock) {
            assignments.append(AttributeAssignment(
                range: range,
                attributes: [
                    .font: SpikeTypography.codeFont,
                    .backgroundColor: SpikeTypography.codeBackground
                ]
            ))
        }
    }

    // MARK: - Helpers

    private func tagDelimiters(aroundFullRange range: NSRange, marker: String) {
        let markerLen = (marker as NSString).length
        guard range.length >= markerLen * 2 else { return }
        let leading = NSRange(location: range.location, length: markerLen)
        let trailing = NSRange(location: range.location + range.length - markerLen, length: markerLen)
        assignments.append(AttributeAssignment(
            range: leading,
            attributes: [SpikeTypography.syntaxRoleKey: "delimiter"]
        ))
        assignments.append(AttributeAssignment(
            range: trailing,
            attributes: [SpikeTypography.syntaxRoleKey: "delimiter"]
        ))
        spans.append(SyntaxSpan(range: leading, role: .delimiter))
        spans.append(SyntaxSpan(range: trailing, role: .delimiter))
    }

    private func leadingMarkerRange(for heading: Heading) -> NSRange? {
        guard let range = nsRange(for: heading) else { return nil }
        var index = range.location
        let end = range.location + range.length
        var hashes = 0
        while index < end && nsSource.character(at: index) == unichar(UnicodeScalar("#").value) {
            hashes += 1
            index += 1
        }
        guard hashes == heading.level else { return nil }
        if index < end && nsSource.character(at: index) == unichar(UnicodeScalar(" ").value) {
            index += 1
        }
        return NSRange(location: range.location, length: index - range.location)
    }

    /// Convert a Markup node's SourceRange (line/column, 1-based, UTF-8)
    /// into a UTF-16 NSRange against the raw NSString.
    private func nsRange(for markup: Markup) -> NSRange? {
        guard let source = markup.range else { return nil }
        let startOffset = offset(for: source.lowerBound)
        let endOffset = offset(for: source.upperBound)
        guard startOffset != NSNotFound, endOffset != NSNotFound, endOffset >= startOffset else {
            return nil
        }
        return NSRange(location: startOffset, length: endOffset - startOffset)
    }

    /// 1-based line + column (UTF-8 bytes) → UTF-16 NSString offset.
    /// Approximate for multibyte content; spike-accept.
    private func offset(for location: SourceLocation) -> Int {
        let targetLine = location.line
        let targetColumn = location.column
        var currentLine = 1
        var index = 0
        let length = nsSource.length
        while index < length && currentLine < targetLine {
            let ch = nsSource.character(at: index)
            index += 1
            if ch == unichar(UnicodeScalar("\n").value) {
                currentLine += 1
            }
        }
        let columnOffset = targetColumn - 1
        let result = index + columnOffset
        return min(max(result, 0), length)
    }
}
