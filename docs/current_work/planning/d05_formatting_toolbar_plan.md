# D5: Formatting Toolbar — Implementation Instructions

**Spec:** `d05_formatting_toolbar_spec.md`
**Created:** 2026-04-22

---

## Overview

Wire every D4 mutation to a visible SwiftUI toolbar button. Add a View → Show/Hide Toolbar menu item with UserDefaults persistence. Use `@FocusedValue` to route clicks from the global toolbar to the focused editor's dispatcher.

Promotes `Sources/Toolbar/` and `Sources/Settings/` from D2 stubs. No new mutation logic.

---

## Prerequisites

- [ ] D4 Complete; all 13 mutations work via keyboard.
- [ ] Open Questions from the spec accepted or adjusted (defaults listed in §6).
- [ ] `DEVELOPER_DIR` sourced in pane 2.

---

## Implementation Steps

### Step 1 — Settings module (promote stub)

**Files:** delete `Sources/Settings/README.md`; create `Sources/Settings/AppSettings.swift`

```swift
import SwiftUI

/// Persistent app preferences. UserDefaults-backed via @AppStorage so
/// toolbar visibility, future preference keys, etc. bind directly to
/// SwiftUI views.
///
/// Storage per engineering-standards `docs/stack-alternatives.md`
/// § "Explicitly not using" — no Core Data / SwiftData.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Backed by UserDefaults key "toolbarVisible". Default true per
    /// vision: the toolbar is on by default for the priority-1 audience.
    @AppStorage("toolbarVisible") var toolbarVisible: Bool = true

    private init() {}
}
```

### Step 2 — Accessibility identifiers

**File:** `Sources/Accessibility/AccessibilityIdentifiers.swift` (extend)

Add constants for every new interactive control:

```swift
// Toolbar format buttons
static let toolbarBold = "md-editor.toolbar.bold"
static let toolbarItalic = "md-editor.toolbar.italic"
static let toolbarInlineCode = "md-editor.toolbar.inline-code"
static let toolbarLink = "md-editor.toolbar.link"
static let toolbarHeadingMenu = "md-editor.toolbar.heading-menu"
static let toolbarBulletList = "md-editor.toolbar.bullet-list"
static let toolbarNumberedList = "md-editor.toolbar.numbered-list"

// Heading-menu items (one per level)
static let headingMenuBody = "md-editor.toolbar.heading.body"
static let headingMenuH1 = "md-editor.toolbar.heading.h1"
static let headingMenuH2 = "md-editor.toolbar.heading.h2"
static let headingMenuH3 = "md-editor.toolbar.heading.h3"
static let headingMenuH4 = "md-editor.toolbar.heading.h4"
static let headingMenuH5 = "md-editor.toolbar.heading.h5"
static let headingMenuH6 = "md-editor.toolbar.heading.h6"

// View menu
static let viewMenuToggleToolbar = "md-editor.menu.view.toggle-toolbar"
```

### Step 3 — FocusedValue routing

**File:** `Sources/Toolbar/EditorDispatcherFocusedValue.swift`

```swift
import SwiftUI

/// A dispatch closure the active editor publishes so any toolbar or
/// menu item in the scene can invoke a command against it. nil when no
/// editor is focused.
struct EditorDispatcherKey: FocusedValueKey {
    typealias Value = (String) -> Void
}

extension FocusedValues {
    var editorDispatch: EditorDispatcherKey.Value? {
        get { self[EditorDispatcherKey.self] }
        set { self[EditorDispatcherKey.self] = newValue }
    }
}
```

### Step 4 — EditorContainer publishes the dispatcher

**File:** `Sources/Editor/EditorContainer.swift` (modify)

SwiftUI bridging views can't set `.focusedValue` directly on an `NSViewRepresentable`. Wrap it in a `ZStack` or add a modifier on the caller side. Simpler: expose a `dispatch` closure on the Coordinator, have `MdEditorApp` capture the active text view via a shared app-level registry.

Pragmatic D5 implementation — use a minimal `EditorDispatcherRegistry` singleton that publishes the current dispatcher:

