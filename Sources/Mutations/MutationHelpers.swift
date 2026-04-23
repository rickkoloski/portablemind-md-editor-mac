import Foundation
import Markdown

/// Shared helpers used by mutation primitives. Kept as a single enum
/// namespace rather than free functions to make their call sites
/// self-describing.
enum MutationHelpers {

    // MARK: - Selection normalization

    /// If the selection ends on a trailing newline character, shrink
    /// it to exclude that newline. Selection-based mutations then wrap
    /// the content without eating the line terminator.
    static func trimTrailingNewline(_ sel: NSRange, in source: NSString) -> NSRange {
        guard sel.length > 0 else { return sel }
        let lastIndex = sel.location + sel.length - 1
        guard lastIndex < source.length else { return sel }
        if source.character(at: lastIndex) == unichar(UnicodeScalar("\n").value) {
            return NSRange(location: sel.location, length: sel.length - 1)
        }
        return sel
    }

    // MARK: - AST lookup

    /// Walk the document's descendants looking for a node of the given
    /// type whose NSRange fully contains `selection`. Returns the
    /// outermost matching node's range, or nil.
    static func enclosingNodeRange<T: Markup>(
        of nodeType: T.Type,
        containing selection: NSRange,
        in document: Document,
        using converter: SourceLocationConverter
    ) -> NSRange? {
        var found: NSRange?
        walk(document) { node in
            guard node is T,
                  let range = node.range.flatMap({ converter.nsRange(for: $0) }) else {
                return
            }
            // Fully-contains test.
            if range.location <= selection.location,
               range.location + range.length >= selection.location + selection.length {
                found = range
            }
        }
        return found
    }

    private static func walk(_ markup: Markup, _ visit: (Markup) -> Void) {
        visit(markup)
        for child in markup.children {
            walk(child, visit)
        }
    }

    // MARK: - Wrap / unwrap

    static func wrap(selection: NSRange, with marker: String, in source: String) -> MutationOutput {
        let nsSource = source as NSString
        let before = nsSource.substring(to: selection.location)
        let middle = nsSource.substring(with: selection)
        let after = nsSource.substring(from: selection.location + selection.length)
        let newSource = before + marker + middle + marker + after
        let newSelection = NSRange(
            location: selection.location + (marker as NSString).length,
            length: selection.length
        )
        return MutationOutput(newSource: newSource, newSelection: newSelection)
    }

    /// Remove the surrounding markers from `wrappedRange`. The new
    /// selection is the original content (ex-markers).
    static func unwrap(
        wrappedRange: NSRange,
        markerLength: Int,
        in source: String
    ) -> MutationOutput {
        let nsSource = source as NSString
        let innerLocation = wrappedRange.location + markerLength
        let innerLength = wrappedRange.length - markerLength * 2
        let innerRange = NSRange(location: innerLocation, length: max(0, innerLength))
        let innerText = nsSource.substring(with: innerRange)

        let before = nsSource.substring(to: wrappedRange.location)
        let after = nsSource.substring(from: wrappedRange.location + wrappedRange.length)
        let newSource = before + innerText + after
        let newSelection = NSRange(location: wrappedRange.location, length: innerText.utf16.count)
        return MutationOutput(newSource: newSource, newSelection: newSelection)
    }

    // MARK: - Line-based

    /// Compute the `NSRange` covering every full line touched by
    /// `selection`. Empty selections touch exactly one line.
    static func linesCovering(_ selection: NSRange, in source: NSString) -> NSRange {
        let start = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let endPoint = selection.location + selection.length
        let endClamped = min(endPoint, source.length)
        let end = source.lineRange(for: NSRange(location: max(0, endClamped - (endPoint > selection.location ? 1 : 0)), length: 0))
        let location = start.location
        let length = (end.location + end.length) - location
        return NSRange(location: location, length: length)
    }

