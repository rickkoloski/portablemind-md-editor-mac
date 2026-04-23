import Foundation
import Markdown

enum InlineCodeMutation: MutationPrimitive {
    static let identifier = "mutation.inlineCode"
    private static let marker = "`"

    static func apply(to input: MutationInput) -> MutationOutput? {
        let sel = MutationHelpers.trimTrailingNewline(input.selection, in: input.nsSource)

        // InlineCode's own range in swift-markdown may be content-only,
        // so we scan adjacent to the selection for existing backticks
        // rather than relying on enclosingNodeRange semantics.
        let nsSource = input.nsSource
        let length = nsSource.length
        let backtick = unichar(UnicodeScalar("`").value)
        let leftNeighbor = sel.location - 1
        let rightNeighbor = sel.location + sel.length
        if leftNeighbor >= 0,
           rightNeighbor < length,
           nsSource.character(at: leftNeighbor) == backtick,
           nsSource.character(at: rightNeighbor) == backtick {
            // Unwrap: drop the two surrounding backticks.
            let wrappedRange = NSRange(location: leftNeighbor, length: sel.length + 2)
            return MutationHelpers.unwrap(
                wrappedRange: wrappedRange,
                markerLength: 1,
                in: input.source
            )
        }

        guard sel.length > 0 else { return nil }
        return MutationHelpers.wrap(selection: sel, with: marker, in: input.source)
    }
}
