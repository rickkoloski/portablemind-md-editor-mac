import Foundation
import Markdown

/// Heading level toggles (H1..H6 plus "Body" which strips heading
/// formatting). One enum per level to give each a distinct
/// `identifier` for the dispatcher / keyboard bindings.

private func applyHeading(level: Int, to input: MutationInput) -> MutationOutput? {
    let nsSource = input.nsSource
    let linesRange = MutationHelpers.linesCovering(input.selection, in: nsSource)
    let affected = nsSource.substring(with: linesRange)

    // Collect current levels per line.
    var lines: [String] = []
    let ns = affected as NSString
    var cursor = 0
    while cursor < ns.length {
        let lr = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let raw = ns.substring(with: lr)
        lines.append(raw.hasSuffix("\n") ? String(raw.dropLast()) : raw)
        cursor = lr.location + lr.length
    }
    if lines.isEmpty {
        lines.append("")
    }

    let allAtTarget = level > 0 && lines.allSatisfy { MutationHelpers.headingLevel(of: $0) == level }
    let target = allAtTarget ? 0 : level

    return MutationHelpers.rewriteLines(linesRange, in: input.source) { line in
        MutationHelpers.setHeadingLevel(line: line, toLevel: target)
    }
}

enum Heading1Mutation: MutationPrimitive {
    static let identifier = "mutation.heading1"
    static func apply(to input: MutationInput) -> MutationOutput? { applyHeading(level: 1, to: input) }
}

enum Heading2Mutation: MutationPrimitive {
    static let identifier = "mutation.heading2"
    static func apply(to input: MutationInput) -> MutationOutput? { applyHeading(level: 2, to: input) }
}

enum Heading3Mutation: MutationPrimitive {
    static let identifier = "mutation.heading3"
    static func apply(to input: MutationInput) -> MutationOutput? { applyHeading(level: 3, to: input) }
}

enum Heading4Mutation: MutationPrimitive {
    static let identifier = "mutation.heading4"
    static func apply(to input: MutationInput) -> MutationOutput? { applyHeading(level: 4, to: input) }
}

enum Heading5Mutation: MutationPrimitive {
    static let identifier = "mutation.heading5"
    static func apply(to input: MutationInput) -> MutationOutput? { applyHeading(level: 5, to: input) }
}

enum Heading6Mutation: MutationPrimitive {
    static let identifier = "mutation.heading6"
    static func apply(to input: MutationInput) -> MutationOutput? { applyHeading(level: 6, to: input) }
}

enum BodyMutation: MutationPrimitive {
    static let identifier = "mutation.body"
    static func apply(to input: MutationInput) -> MutationOutput? {
        // Body = "level 0" = strip any heading prefix from each line.
        let linesRange = MutationHelpers.linesCovering(input.selection, in: input.nsSource)
        return MutationHelpers.rewriteLines(linesRange, in: input.source) { line in
            MutationHelpers.setHeadingLevel(line: line, toLevel: 0)
        }
    }
}
