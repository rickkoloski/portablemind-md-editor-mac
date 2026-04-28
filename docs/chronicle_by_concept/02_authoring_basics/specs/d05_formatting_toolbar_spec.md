# D5: Formatting Toolbar — Specification

**Status:** Complete
**Created:** 2026-04-22
**Completed:** 2026-04-22 — see `docs/current_work/stepwise_results/d05_formatting_toolbar_COMPLETE.md`
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D4 (mutation primitives + keyboard bindings + dispatcher)
**Traces to:** `docs/vision.md` Principle 1 (Level 1 audience — Word/Docs users need visible formatting controls); `docs/competitive-analysis.md` Typora anti-pattern (buried format menu); `docs/roadmap_ref.md` (D5 = toolbar, first user-visible feature); `docs/engineering-standards_ref.md` §2.1 (identifier-based queries).

---

## 1. Problem Statement

D1 through D4 produced a real markdown editor: native, sandbox-safe, live-rendered, with 13 formatting mutations reachable by keyboard. What's missing for our **priority-1 audience** is the single most important affordance from the competitive analysis: **a persistent, Word/Docs-style formatting toolbar** whose buttons invoke those same mutations.

The vision is unambiguous on this. From `docs/vision.md`:

> A persistent, Word/Docs-style formatting toolbar is not optional for our primary audience. It's the single most important affordance separating "tool a business user will adopt" from "tool a business user politely declines." The default must be: visible, labeled, familiar.

> Power users who want a cleaner surface should hide it via the **View menu → Show/Hide Toolbar** convention that Word, Docs, Pages, and virtually every desktop app already use.

D5 delivers that toolbar. It is **pure UI composition** — no new mutation logic, no new rendering logic. Every button dispatches the same `CommandDispatcher` identifier D4's keyboard bindings use.

---

## 2. Requirements

### Functional — buttons

The toolbar presents, in a single horizontal group, one button per D4 mutation:

| Control | Kind | SF Symbol (proposed) | Identifier | Dispatches |
|---|---|---|---|---|
| Bold | Button | `bold` | `toolbar.bold` | `mutation.bold` |
| Italic | Button | `italic` | `toolbar.italic` | `mutation.italic` |
| Inline code | Button | `chevron.left.forwardslash.chevron.right` | `toolbar.inlineCode` | `mutation.inlineCode` |
| Link | Button | `link` | `toolbar.link` | `mutation.link` |
| Heading level | Menu (dropdown) | `text.book.closed` | `toolbar.heading` | `mutation.body` / `mutation.heading1..6` |
| Bullet list | Button | `list.bullet` | `toolbar.bulletList` | `mutation.bulletList` |
| Numbered list | Button | `list.number` | `toolbar.numberedList` | `mutation.numberedList` |

The Heading dropdown menu contains 7 items: **Body**, **Heading 1**, **Heading 2**, …, **Heading 6**. Each dispatches the corresponding mutation identifier.

Buttons that are purely discoverability aids for an already-keyboard-accessible feature do *not* duplicate the chord. SwiftUI's `.help` modifier shows the chord in the tooltip (so `Bold (⌘B)` is discoverable without cluttering the button label).

### Functional — View menu

- [ ] Add a **View** menu with a single item: **Show Toolbar** / **Hide Toolbar** (labels swap based on current state), mapped to `Cmd+Opt+T`.
- [ ] Toggling the item shows or hides the toolbar for the active window.
- [ ] Toolbar-visible state persists across app launches via `UserDefaults` (key: `toolbarVisible`, default: `true`).

### Functional — toolbar-to-editor routing

- [ ] Toolbar buttons dispatch against the currently-focused editor in the active window.
- [ ] If no editor is focused (edge case — empty-window / between-windows state), buttons are disabled.
- [ ] Routing uses SwiftUI's `@FocusedValue` pattern — the `EditorContainer` publishes a reference to its active text view (or a dispatcher bound to it) via a `FocusedValueKey`; the toolbar reads that value.

