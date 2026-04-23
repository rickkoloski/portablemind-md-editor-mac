import AppKit
import Foundation

/// One attribute assignment: a range in the full text buffer and the
/// attributes to apply to that range. The renderer produces a list of
/// these; the text view applies them inside a single begin/endEditing
/// block.
struct AttributeAssignment {
    let range: NSRange
    let attributes: [NSAttributedString.Key: Any]
}

/// Classification of a range for the cursor-on-line reveal. Bold and
/// italic delimiters want to toggle visibility; heading markers want
/// the same. The tracker uses this to decide which previously-collapsed
/// ranges to reveal when the caret enters a line.
enum SyntaxRole {
    case delimiter           // **, *, `, #, etc. — hide when caret off-line
    case rendered            // the content inside delimiters
}

/// A span tagged with its role, produced alongside AttributeAssignments.
/// The tracker consults these to know what to toggle.
struct SyntaxSpan {
    let range: NSRange
    let role: SyntaxRole
}

/// The base typography used for rendering. Kept central so heading /
/// code / body fonts all derive from one size.
struct SpikeTypography {
    static let baseFontSize: CGFloat = 14
    static let baseFont: NSFont = .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    static let headingBaseSize: CGFloat = 22

    static func headingFont(level: Int) -> NSFont {
        // H1 largest, H6 closer to body size.
        let size = max(baseFontSize + 1, headingBaseSize - CGFloat(level - 1) * 2)
        return .systemFont(ofSize: size, weight: .bold)
    }

    static let boldFont: NSFont = .monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
    static let italicFont: NSFont = {
        let desc = NSFontDescriptor(name: "Menlo-Italic", size: baseFontSize)
        return NSFont(descriptor: desc, size: baseFontSize) ?? .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    }()
    static let codeFont: NSFont = .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    static let codeBackground: NSColor = NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .labelColor) ?? .textBackgroundColor
    static let linkColor: NSColor = .linkColor

    /// The attribute key we use to mark collapsible delimiter ranges.
    /// We attach this so CursorLineTracker can find and re-render them.
    static let syntaxRoleKey = NSAttributedString.Key("SpikeSyntaxRole")
}
