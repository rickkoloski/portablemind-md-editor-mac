import Foundation
import Markdown

/// A mutation primitive transforms markdown source in response to a
/// user command (keyboard chord or — later — toolbar button). Pure
/// function of input → optional output. nil means "no-op" (typically
/// code-block safety triggered; dispatcher skips the text change).
protocol MutationPrimitive {
    static var identifier: String { get }
    static func apply(to input: MutationInput) -> MutationOutput?
}

struct MutationInput {
    let source: String
    let selection: NSRange
    let document: Document
    let nsSource: NSString
    let converter: SourceLocationConverter
}

struct MutationOutput {
    let newSource: String
    let newSelection: NSRange
}
