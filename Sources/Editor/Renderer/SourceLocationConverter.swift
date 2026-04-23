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
/// Column semantics: swift-markdown uses 1-based UTF-8 byte columns.
/// D8 revisit: the naive "byte == UTF-16 code unit" assumption broke
/// on rows containing ✅ (3 UTF-8 bytes, 1 UTF-16 code unit) — cell
/// source ranges landed 2 UTF-16 offsets too far into the next cell.
/// This converter now walks grapheme-clusters accumulating UTF-8 byte
/// length while tracking the matching UTF-16 offset.
final class SourceLocationConverter {
    private let source: NSString
    private let swiftSource: String
    /// UTF-16 offset of the start of each 1-based line.
    /// `lineStarts[0]` = 0 (start of line 1).
    /// `lineStarts.count` = number of lines + 1 (last entry = end-of-string
    /// position for correct handling of trailing locations).
    private let lineStarts: [Int]

    init(source: String) {
        self.swiftSource = source
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

    /// UTF-16 offset of the given 1-based line+column (column is in
    /// UTF-8 bytes). Clamped to the string length. Returns NSNotFound
    /// only for clearly invalid lines.
    func nsOffset(line: Int, column: Int) -> Int {
        guard line >= 1, line < lineStarts.count else { return NSNotFound }
        let lineStartUTF16 = lineStarts[line - 1]
        let targetBytes = max(0, column - 1)
        if targetBytes == 0 { return lineStartUTF16 }

        // Map the UTF-16 line-start back to a Swift String.Index and
        // walk grapheme clusters until we've consumed `targetBytes`
        // UTF-8 bytes. Return the running UTF-16 offset at that point.
        let startIdx = String.Index(
            utf16Offset: lineStartUTF16,
            in: swiftSource
        )

        var bytesConsumed = 0
        var utf16Consumed = 0
        var idx = startIdx
        while bytesConsumed < targetBytes, idx < swiftSource.endIndex {
            let char = swiftSource[idx]
            if char == "\n" { break }
            let b = char.utf8.count
            if bytesConsumed + b > targetBytes {
                // Target lies inside this grapheme — snap to cluster boundary.
                break
            }
            bytesConsumed += b
            utf16Consumed += char.utf16.count
            idx = swiftSource.index(after: idx)
        }
        return min(lineStartUTF16 + utf16Consumed, source.length)
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
