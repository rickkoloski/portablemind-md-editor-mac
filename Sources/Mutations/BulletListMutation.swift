import Foundation
import Markdown

enum BulletListMutation: MutationPrimitive {
    static let identifier = "mutation.bulletList"
    private static let prefix = "- "

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

        let allBullet = lines.allSatisfy { MutationHelpers.isBulletLine($0) }

        return MutationHelpers.rewriteLines(linesRange, in: input.source) { line in
            if allBullet {
                // Strip bullet prefix.
                return MutationHelpers.stripLeadingFormattingPrefix(line)
            }
            // Apply bullet if not already. If already bullet, leave as-is.
            if MutationHelpers.isBulletLine(line) { return line }
            // Also strip any heading/numbered prefix before applying bullet.
            let content = MutationHelpers.stripLeadingFormattingPrefix(line)
            return prefix + content
        }
    }
}