    /// Run `transform` on each line in `linesRange` and produce a new
    /// source. Returns the rewritten source and a selection that spans
    /// the same logical lines in the new source.
    static func rewriteLines(
        _ linesRange: NSRange,
        in source: String,
        transform: (String) -> String
    ) -> MutationOutput {
        let nsSource = source as NSString
        let before = nsSource.substring(to: linesRange.location)
        let affected = nsSource.substring(with: linesRange)
        let after = nsSource.substring(from: linesRange.location + linesRange.length)

        // Split keeping the trailing newline on each line except possibly the last.
        var rewritten = ""
        var cursor = 0
        let affectedNS = affected as NSString
        while cursor < affectedNS.length {
            let lineRange = affectedNS.lineRange(for: NSRange(location: cursor, length: 0))
            let line = affectedNS.substring(with: lineRange)
            // Separate trailing newline so transform sees clean content.
            var content = line
            var trailer = ""
            if line.hasSuffix("\n") {
                content = String(line.dropLast())
                trailer = "\n"
            }
            rewritten += transform(content) + trailer
            cursor = lineRange.location + lineRange.length
        }

        let newSource = before + rewritten + after
        let newSelection = NSRange(location: linesRange.location, length: (rewritten as NSString).length)
        return MutationOutput(newSource: newSource, newSelection: newSelection)
    }

    // MARK: - Heading helpers

    /// Current heading level of `line` (the line *content*, without a
    /// trailing newline). 0 = body. 1–6 = H1–H6.
    static func headingLevel(of line: String) -> Int {
        let ns = line as NSString
        var hashes = 0
        var i = 0
        let hashChar = unichar(UnicodeScalar("#").value)
        let spaceChar = unichar(UnicodeScalar(" ").value)
        while i < ns.length, ns.character(at: i) == hashChar, hashes < 6 {
            hashes += 1
            i += 1
        }
        guard hashes >= 1, hashes <= 6 else { return 0 }
        guard i < ns.length, ns.character(at: i) == spaceChar else { return 0 }
        return hashes
    }

    /// Apply a heading level to a line of *content* (no trailing \n).
    /// Strips existing heading prefix and any single leading list
    /// prefix (`- ` or `N. `), then prepends the new prefix. Per spec
    /// OQ #3, heading replaces list prefix.
    static func setHeadingLevel(line: String, toLevel level: Int) -> String {
        let content = stripLeadingFormattingPrefix(line)
        if level <= 0 { return content }
        let prefix = String(repeating: "#", count: min(max(level, 1), 6)) + " "
        return prefix + content
    }

    /// Strip a single leading `#…#  `, `- `, `* `, or `NN. ` prefix.
    static func stripLeadingFormattingPrefix(_ line: String) -> String {
        let ns = line as NSString
        // Heading
        var i = 0
        let hashChar = unichar(UnicodeScalar("#").value)
        let spaceChar = unichar(UnicodeScalar(" ").value)
        while i < ns.length, ns.character(at: i) == hashChar, i < 6 {
            i += 1
        }
        if i >= 1, i < ns.length, ns.character(at: i) == spaceChar {
            return ns.substring(from: i + 1)
        }
        // Bullet
        if ns.length >= 2 {
            let c0 = ns.character(at: 0)
            let c1 = ns.character(at: 1)
            if (c0 == unichar(UnicodeScalar("-").value) || c0 == unichar(UnicodeScalar("*").value)) && c1 == spaceChar {
                return ns.substring(from: 2)
            }
        }
        // Numbered: run of digits, then ". "
        var j = 0
        while j < ns.length, let scalar = UnicodeScalar(ns.character(at: j)), CharacterSet.decimalDigits.contains(scalar) {
            j += 1
        }
        if j >= 1, j + 1 < ns.length,
           ns.character(at: j) == unichar(UnicodeScalar(".").value),
           ns.character(at: j + 1) == spaceChar {
            return ns.substring(from: j + 2)
        }
        return line
    }

    // MARK: - List helpers

    static func isBulletLine(_ line: String) -> Bool {
        let ns = line as NSString
        guard ns.length >= 2 else { return false }
        let c0 = ns.character(at: 0)
        let c1 = ns.character(at: 1)
        let space = unichar(UnicodeScalar(" ").value)
        return (c0 == unichar(UnicodeScalar("-").value) || c0 == unichar(UnicodeScalar("*").value)) && c1 == space
    }

    static func isNumberedLine(_ line: String) -> Bool {
        let ns = line as NSString
        var j = 0
        while j < ns.length, let scalar = UnicodeScalar(ns.character(at: j)), CharacterSet.decimalDigits.contains(scalar) {
            j += 1
        }
        return j >= 1
            && j + 1 < ns.length
            && ns.character(at: j) == unichar(UnicodeScalar(".").value)
            && ns.character(at: j + 1) == unichar(UnicodeScalar(" ").value)
    }
}
