import Foundation

/// One case per direct toolbar button. The Heading dropdown lives in
/// `HeadingToolbarMenu` because it emits seven separate mutation
/// commands and has its own layout.
enum ToolbarAction: CaseIterable {
    case bold, italic, inlineCode, link, bulletList, numberedList

    var commandIdentifier: String {
        switch self {
        case .bold: return BoldMutation.identifier
        case .italic: return ItalicMutation.identifier
        case .inlineCode: return InlineCodeMutation.identifier
        case .link: return LinkMutation.identifier
        case .bulletList: return BulletListMutation.identifier
        case .numberedList: return NumberedListMutation.identifier
        }
    }

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .inlineCode: return "Inline Code"
        case .link: return "Link"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        }
    }

    /// Tooltip text; shows the keyboard chord alongside the action
    /// name for discoverability per vision Principle 1.
    var helpText: String {
        switch self {
        case .bold: return "Bold (⌘B)"
        case .italic: return "Italic (⌘I)"
        case .inlineCode: return "Inline Code (⌘E)"
        case .link: return "Link (⌘K)"
        case .bulletList: return "Bullet List (⇧⌘8)"
        case .numberedList: return "Numbered List (⇧⌘7)"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .bold: return AccessibilityIdentifiers.toolbarBold
        case .italic: return AccessibilityIdentifiers.toolbarItalic
        case .inlineCode: return AccessibilityIdentifiers.toolbarInlineCode
        case .link: return AccessibilityIdentifiers.toolbarLink
        case .bulletList: return AccessibilityIdentifiers.toolbarBulletList
        case .numberedList: return AccessibilityIdentifiers.toolbarNumberedList
        }
    }
}
