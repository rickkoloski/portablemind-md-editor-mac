import Foundation

/// Where the editor should place the caret (and future: selection)
/// when a file is opened or re-focused via an external command.
///
/// D9 ships only the `.caret` variant. `.selection` reserved for the
/// D10+ text-selection-on-open work tracked in Harmoniq task #1368.
enum EditorFocusTarget: Equatable {
    case caret(line: Int, column: Int)
}
