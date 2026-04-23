import Foundation
import Markdown

enum BoldMutation: MutationPrimitive {
    static let identifier = "mutation.bold"
    private static let marker = "**"

    static func apply(to input: MutationInput) -> MutationOutput? {
        let sel = MutationHelpers.trimTrailingNewline(input.selection, in: input.nsSource)
        if let enclosing = MutationHelpers.enclosingNodeRange(
            of: Strong.self,
            containing: sel,
            in: input.document,
            using: input.converter
        ) {
            return MutationHelpers.unwrap(
                wrappedRange: enclosing,
                markerLength: (marker as NSString).length,
                in: input.source
            )
        }
        guard sel.length > 0 else { return nil }
        return MutationHelpers.wrap(selection: sel, with: marker, in: input.source)
    }
}
