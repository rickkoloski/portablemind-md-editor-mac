import AppKit
import Markdown

/// Orchestrates: keyboard chord → mutation primitive → text mutation
/// with undo integration. Single source of command dispatch; the only
/// callers are `LiveRenderTextView.keyDown` and (future) toolbar
/// button actions.
final class CommandDispatcher {
    static let shared = CommandDispatcher()
    private init() {}

    /// Execute the command identified by `identifier` against `textView`'s
    /// current state. Returns true if the event was consumed (so
    /// keyDown knows not to forward), false if the identifier is unknown.
    @discardableResult
    func dispatch(identifier: String, in textView: NSTextView) -> Bool {
        guard let primitive = MutationResolver.primitive(for: identifier) else { return false }
        guard let storage = textView.textStorage else { return false }

        let selection = textView.selectedRange()

        // Code-block safety — §3 Open Question 5: probe start-of-selection.
        if CodeBlockSafety.isInsideCodeBlock(selectionStart: selection.location, in: storage) {
            return true  // consumed as no-op
        }

        let source = storage.string
        let nsSource = source as NSString
        let converter = SourceLocationConverter(source: source)
        let document = Document(parsing: source)

        let input = MutationInput(
            source: source,
            selection: selection,
            document: document,
            nsSource: nsSource,
            converter: converter
        )

        guard let output = primitive.apply(to: input) else {
            // Primitive decided no-op (e.g., wrap with empty selection).
            return true
        }

        // Apply as a single undo group via the shouldChange/didChange
        // lifecycle so NSUndoManager sees it as one step.
        let fullRange = NSRange(location: 0, length: storage.length)
        if textView.shouldChangeText(in: fullRange, replacementString: output.newSource) {
            storage.replaceCharacters(in: fullRange, with: output.newSource)
            textView.didChangeText()
        }
        let clampedLocation = min(output.newSelection.location, (output.newSource as NSString).length)
        let clampedLength = min(output.newSelection.length, (output.newSource as NSString).length - clampedLocation)
        textView.setSelectedRange(NSRange(location: clampedLocation, length: max(0, clampedLength)))
        return true
    }
}
