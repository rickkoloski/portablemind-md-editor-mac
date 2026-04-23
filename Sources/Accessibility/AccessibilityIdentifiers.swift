import Foundation

/// Central registry of accessibility identifiers for every interactive
/// NSView in the app. Required by `docs/engineering-standards_ref.md`
/// §2.1 — never hardcode identifier strings at the usage site.
///
/// Add one constant per interactive view as it lands.
enum AccessibilityIdentifiers {
    // Core views (D2)
    static let mainWindow = "md-editor.main-window"
    static let mainEditor = "md-editor.main-editor"
    static let openFileButton = "md-editor.toolbar.open-file"

    // Formatting toolbar direct buttons (D5)
    static let toolbarBold = "md-editor.toolbar.bold"
    static let toolbarItalic = "md-editor.toolbar.italic"
    static let toolbarInlineCode = "md-editor.toolbar.inline-code"
    static let toolbarLink = "md-editor.toolbar.link"
    static let toolbarHeadingMenu = "md-editor.toolbar.heading-menu"
    static let toolbarBulletList = "md-editor.toolbar.bullet-list"
    static let toolbarNumberedList = "md-editor.toolbar.numbered-list"

    // Heading dropdown menu items (D5)
    static let headingMenuBody = "md-editor.toolbar.heading.body"
    static let headingMenuH1 = "md-editor.toolbar.heading.h1"
    static let headingMenuH2 = "md-editor.toolbar.heading.h2"
    static let headingMenuH3 = "md-editor.toolbar.heading.h3"
    static let headingMenuH4 = "md-editor.toolbar.heading.h4"
    static let headingMenuH5 = "md-editor.toolbar.heading.h5"
    static let headingMenuH6 = "md-editor.toolbar.heading.h6"

    // View menu (D5)
    static let viewMenuToggleToolbar = "md-editor.menu.view.toggle-toolbar"
}