### Functional — Open… button

The D2 Open… button remains in the same toolbar. Its accessibility identifier (`md-editor.toolbar.open-file`) is unchanged.

### Non-functional

- [ ] Standards §2.1 — every toolbar button has an `accessibilityIdentifier` from `AccessibilityIdentifiers`. No hardcoded identifier strings. The UITest suite is extended with at least one click-by-identifier test.
- [ ] Standards §2.3 — the toolbar does not inline chord checks. Its keyboard shortcuts for accelerator keys (e.g., Cmd+Opt+T for the View menu toggle) are declared through the existing `KeyboardBindings.all` table when applicable; SwiftUI's `.keyboardShortcut` modifier on menu items is acceptable where it routes through the menu system naturally.
- [ ] Standards §1.1 (sandbox-safe) — UI code only; no file I/O.
- [ ] Standards §1.2, §1.3 — unchanged.
- [ ] Standards §2.2 — no `.layoutManager` references introduced.
- [ ] Performance — adding the toolbar adds no measurable cost to typing or rendering. Subjective only.

---

## 3. Design

### Toolbar composition

Inside `MdEditorApp`'s `WindowGroup` scene, extend the existing `.toolbar { ... }` with a single `ToolbarItemGroup`:

```swift
.toolbar(id: "main") {
    ToolbarItem(id: "open", placement: .navigation) {
        Button("Open…", action: openFile)
            .accessibilityIdentifier(AccessibilityIdentifiers.openFileButton)
    }
    ToolbarItemGroup(id: "format", placement: .principal) {
        ToolbarButton(action: .bold)     // Label("Bold", systemImage: "bold"), .help("Bold (⌘B)")
        ToolbarButton(action: .italic)
        ToolbarButton(action: .inlineCode)
        ToolbarButton(action: .link)
        HeadingToolbarMenu()
        ToolbarButton(action: .bulletList)
        ToolbarButton(action: .numberedList)
    }
}
.toolbar(toolbarVisible ? .visible : .hidden, for: .windowToolbar)
```

Where:
- `ToolbarButton` is our thin wrapper component (one per action, takes a `ToolbarAction` enum value, composes `Button` + `Label` + `.help` + `.accessibilityIdentifier`)
- `ToolbarAction` is a new enum in `Sources/Toolbar/` enumerating the 7 direct-button actions (the Heading menu's items dispatch 7 separate mutation identifiers and live inside `HeadingToolbarMenu`)
- `toolbarVisible` comes from `AppSettings.shared.toolbarVisible` (published state)

### FocusedValue routing

```swift
// Sources/Toolbar/EditorDispatcherFocusedValue.swift
struct EditorDispatcherKey: FocusedValueKey {
    typealias Value = (command: String) -> Void
}
extension FocusedValues {
    var editorDispatch: EditorDispatcherKey.Value? {
        get { self[EditorDispatcherKey.self] }
        set { self[EditorDispatcherKey.self] = newValue }
    }
}
```

`EditorContainer`'s SwiftUI wrapper publishes a dispatch closure via `.focusedValue(\.editorDispatch) { command in ... }`. The closure captures the current `NSTextView` and calls `CommandDispatcher.shared.dispatch(identifier: command, in: textView)`.

`ToolbarButton` reads `@FocusedValue(\.editorDispatch) var dispatch` and calls `dispatch?(action.commandIdentifier)` when clicked. When no editor is focused, `dispatch` is nil → button is disabled.

### AppSettings (promote D2 stub)

```swift
// Sources/Settings/AppSettings.swift
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @AppStorage("toolbarVisible") var toolbarVisible: Bool = true
    private init() {}
}
```

`@AppStorage` wraps `UserDefaults` with SwiftUI bindings, so the toolbar's visibility tracks storage automatically.

### View menu

```swift
.commands {
    CommandMenu("View") {
        Toggle(AppSettings.shared.toolbarVisible ? "Hide Toolbar" : "Show Toolbar",
               isOn: $settings.toolbarVisible)
            .keyboardShortcut("t", modifiers: [.command, .option])
            .accessibilityIdentifier(AccessibilityIdentifiers.viewMenuToggleToolbar)
    }
}
```

The menu title label swaps between "Show Toolbar" and "Hide Toolbar" based on current state. The chord `Cmd+Opt+T` is declared here via SwiftUI's `.keyboardShortcut` rather than `KeyboardBindings` because it routes through the menu system natively (standard §2.3 allows menu-bound chords to use SwiftUI's native mechanism — the rule is about mutation chord dispatch in `LiveRenderTextView`, not menu accelerators).

