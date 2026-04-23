# D5: Formatting Toolbar — Completion Record

**Status:** Complete
**Created:** 2026-04-22
**Completed:** 2026-04-22
**Spec:** `docs/current_work/specs/d05_formatting_toolbar_spec.md`
**Plan:** `docs/current_work/planning/d05_formatting_toolbar_plan.md`

---

## 1. TL;DR

**D5 is Complete.** The formatting toolbar is live. Every D4 mutation is reachable via a visible, Word/Docs-familiar button; the View menu hosts a **Show/Hide Toolbar** toggle (Cmd+Opt+T) with UserDefaults persistence across launches. The priority-1 audience (Word/Docs users) now has the single most important affordance the competitive analysis called out.

All 14 demo steps verified by CD including the hide-across-relaunch persistence test (driven from pane 2). `xcodebuild test` runs all three UITest suites green (`LaunchSmokeTests`, `MutationKeyboardTests`, `MutationToolbarTests`).

Two findings surfaced during validation — both AppKit/SwiftUI interoperation quirks — fixed in-deliverable.

---

## 2. Spec success criteria — pass/fail

| Item | Result |
|---|---|
| `xcodebuild build` clean, no new warnings | ✅ |
| Toolbar visible on launch with Open… + 7 format controls | ✅ |
| Bold button ≡ Cmd+B (source change identical) | ✅ |
| Italic, InlineCode, Link buttons work | ✅ |
| Heading dropdown shows Body + H1–H6; each dispatches the corresponding mutation | ✅ |
| Bullet, Numbered list buttons work | ✅ |
| Code-block safety (click Bold inside code block → no change) | ✅ inherits from D4 |
| View menu → Hide Toolbar hides toolbar row; menu label flips to "Show Toolbar" | ✅ |
| Hide state persists across app quit + relaunch | ✅ (verified via kill+relaunch from pane 2) |
| Cmd+Opt+T toggles the toolbar from keyboard | ✅ |
| No toolbar button fires when no editor is focused | ✅ (registry.activeDispatch binding disables buttons) |
| `rg 'accessibilityIdentifier' Sources/` ≥ 10 matches | ✅ (14+ usages across Sources/ + test target) |
| `rg 'layoutManager\\b' Sources/` → zero non-comment hits | ✅ |
| `rg 'event\\.keyCode|event\\.charactersIgnoringModifiers' Sources/` → only KeyboardBindings.swift | ✅ |
| `MutationToolbarTests` passes via `xcodebuild test` | ✅ |
| `LaunchSmokeTests` + `MutationKeyboardTests` still pass | ✅ |

---

## 3. Findings (during validation; fixed in-deliverable)

### Finding #1 — `CommandMenu("View")` creates a DUPLICATE View menu

The first validation pass showed two "View" menus in the menu bar. `CommandMenu(String)` in SwiftUI adds a new top-level menu with the given name, even if a menu by that name already exists. macOS's default windowed-app menu bar already has a View menu with the standard toolbar-related items.

**Resolution:** Replaced `CommandMenu("View") { … }` with `CommandGroup(replacing: .toolbar) { … }`. `.toolbar` is the placement inside the existing View menu where macOS puts its default "Show Toolbar" / "Customize Toolbar" items. Replacing that group slots our toggle into the existing menu (rather than creating a second one) and removes the default items we'd otherwise duplicate.

**Severity:** Moderate (user-visible menu-bar clutter; easy to fix once the API distinction is known).

### Finding #2 — `.toolbar(.hidden, for: .windowToolbar)` hides the title bar too

SwiftUI's scene-level `.toolbar(visibility, for: .windowToolbar)` targets the entire toolbar region, which on macOS includes the title bar (and thus the red/yellow/green traffic lights). Even with `windowToolbarStyle(.expanded)` putting title and toolbar in separate rows visually, the visibility modifier still hid both. The user could not hide just the toolbar while keeping the chrome.

**Resolution:** Introduced `Sources/App/WindowAccessor.swift` — a thin `NSViewRepresentable` that passes the underlying `NSWindow` to a closure on every SwiftUI update. Used `.background(WindowAccessor { window in window.toolbar?.isVisible = settings.toolbarVisible })` to drive the toolbar's visibility via AppKit's native `NSWindow.toolbar.isVisible`, which distinguishes "hide the toolbar row" from "hide the whole toolbar region."

