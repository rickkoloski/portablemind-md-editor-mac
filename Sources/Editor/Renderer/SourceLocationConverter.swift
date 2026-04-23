import Foundation
import Markdown

/// Converts swift-markdown `SourceLocation` (1-based line + column, UTF-8
/// bytes) into UTF-16 NSString offsets against the raw source.
///
/// D1 findings #3 and #4 were both off-by-N bugs in the spike's inline
/// line-walking version of this. Caching line starts once per parse
/// lets every `nsOffset(line:column:)` call run in O(1), and puts the
/// conversion logic in one place where it can be unit-tested in
/// isolation.
///
/// Note on column semantics: swift-markdown uses 1-based UTF-8 byte
/// columns. For ASCII content (our realistic worst case during heavy
/// HITL work), byte == UTF-16 code unit. For multibyte content this is
/// approximate; D2 accepts that — when we hit a real problem, we revisit.
final class SourceLocationConverter {
    private let source: NSString
    /// UTF-16 offset of the start of each 1-based line.
    /// `lineStarts[0]` = 0 (start of line 1).
    /// `lineStarts.count` = number of lines + 1 (last entry = end-of-string
    /// position for correct handling of trailing locations).
    private let lineStarts: [Int]

    init(source: String) {
        let ns = source as NSString
        self.source = ns
        var starts = [0]
        let length = ns.length
        var i = 0
        while i < length {
            let ch = ns.character(at: i)
            i += 1
            if ch == unichar(UnicodeScalar("\n").value) {
                starts.append(i)
            }
        }
        starts.append(length)
        self.lineStarts = starts
    }

    /// UTF-16 offset of the given 1-based line+column. Clamped to the
    /// string length. Returns NSNotFound only for clearly invalid lines.
    func nsOffset(line: Int, column: Int) -> Int {
        guard line >= 1, line < lineStarts.count else { return NSNotFound }
        let base = lineStarts[line - 1]
        let columnOffset = max(0, column - 1)
        return min(base + columnOffset, source.length)
    }

    func nsOffset(for location: SourceLocation) -> Int {
        nsOffset(line: location.line, column: location.column)
    }

    /// UTF-16 range from lowerBound to upperBound of a SourceRange.
    func nsRange(for range: SourceRange) -> NSRange? {
        let start = nsOffset(for: range.lowerBound)
        let end = nsOffset(for: range.upperBound)
        guard start != NSNotFound, end != NSNotFound, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
