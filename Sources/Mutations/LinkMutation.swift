import Foundation
import Markdown

enum LinkMutation: MutationPrimitive {
    static let identifier = "mutation.link"

    static func apply(to input: MutationInput) -> MutationOutput? {
        let sel = MutationHelpers.trimTrailingNewline(input.selection, in: input.nsSource)
        let nsSource = input.nsSource

        // Unwrap: if the caret / selection is inside an existing Link,
        // remove the surrounding `[…](…)` structure and leave just the
        // link text content.
        if let linkRange = MutationHelpers.enclosingNodeRange(
            of: Link.self,
            containing: sel,
            in: input.document,
            using: input.converter
        ) {
            let text = nsSource.substring(with: linkRange)
            // Find the "]" that closes the text portion.
            let ns = text as NSString
            var depth = 0
            var closeBracketInText: Int? = nil
            for i in 0..<ns.length {
                let ch = ns.character(at: i)
                if ch == unichar(UnicodeScalar("[").value) { depth += 1 }
                else if ch == unichar(UnicodeScalar("]").value) {
                    depth -= 1
                    if depth == 0 {
                        closeBracketInText = i
                        break
                    }
                }
            }
            guard let closeInText = closeBracketInText, closeInText >= 1 else { return nil }
            // Text is between linkRange.location+1 and linkRange.location+closeInText.
            let contentRange = NSRange(location: linkRange.location + 1, length: closeInText - 1)
            let content = nsSource.substring(with: contentRange)

            let before = nsSource.substring(to: linkRange.location)
            let after = nsSource.substring(from: linkRange.location + linkRange.length)
            let newSource = before + content + after
            let newSelection = NSRange(location: linkRange.location, length: (content as NSString).length)
            return MutationOutput(newSource: newSource, newSelection: newSelection)
        }

        // Insert: with selection, produce [sel]() with caret inside ().
        // Without selection, produce [](|) with caret inside [].
        if sel.length == 0 {
            let before = nsSource.substring(to: sel.location)
            let after = nsSource.substring(from: sel.location)
            let newSource = before + "[]()" + after
            let newSelection = NSRange(location: sel.location + 1, length: 0)  // caret inside []
            return MutationOutput(newSource: newSource, newSelection: newSelection)
        } else {
            let before = nsSource.substring(to: sel.location)
            let middle = nsSource.substring(with: sel)
            let after = nsSource.substring(from: sel.location + sel.length)
            let wrapped = "[" + middle + "]()"
            let newSource = before + wrapped + after
            // Caret inside the (): one past `[` + middle.length + 2 (for "](").
            let parenStart = sel.location + 1 + (middle as NSString).length + 2
            let newSelection = NSRange(location: parenStart, length: 0)
            return MutationOutput(newSource: newSource, newSelection: newSelection)
        }
    }
}