### Module layout

```
Sources/Toolbar/                 (promoted from D2 stub README)
├── ToolbarAction.swift          7-case enum for direct buttons
├── ToolbarButton.swift          Generic button component reading FocusedValue
├── HeadingToolbarMenu.swift     Dropdown menu with Body + H1-H6 items
└── EditorDispatcherFocusedValue.swift  FocusedValueKey for toolbar → editor routing

Sources/Settings/                (promoted from D2 stub README)
└── AppSettings.swift            @AppStorage-backed settings singleton

Sources/App/MdEditorApp.swift    modified — expand .toolbar, add .commands
Sources/Editor/EditorContainer.swift  modified — publish focusedValue
Sources/Accessibility/AccessibilityIdentifiers.swift  extended with 8 new constants
UITests/MutationToolbarTests.swift    new — click Bold button by identifier, verify source
```

---

## 4. Success Criteria

- [ ] `xcodebuild build` clean, no new warnings.
- [ ] On launch, toolbar is visible with Open… on the left, format buttons in the center.
- [ ] Clicking each format button produces the same source change as its keyboard chord. Spot-check: Bold button ≡ Cmd+B; Numbered button ≡ Cmd+Shift+7.
- [ ] Heading dropdown opens a menu with 7 items (Body + H1–H6); each dispatches the corresponding mutation.
- [ ] View menu → "Hide Toolbar" hides the toolbar immediately. Menu label flips to "Show Toolbar". Clicking again restores.
- [ ] Hide state persists across app quit + relaunch.
- [ ] `Cmd+Opt+T` toggles the toolbar from keyboard.
- [ ] No toolbar button is enabled when no editor is focused (e.g., just-launched empty window with no file; window not yet focused).
- [ ] `rg --type swift 'accessibilityIdentifier' Sources/` shows at least 10 matches (was 2 post-D2; adding 7 direct buttons + Heading menu + View menu item).
- [ ] `rg --type swift 'layoutManager\\b' Sources/` still zero non-comment hits.
- [ ] `rg --type swift 'event\\.keyCode|event\\.charactersIgnoringModifiers' Sources/` still only inside `KeyboardBindings.swift`.
- [ ] UITest `MutationToolbarTests.testBoldButtonWrapsSelection` passes: launch, type "hi", select, click Bold button by identifier, assert source contains `**hi**`.
- [ ] Existing `MutationKeyboardTests` still passes — keyboard path unchanged.

---

## 4.5 Validation approach

Native Phase 1 exploratory plus the existing XCUITest infrastructure. Phases 2–4 still skipped per the spike pattern established in D1 — D5 is still pre-release feature development.

**Demo script:**

1. Launch app. Confirm toolbar visible with Open… + 7 format controls.
2. Type `hello`. Select it. Click **Bold** button. Verify bold renders and source contains `**hello**`.
3. Click **Italic**. Verify italic wrap.
4. Click **Inline code**. Verify backticks.
5. Click **Link**. Verify `[hello]()` with caret inside parens.
6. Select a fresh line. Open Heading menu → click **Heading 2**. Verify H2.
7. Same line. Heading menu → **Body**. Verify strips heading.
8. Select 3 lines. Click **Bullet**. Verify bulleted.
9. Same selection. Click **Numbered**. Verify numbered.
10. Put caret inside a fenced code block. Click **Bold**. Verify no change (code-block safety unchanged from D4).
11. View menu → **Hide Toolbar**. Verify toolbar disappears. Menu label flips.
12. Quit app. Relaunch. Verify toolbar is still hidden (persistence).
13. View menu → **Show Toolbar**. Verify toolbar reappears. Menu label flips.
14. `Cmd+Opt+T` from keyboard. Verify toggle via shortcut.

