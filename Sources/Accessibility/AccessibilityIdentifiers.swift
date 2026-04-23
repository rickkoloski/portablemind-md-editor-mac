import Foundation

/// Central registry of accessibility identifiers for every interactive
/// NSView in the app. Required by `docs/engineering-standards_ref.md`
/// §2.1 — never hardcode identifier strings at the usage site.
///
/// Add one constant per interactive view as it lands.
enum AccessibilityIdentifiers {
    static let mainWindow = "md-editor.main-window"
    static let mainEditor = "md-editor.main-editor"
    static let openFileButton = "md-editor.toolbar.open-file"
}
