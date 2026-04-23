import Foundation
import Markdown

enum NumberedListMutation: MutationPrimitive {
    static let identifier = "mutation.numberedList"

    static func apply(to input: MutationInput) -> MutationOutput? {
        let nsSource = input.nsSource
        let linesRange = MutationHelpers.linesCovering(input.selection, in: nsSource)
        let affected = nsSource.substring(with: linesRange)

        // Collect lines to check uniformity.
        var lines: [String] = []
        let ns = affected as NSString
        var cursor = 0
        while cursor < ns.length {
            let lr = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let raw = ns.substring(with: lr)
            lines.append(raw.hasSuffix("\n") ? String(raw.dropLast()) : raw)
            cursor = lr.location + lr.length
        }
        if lines.isEmpty { lines.append("") }

        let allNumbered = lines.allSatisfy { MutationHelpers.isNumberedLine($0) }

        // We need a per-line counter; rewriteLines doesn't provide an
        // index, so do the walk inline here.
        let before = nsSource.substring(to: linesRange.location)
        let after = nsSource.substring(from: linesRange.location + linesRange.length)

        var rewritten = ""
        var counter = 0
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            // Match trailing-newline handling in rewriteLines: every line
            // except possibly the last gets a trailing \n.
            let originalLine = (affected as NSString).substring(with:
                (affected as NSString).lineRange(for: NSRange(location: positionOfLine(index: index, in: lines), length: 0))
            )
            let hadNewline = originalLine.hasSuffix("\n")
            let trailer = hadNewline ? "\n" : (isLast ? "" : "\n")

            let transformed: String
            if allNumbered {
                transformed = MutationHelpers.stripLeadingFormattingPrefix(line)
            } else if MutationHelpers.isNumberedLine(line) {
                transformed = line
            } else {
                counter += 1
                let content = MutationHelpers.stripLeadingFormattingPrefix(line)
                transformed = "\(counter). " + content
            }
            rewritten += transformed + trailer
        }

        let newSource = before + rewritten + after
        let newSelection = NSRange(location: linesRange.location, length: (rewritten as NSString).length)
        return MutationOutput(newSource: newSource, newSelection: newSelection)
    }

    /// Character-offset of the start of the `index`-th logical line
    /// within the `lines` array's serialized form. Utility for locating
    /// the original line span when walking.
    private static func positionOfLine(index: Int, in lines: [String]) -> Int {
        var total = 0
        for i in 0..<index {
            total += (lines[i] as NSString).length + 1  // +1 for \n between lines
        }
        return total
    }
}