```swift
// Sources/Toolbar/EditorDispatcherRegistry.swift
import AppKit

@MainActor
final class EditorDispatcherRegistry: ObservableObject {
    static let shared = EditorDispatcherRegistry()
    @Published private(set) var activeDispatch: ((String) -> Void)?
    func register(for textView: NSTextView) {
        activeDispatch = { [weak textView] identifier in
            guard let textView else { return }
            _ = CommandDispatcher.shared.dispatch(identifier: identifier, in: textView)
        }
    }
    func deregister() { activeDispatch = nil }
    private init() {}
}
```

In `EditorContainer.makeNSView`, after creating the text view:

```swift
EditorDispatcherRegistry.shared.register(for: textView)
```

Re-register on each `updateNSView` call as a safety net. Future refactor can migrate to proper `@FocusedValue` once we have multiple windows.

(We keep the `EditorDispatcherFocusedValue.swift` file from Step 3 because the eventual path is `@FocusedValue`; this interim registry is an easy drop-in replacement later.)

### Step 5 — ToolbarAction enum

**File:** `Sources/Toolbar/ToolbarAction.swift`

```swift
import SwiftUI

/// One case per direct toolbar button (not the Heading dropdown, which
/// emits seven separate commands and lives in HeadingToolbarMenu).
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

    /// Label for the tooltip; shows the chord for discoverability.
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
```

### Step 6 — ToolbarButton component

**File:** `Sources/Toolbar/ToolbarButton.swift`

```swift
import SwiftUI

struct ToolbarButton: View {
    let action: ToolbarAction
    @ObservedObject private var registry = EditorDispatcherRegistry.shared

    var body: some View {
        Button(action: invoke) {
            Label(action.title, systemImage: action.systemImage)
                .labelStyle(.iconOnly)
        }
        .help(action.helpText)
        .disabled(registry.activeDispatch == nil)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }

    private func invoke() {
        registry.activeDispatch?(action.commandIdentifier)
    }
}
```

### Step 7 — HeadingToolbarMenu component

**File:** `Sources/Toolbar/HeadingToolbarMenu.swift`

```swift
import SwiftUI

struct HeadingToolbarMenu: View {
    @ObservedObject private var registry = EditorDispatcherRegistry.shared

    var body: some View {
        Menu {
            menuItem("Body", id: AccessibilityIdentifiers.headingMenuBody, command: BodyMutation.identifier)
            menuItem("Heading 1", id: AccessibilityIdentifiers.headingMenuH1, command: Heading1Mutation.identifier)
            menuItem("Heading 2", id: AccessibilityIdentifiers.headingMenuH2, command: Heading2Mutation.identifier)
            menuItem("Heading 3", id: AccessibilityIdentifiers.headingMenuH3, command: Heading3Mutation.identifier)
            menuItem("Heading 4", id: AccessibilityIdentifiers.headingMenuH4, command: Heading4Mutation.identifier)
            menuItem("Heading 5", id: AccessibilityIdentifiers.headingMenuH5, command: Heading5Mutation.identifier)
            menuItem("Heading 6", id: AccessibilityIdentifiers.headingMenuH6, command: Heading6Mutation.identifier)
        } label: {
            Label("Heading", systemImage: "textformat")
                .labelStyle(.iconOnly)
        }
        .help("Heading")
        .disabled(registry.activeDispatch == nil)
        .accessibilityIdentifier(AccessibilityIdentifiers.toolbarHeadingMenu)
    }

    @ViewBuilder
    private func menuItem(_ title: String, id: String, command: String) -> some View {
        Button(title) {
            registry.activeDispatch?(command)
        }
        .accessibilityIdentifier(id)
    }
}
```

### Step 8 — Wire toolbar + View menu into the scene

**File:** `Sources/App/MdEditorApp.swift` (modify)