Evidence: screen recording, transcript, xcodebuild build + test logs.

**Automated test:**
- New `MutationToolbarTests.testBoldButtonWrapsSelection` — launches, types text, selects, queries the Bold button via `accessibilityIdentifier`, calls `.click()`, asserts source contains `**text**`.

---

## 5. Out of Scope

- **Icon artwork beyond SF Symbols** — we use SwiftUI's standard SF Symbol names. Custom brand iconography is a later visual-design deliverable.
- **Toolbar customization by users** (drag to reorder, add/remove buttons). SwiftUI's `.customizationBehavior` can be added later; for D5 the layout is fixed.
- **Multiple toolbars / multiple window support** — D5 assumes one main window per scene.
- **Format menu** — the File / Edit / View menu set is already native; a dedicated "Format" menu duplicating the toolbar actions is a usability nicety we can add later.
- **Disable button when the target is invalid** (e.g., gray out Bold when inside code block) — the spec keeps D5 simple: buttons are enabled whenever focus is on an editor; mutations are still safely no-op'd inside code blocks via D4's existing `CodeBlockSafety` check.
- **Visual state that reflects current formatting** (e.g., Bold button highlighted when selection is already bold) — require AST lookup on every selection change; real UX win but non-trivial. Deferred to a later polish deliverable.
- **Internationalization of keyboard chords** — finding #4 from D4 still stands. D5 inherits the US-keyboard-specific chord table.

---

## 6. Open Questions

1. **SF Symbol for inline code.** SF Symbols has several candidates: `chevron.left.forwardslash.chevron.right`, `curlybraces`, `terminal`, `text.append`. Recommendation: **`chevron.left.forwardslash.chevron.right`** — it's the most recognizable `</>` visual and is the standard "inline code" choice in Apple's SF Symbols library on macOS 14+.
2. **SF Symbol for Heading dropdown.** `text.book.closed` or `textformat`? Recommendation: **`textformat`** — it's the generic "paragraph style" symbol and matches Word/Docs' common UX.
3. **Toolbar placement.** SwiftUI's `.principal` centers the group; `.automatic` lets the system place it. Recommendation: **`.automatic`** — yields the most native feel; re-evaluate if it looks cramped next to Open….
4. **Should the Heading menu display the current heading level as its label?** e.g., "Heading 1" when caret is on an H1. Requires AST lookup on every selection change (same cost as "current format" button state). Recommendation: **no for D5** — the menu label stays "Heading"; dynamic label is a polish deliverable alongside button-state highlighting.
5. **Disable the toolbar when no document is open?** Currently the app opens an empty untitled buffer, and buttons work on it. Recommendation: **leave enabled**, since the untitled buffer IS a valid editing target post-D4 finding #1 fix.

Default decisions (1 = `chevron.left.forwardslash.chevron.right`, 2 = `textformat`, 3 = `.automatic`, 4 = no, 5 = leave enabled) proceed unless you say otherwise.

---

## 7. Definition of Done

D5 is Complete when:
- All Success Criteria items check.
- Demo script executed; transcript and screen recording in `evidence/d05/`.
- New UITest passes via `xcodebuild test`.
- Completion record at `docs/current_work/stepwise_results/d05_formatting_toolbar_COMPLETE.md` with per-step pass/fail and any new findings.
- `docs/engineering-standards_ref.md` reviewed; any new rules surfaced during D5 added.
- `docs/roadmap_ref.md` updated to mark D5 complete.
- `spikes/d01_textkit2/` remains frozen (no changes).
