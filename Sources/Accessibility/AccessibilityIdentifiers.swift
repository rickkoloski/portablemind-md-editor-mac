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

    // View menu (D10)
    static let viewMenuToggleLineNumbers = "md-editor.menu.view.toggle-line-numbers"

    // Workspace — sidebar, tree, tabs, empty state (D6)
    static let folderTree = "md-editor.sidebar.folder-tree"
    static let sidebarToggleButton = "md-editor.sidebar.toggle"
    static let tabBar = "md-editor.tabs.bar"
    static let emptyEditor = "md-editor.empty-editor"
    static let openFolderMenuItem = "md-editor.menu.file.open-folder"
    static let viewMenuToggleSidebar = "md-editor.menu.view.toggle-sidebar"

    // File menu — Save / Save As (D14)
    static let fileMenuSave = "md-editor.menu.file.save"
    static let fileMenuSaveAs = "md-editor.menu.file.save-as"

    /// Per-row and per-tab identifiers use the connector-qualified node
    /// id (for tree rows) or document UUID (for tabs) so tests can
    /// target a specific row or tab reliably.
    static func folderTreeRow(id: String) -> String {
        "md-editor.sidebar.folder-tree.row:\(id)"
    }

    static func tabButton(documentID: UUID) -> String {
        "md-editor.tabs.tab:\(documentID.uuidString)"
    }

    static func tabCloseButton(documentID: UUID) -> String {
        "md-editor.tabs.close:\(documentID.uuidString)"
    }
}