```swift
@main
struct MdEditorApp: App {
    @State private var fileURL: URL?
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            EditorContainer(fileURL: $fileURL)
                .frame(minWidth: 700, minHeight: 500)
                .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
                .toolbar(id: "main") {
                    ToolbarItem(id: "open", placement: .navigation) {
                        Button(action: openFile) { Text("Open…") }
                            .keyboardShortcut("o", modifiers: .command)
                            .accessibilityIdentifier(AccessibilityIdentifiers.openFileButton)
                    }
                    ToolbarItemGroup(id: "format", placement: .automatic) {
                        ToolbarButton(action: .bold)
                        ToolbarButton(action: .italic)
                        ToolbarButton(action: .inlineCode)
                        ToolbarButton(action: .link)
                        HeadingToolbarMenu()
                        ToolbarButton(action: .bulletList)
                        ToolbarButton(action: .numberedList)
                    }
                }
                .toolbar(settings.toolbarVisible ? .visible : .hidden, for: .windowToolbar)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("View") {
                Button(settings.toolbarVisible ? "Hide Toolbar" : "Show Toolbar") {
                    settings.toolbarVisible.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .accessibilityIdentifier(AccessibilityIdentifiers.viewMenuToggleToolbar)
            }
        }
    }

    private func openFile() { ... /* unchanged */ }
}
```

### Step 9 — UITest

**File:** `UITests/MutationToolbarTests.swift` (new)

```swift
import XCTest

final class MutationToolbarTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testBoldButtonWrapsSelection() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.descendants(matching: .any)["md-editor.main-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        editor.click()
        editor.typeText("hi")
        editor.typeKey("a", modifierFlags: .command)  // select all

        let boldButton = app.descendants(matching: .any)["md-editor.toolbar.bold"]
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5), "Bold toolbar button not found by identifier")
        boldButton.click()

        let text = (editor.value as? String) ?? ""
        XCTAssertTrue(text.contains("**hi**"),
                      "expected source to contain **hi** after Bold click; got: \(text)")
    }
}
```

### Step 10 — Regenerate, build, launch

```bash
cd /Users/richardkoloski/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
    -configuration Debug -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Then run the automated test:

```bash
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
    -destination 'platform=macOS' -derivedDataPath ./.build-xcode test
```

---

## Testing

Manual demo script (spec §4.5) in `evidence/d05/transcript.md` with screen recording.

Automated: `LaunchSmokeTests`, `MutationKeyboardTests`, `MutationToolbarTests` all green via `xcodebuild test`.

### Verification Checklist

- [ ] Sources/Toolbar/ contains: ToolbarAction.swift, ToolbarButton.swift, HeadingToolbarMenu.swift, EditorDispatcherRegistry.swift, EditorDispatcherFocusedValue.swift (stub for future migration)
- [ ] Sources/Settings/ contains: AppSettings.swift (README.md removed)
- [ ] AccessibilityIdentifiers.swift has all new constants (12+ new entries)
- [ ] `rg 'accessibilityIdentifier(' Sources/` shows ≥10 usages
- [ ] `rg 'layoutManager\\b' Sources/` → only comments
- [ ] `rg 'event\\.keyCode|event\\.charactersIgnoringModifiers' Sources/` → only KeyboardBindings.swift
- [ ] Demo script complete; evidence files checked in
- [ ] MutationToolbarTests passes
- [ ] Existing tests (LaunchSmokeTests, MutationKeyboardTests) still pass
- [ ] COMPLETE doc written; roadmap updated; spec flipped to Complete

---

## Notes

- **`@FocusedValue` vs. registry singleton:** `@FocusedValue` is the proper SwiftUI-idiomatic path for command routing, but wiring it cleanly through an `NSViewRepresentable` requires either a SwiftUI wrapper view that observes focus state or a FocusState relay. The registry singleton in Step 4 is a pragmatic shortcut that works for the single-window case we have. When we add multi-window in a later deliverable, migrate to `@FocusedValue` in one focused refactor.
- **Toolbar placement:** `placement: .automatic` gives SwiftUI discretion. If it looks cramped next to Open…, try `.primaryAction` or `.principal` in Xcode preview.
- **Disable-on-no-editor:** `registry.activeDispatch == nil` binds through `@ObservedObject`, so SwiftUI re-evaluates the disabled state when focus changes.
- **Commit cadence:** one commit after Step 3 (Settings + Identifiers), one after Step 7 (all Toolbar Swift compiles), one after Step 9 (wired + UITest added), one after Step 10 (green build + test). Four commits total for D5.
- **Don't be clever about button state** (highlight when already bold). That's a later polish deliverable — covered as spec OQ #4.
