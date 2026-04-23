import Foundation

extension String {
    /// Convert a 1-based (line, column) coordinate to an NSRange
    /// location suitable for `NSTextView.setSelectedRange`.
    ///
    /// - Line 1 is the first line.
    /// - Column 1 is the first character on that line.
    /// - Line beyond EOF clamps to the last line.
    /// - Column beyond end-of-line clamps to end-of-line (before
    ///   the trailing newline, if any).
    /// - Non-positive inputs clamp to 1.
    func nsLocation(forLine line: Int, column: Int) -> Int {
        let ns = self as NSString
        let length = ns.length
        let targetLine = max(1, line)
        let targetCol = max(1, column)

        var currentLine = 1
        var lineStart = 0
        let newline = unichar(UnicodeScalar("\n").value)

        var i = 0
        while i < length, currentLine < targetLine {
            if ns.character(at: i) == newline {
                currentLine += 1
                lineStart = i + 1
            }
            i += 1
        }

        // If we fell off the end before reaching the target line,
        // clamp to the start of the last line.
        if currentLine < targetLine {
            // `lineStart` is already the start of whatever final line
            // we reached. Fall through to clamp the column to that
            // line's end.
        }

        var lineEnd = lineStart
        while lineEnd < length, ns.character(at: lineEnd) != newline {
            lineEnd += 1
        }

        let loc = lineStart + (targetCol - 1)
        return min(loc, lineEnd)
    }
}
