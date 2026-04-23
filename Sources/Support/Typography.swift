import AppKit
import Foundation

/// Typography for the MdEditor content area. Kept central so heading,
/// code, and body fonts derive from one size.
///
/// D2 note: body font stays monospace per docs/current_work/specs/
/// d02_project_scaffolding_spec.md Open Question 5. The intentional
/// switch to a proportional body font is a dedicated later deliverable
/// because it alters the product's feel for the priority-1 audience.
struct Typography {
    static let baseFontSize: CGFloat = 14
    static let baseFont: NSFont = .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
    static let headingBaseSize: CGFloat = 22

    static func headingFont(level: Int) -> NSFont {
        let size = max(baseFontSize + 1, headingBaseSize - CGFloat(level - 1) * 2)
        return .systemFont(ofSize: size, weight: .bold)
    }

    static let boldFont: NSFont = .monospacedSystemFont(ofSize: baseFontSize, weight: .bold)

    static let italicFont: NSFont = {
        let desc = NSFontDescriptor(name: "Menlo-Italic", size: baseFontSize)
        return NSFont(descriptor: desc, size: baseFontSize) ?? baseFont
    }()

    static let codeFont: NSFont = .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)

    static let codeBackground: NSColor = NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .labelColor) ?? .textBackgroundColor

    static let linkColor: NSColor = .linkColor

    /// Attribute key used to tag delimiter ranges so CursorLineTracker
    /// can find and collapse/reveal them without re-parsing.
    static let syntaxRoleKey = NSAttributedString.Key("MdEditorSyntaxRole")

    /// Attribute key used to attach a "reveal scope" to content whose
    /// delimiters live on different lines from the content (most
    /// notably fenced code blocks). When the caret enters any character
    /// carrying this attribute, the tracker treats the attached NSRange
    /// as the current-line range — so fences on neighboring lines
    /// reveal together with the block content.
    ///
    /// Value is an `NSValue` wrapping the block's full NSRange.
    static let revealScopeKey = NSAttributedString.Key("MdEditorRevealScope")
}