**Severity:** Moderate (broke the intended "hide just the toolbar" UX; fixed by dropping to AppKit where SwiftUI's API is too coarse).

**General pattern reinforced:** SwiftUI-first, AppKit-when-needed. The WindowAccessor is now a reusable bridge we'll reach for again whenever SwiftUI's scene modifiers don't expose the AppKit semantic we need.

### Finding #3 — SwiftUI Button-wrapping-Label produces duplicate-identifier AX nodes

First UITest run failed with `Failed to click "md-editor.toolbar.bold" Any: Multiple matching elements found`. The accessibility tree showed a Button with identifier `md-editor.toolbar.bold` containing an inner Button with the same identifier — SwiftUI's `Button { Label(…) { … } }` produces nested AX nodes, and the identifier propagates to both. An identifier-based query returns *all* matches; `.click()` on an ambiguous query fails.

**Resolution:** Resolve the query with `.firstMatch` so the test picks a single element:

```swift
let boldButton = app.descendants(matching: .any)["md-editor.toolbar.bold"].firstMatch
```

This is still identifier-based and still compliant with engineering-standards §2.1 — the discipline is about not using element-type shortcuts (`.buttons[id]`, `.textViews.firstMatch`), not about avoiding `.firstMatch`. `.firstMatch` is the idiomatic resolver for identifier queries that hit multiple elements.

**D2+D5 compounding lesson:** identifier queries must be written as `descendants(matching:.any)["id"].firstMatch` on SwiftUI-hosted views. Updating engineering-standards §2.1 to cite the exact query shape so future sessions don't re-hit this.

**Severity:** Low (test-only; easy resolver).

---

## 4. APIs that worked

- **`EditorDispatcherRegistry` singleton + `@ObservedObject`.** Clean single-window path for wiring global toolbar buttons to the active text view's dispatcher. Disabling-when-nil binds through `@ObservedObject`, so buttons disable/enable reactively without extra state.
- **`@AppStorage` for `toolbarVisible`.** Zero-code persistence — `@AppStorage("toolbarVisible")` binds the property to `UserDefaults` directly; toggling the toggle persists automatically.
- **`.windowToolbarStyle(.expanded)`** for the two-row title + toolbar layout Rick asked for.
- **`.help(…)`** modifier on toolbar buttons shows the keyboard chord in tooltip (e.g., `Bold (⌘B)`) — discoverability without button-label clutter.
- **SF Symbols** for button icons — every action had a native symbol (`bold`, `italic`, `link`, `list.bullet`, `list.number`, `chevron.left.forwardslash.chevron.right` for inline code, `textformat` for the Heading menu). No custom glyphs needed at D5.

## 5. APIs that were traps

- **`CommandMenu("View")` vs `CommandGroup(replacing: .toolbar)`** — the former creates a duplicate; the latter merges with the existing menu. Documented in finding #1.
- **`.toolbar(visibility, for: .windowToolbar)`** hides title bar too; not visibility-for-toolbar-row only. Documented in finding #2.
- **`.toolbar(id:)` customization API** — tried first in line with the spec, caused compile errors (`extra argument 'id'` + missing `content` generic). Dropped to the non-customizable `.toolbar { }` form. Future toolbar-customization (e.g., drag to reorder) will need the customizable overload — deferred, out of scope for D5.

---

## 6. UITest outcome

**Passed.** `xcodebuild test` ran all three suites:

- `LaunchSmokeTests.testAppLaunchesAndMainEditorIsAccessible` — D2 smoke
- `MutationKeyboardTests.testBoldMutationWrapsSelection` — D4 keyboard path
- `MutationToolbarTests.testBoldButtonWrapsSelection` — D5 new test; launches the app, types "hi", Cmd+A, finds the Bold button by `md-editor.toolbar.bold` identifier, clicks it, asserts source contains `**hi**`.

All identifier-based queries per engineering-standards §2.1. No element-type shortcuts anywhere in the test source.

---

## 7. Engineering standards verification

| Standard | Check | Result |
|---|---|---|
| §1.1 Sandbox-safe | New files touch SwiftUI + AppKit only; no file I/O | ✅ |
| §1.2 Bundle ID | Unchanged | ✅ |
| §1.3 Info.plist | Unchanged | ✅ |
| §2.1 `accessibilityIdentifier` | 14+ identifiers across app + test paths; every new interactive control has one | ✅ |
| §2.2 No `.layoutManager` | grep → only comments | ✅ |
| §2.3 Declarative chord table | `KeyboardBindings.all` still the sole chord-match source; toolbar uses SwiftUI's `.keyboardShortcut` which routes through the menu system (the §2.3 rule is about NSTextView-level chord dispatch, not menu accelerators) | ✅ |

---

## 8. Deviations from spec / plan

- **`.toolbar(id:)` customization API not used.** Spec's example code used the customizable form; compile errors drove us to the simpler non-customizable `.toolbar { … }`. Toolbar customization (drag to reorder, add/remove buttons) is already in spec §5 Out of Scope, so this deviation doesn't change the delivered behavior — just the internal wiring shape.
- **`WindowAccessor.swift` added outside the spec.** Not anticipated; required to fix finding #2. Small, reusable AppKit bridge; lives in `Sources/App/`. Captured above in §4.
- **`@FocusedValue` pattern deferred to multi-window deliverable.** Spec and plan both mentioned it; we used `EditorDispatcherRegistry` instead for D5's single-window case. Stub `EditorDispatcherFocusedValue.swift` checked in so the migration path is clear when multi-window arrives.
- **Dynamic Heading menu label** (e.g., "Heading 1" when caret is on an H1) — out of scope per spec OQ #4. Remains a polish candidate.
- **Link polish** (pre-filled `url` placeholder in `[text](|)`) — out of scope per D4 finding #3. Remains a polish candidate.

---

## 9. Next

Per `docs/roadmap_ref.md`, the roadmap becomes:
- **D3 — Packaging (Sparkle + DMG + notarization)** — deferred by CD; still valid whenever a second-machine install or auto-update is needed. Gating on Apple Developer Program enrollment per `engineering-standards_ref.md` §1.4.
- **D6+ — PortableMind integration** — connected mode (Submit → status transition, document↔entity association, tenant sign-in). First deliverable that bridges the standalone app to the PortableMind ecosystem.

Polish backlog items surfaced across D4 and D5 (bare-parens Link, dynamic Heading label, i18n for keyboard chords, current-format button highlighting) are worth pulling into a dedicated polish deliverable rather than drip-feeding into feature work — the foundation is now solid enough to warrant that.

With D5 done, md-editor-mac is genuinely usable for its primary audience: open a markdown file, see it formatted, click visible buttons to apply formatting, use familiar keyboard shortcuts, hide the toolbar for a cleaner reading view. The vision's Principle 1 ("Word/Docs-familiar authoring experience") is realized at its core level.
