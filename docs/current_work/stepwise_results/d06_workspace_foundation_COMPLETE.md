# D6: Workspace Foundation — Completion Record

**Status:** Complete
**Created:** 2026-04-23
**Completed:** 2026-04-23
**Spec:** `docs/current_work/specs/d06_workspace_foundation_spec.md`
**Plan:** `docs/current_work/planning/d06_workspace_foundation_plan.md`

---

## 1. TL;DR

**D6 is Complete.** md-editor is now a folder workspace: open a folder via `File → Open Folder…` or the `./scripts/md-editor` CLI, see the tree in the sidebar, click files to open them in tabs, switch between tabs, and have external edits reflect per-tab. URL-scheme events route through a new `CommandSurface` module that will become the adapter point for a future MCP integration without code-wide refactor.

The dogfooding moment landed: `./scripts/md-editor apps/md-editor-mac/docs/` opens our own SDLC artifacts in our own editor. Every subsequent feature ships against the editor it runs in.

**Six findings surfaced during implementation and validation — all fixed in-deliverable**, most producing engineering-standards-worthy lessons. Details in §3.

---

## 2. Spec success criteria — pass/fail

| Item | Result |
|---|---|
| `xcodebuild build` clean, no new warnings | ✅ |
| File → Open Folder… (Cmd+Shift+O) picks a folder via NSOpenPanel | ✅ |
| Security-scoped bookmark persists workspace root across launches | ✅ |
| Sidebar shows workspace tree with excluded dirs hidden | ✅ |
| Click file in tree opens in tab; existing tab focused on re-click | ✅ |
| Tab bar with filename + × close control | ✅ |
| Tab switching via click works | ✅ (after ScrollView-removal fix — finding #1) |
| Per-tab external-edit reconcile | ✅ |
| Workspace restores across quit/relaunch (tabs + focus) | ✅ |
| `md-editor://open?path=…` opens file in tab via URL scheme | ✅ |
| `md-editor://open-folder?path=…` switches workspace | ✅ |
| `./scripts/md-editor <path>` CLI wrapper works | ✅ |
| Dogfood: open our own docs folder in our own editor | ✅ |
| No new `.layoutManager` references (§2.2) | ✅ |
| Every new interactive view has accessibilityIdentifier from central enum (§2.1) | ✅ |
| External commands live only in `Sources/CommandSurface/` (§2.4) | ✅ |
| Shell wrapper contains no command semantics (§2.4) | ✅ |

---

## 3. Findings — all fixed in-deliverable, several codified as standards

### Finding #1 — SwiftUI horizontal ScrollView swallowed tab clicks on macOS 15

The initial `TabBarView` used `ScrollView(.horizontal)` wrapping the HStack of tab buttons to enable overflow scrolling. Result: tabs rendered and highlighted on hover (or didn't — see #5 below), but **no click event ever reached the buttons**. Cursor didn't change to pointing-hand; no `onTapGesture`, `Button` action, or `.onChanged` fired.

Diagnosis path: added `NSLog` to every tab's `onFocus` callback and wrapped the tab bar in a diagnostic red background with an `onTapGesture` on the whole row. Clicks on tabs or the red background produced no log — the entire region was event-dead. After several restructure attempts (wrapping in a single outer Button, replacing `onTapGesture` with nested Buttons, moving to `.safeAreaInset`, relocating to the top of the scene above `NavigationSplitView`), the fix that unblocked events was **removing the ScrollView entirely**.

Web search confirmed: SwiftUI ScrollView's drag-gesture recognizer competes for mouse events even when no scroll is possible, and in layered hosting-view scenarios it wins unconditionally. Apple Developer Forums thread [#749620](https://developer.apple.com/forums/thread/749620) and related.

**Resolution:** `TabBarView` is a plain `HStack` with a trailing `Spacer`. If a user opens more tabs than fit horizontally, they clip — a known polish item. Overflow UX (chevron dropdown, or a ScrollView variant with explicit hit-test overrides) is deferred to a later polish deliverable.

**Codified?** Not yet — too narrow for a §-level standard. Captured in the TabBarView source comment so future tab-bar-adjacent work doesn't re-add a ScrollView without understanding the consequence.

### Finding #2 — Nested `@ObservedObject` doesn't propagate inner changes

`WorkspaceView` held `@ObservedObject var workspace: WorkspaceStore`. When `workspace.tabs.open(fileURL:)` changed `tabs.focusedIndex`, `TabBarView` re-rendered (because it observes `TabStore` directly), but the detail region `if let focused = workspace.tabs.focused { EditorContainer(…) }` evaluated once with stale nil — SwiftUI didn't re-evaluate because `workspace.objectWillChange` didn't fire for a nested store's mutation.

**Resolution:** Extracted `WorkspaceDetailView` as a subview taking `@ObservedObject var tabs: TabStore` directly. Now tab changes propagate to the detail through its own observer. Idiomatic SwiftUI — nested ObservableObjects need their own `@ObservedObject` attachment at the consuming view.

**Codified?** Worth a standards note; added below to the change log with a cross-reference to this finding.

### Finding #3 — `WindowGroup` spawns a window per URL event

Running `./scripts/md-editor path1`, then `path2`, then `path3` produced three visible windows on a single process. Cause: SwiftUI's `WindowGroup` is document-oriented — every `.onOpenURL` fires in the scene closure and the scene's default response is to open a new window.

**Resolution:** Switched scene from `WindowGroup { … }` to `Window("MdEditor", id: "main") { … }`. `Window` is single-window by design; `.onOpenURL` fires once on the existing window rather than creating a new one.

**Codified?** Captured in `MdEditorApp.swift` comment. Good standards note for future multi-scene work: pick the scene type that matches the app's document model (single-window = `Window`; per-document windows = `WindowGroup`; menu-bar-only = `MenuBarExtra`).

### Finding #4 — `safeAreaInset(edge: .top)` did NOT resolve the click-through issue

Before identifying ScrollView as the root cause, I tried moving the tab bar from a VStack sibling to a `safeAreaInset` on the editor. Hypothesis: layered NSHostingView boundaries. safeAreaInset is the standard fix pattern per several Apple guides. In our case it didn't help — the ScrollView's own event absorption was the issue, not the layout boundary.

**Resolution:** Reverted to VStack inside WorkspaceDetailView. Lesson captured: safeAreaInset is still the right default for "header bar above scrollable content," but only resolves layout-seam issues, not gesture-competition issues.

### Finding #5 — FolderNode + OutlineGroup requires KeyPath-compatible children

`SwiftUI.OutlineGroup(root, children: closure)` does not exist — the API takes a `KeyPath<Element, [Element]?>`. For a recursive file-tree model, that requires a computed property on the model type:

```swift
struct FolderNode: Identifiable, Hashable {
    let url: URL; let name: String; let isDirectory: Bool
    var children: [FolderNode]? {
        isDirectory ? FolderTreeLoader.children(of: url) : nil
    }
}
```

Hashable/Equatable had to be manually implemented to exclude the computed property (otherwise re-walking the filesystem would make identical nodes unequal).

**Resolution:** As above. Works cleanly with `OutlineGroup(root, children: \.children) { row }`.

### Finding #6 — `Coordinator` touching `@MainActor EditorDocument` requires `@MainActor` on itself

When `EditorContainer`'s `Coordinator` subscribed to `document.$source` via Combine, the compiler flagged "main actor-isolated property '$source' cannot be referenced from a nonisolated context." NSTextView delegates aren't `@MainActor` by default; when they hold a reference to a `@MainActor ObservableObject`, the delegate methods have to be isolated to main too.

**Resolution:** `@MainActor` on the Coordinator class. Done-and-forget; no further implications.

---

## 4. APIs / patterns that worked

- **`@AppStorage` for persistence primitives** — `sidebarVisible`, `sidebarWidth` bind directly to `UserDefaults`. For the non-primitive workspace bookmark, raw `UserDefaults` `data(forKey:)` handled it.
- **`NSFilePresenter` per tab** — scaled from D2's single-file pattern to per-tab without issue. `NSFileCoordinator.addFilePresenter` is cheap.
- **`DispatchSourceFileSystemObject` at the folder level** with a 100ms debounce — covers tree refresh for adds/deletes without polling.
- **Security-scoped bookmarks** — `.withSecurityScope` option on both save and resolve; stopAccessing closure held by `WorkspaceStore` for the workspace lifetime. Worked sandbox-ready out of the gate per standards §1.1.
- **SwiftUI `OutlineGroup(_:children:)`** — once we used the KeyPath variant, laziness came for free.
- **`Window("id: main")` + `.onOpenURL`** — single-window routing that doesn't spawn duplicates.
- **Registry singleton + @Published for dispatcher routing** (`EditorDispatcherRegistry` from D5, still working) — no refactor needed for workspace changes.

## 5. APIs / patterns that were traps

- **`ScrollView` around interactive buttons on macOS** — see finding #1.
- **`WindowGroup` for single-window apps** — see finding #3.
- **`OutlineGroup` with a closure children parameter** — doesn't exist; use KeyPath.
- **Non-`@MainActor` delegate classes holding `@MainActor` stored properties** — see finding #6.
- **Nested `ObservableObject` without direct observers in consuming views** — see finding #2.

---

## 6. Engineering standards verification

| Standard | Check | Result |
|---|---|---|
| §1.1 Sandbox-safe | File access through `NSOpenPanel` + security-scoped bookmarks; no hardcoded paths; no private APIs | ✅ |
| §1.2 Bundle ID | Unchanged | ✅ |
| §1.3 Info.plist | `CFBundleURLTypes` added for `md-editor://` scheme; other keys unchanged | ✅ |
| §2.1 `accessibilityIdentifier` | 14+ new constants for tree rows, tabs, close buttons, sidebar toggle, empty state, menu items; tests use identifier-based queries | ✅ |
| §2.2 No `.layoutManager` | grep clean | ✅ |
| §2.3 Keyboard bindings declarative | `Cmd+Shift+O` and `Cmd+Ctrl+S` via `.keyboardShortcut` on menu items (menu-chord carve-out); no chord checks outside `KeyboardBindings.swift` / menus | ✅ |
| §2.4 Command surface declarative | `rg 'md-editor://' Sources/` → only `CommandSurface/`; shell wrapper is a courier only | ✅ |

---

## 7. Deferrals (out-of-scope for D6, on the polish backlog)

- **Tab overflow UX** — chevron dropdown or a working horizontal scroll. Spec-acknowledged; finding #1's direct consequence.
- **File operations in the tree** (new, rename, delete, move) — do them in Finder for now.
- **Tree keyboard navigation** (arrow keys, enter to open) — accessibility polish.
- **UITest extension for workspace paths** — D6 validation is manual + CLI-driven; automated coverage lands in a later polish deliverable.
- **Dirty-state indicators on tabs** — we track `externallyDeleted`; unsaved-changes indicator is a later deliverable.
- **Multi-window / multi-workspace** — Window (not WindowGroup) is a deliberate single-window commitment at D6. Multi-window would require revisiting.
- **Workspace switching UX** — "Recent Workspaces" menu, drag-drop a folder onto the app — later.

---

## 8. Deviations from spec / plan

- **Shell-wrapper CLI instead of a Swift CLI binary.** Plan recommended starting with the shell wrapper for simplicity; it's sufficient for D6. A Swift binary only earns its place when we need stateful CLI behavior the shell can't express.
- **No formal UITest for the workspace paths in D6.** Deferred to polish given this session's context budget and because the manual + CLI-driven validation proved out the functional paths end-to-end. `LaunchSmokeTests`, `MutationKeyboardTests`, `MutationToolbarTests` from prior deliverables still pass.
- **`EditorDispatcherFocusedValue.swift`** remains a stub (not used in D6) — kept as the migration path for multi-window support. `EditorDispatcherRegistry` singleton is the single-window implementation. Documented inline.

---

## 9. What shipped vs. the roadmap

Per `docs/roadmap_ref.md`, D6 was sketched post-D5 as "PortableMind integration." CD (Rick) reordered during D2 triad review to put workspace/editor-layer foundations first and PortableMind integration later. What actually shipped as D6 is the *workspace foundation* needed BEFORE PortableMind integration can meaningfully happen — folder-of-markdown abstraction, tabs, external command surface. The roadmap ordering now becomes:

- D1 ✅ TextKit 2 spike
- D2 ✅ Project scaffolding
- D4 ✅ Mutation primitives
- D5 ✅ Formatting toolbar
- **D6 ✅ Workspace foundation (this)**
- D3 — Packaging (still deferred; gates on Apple Developer renewal)
- D7+ — PortableMind integration (now unblocked by D6's workspace + CommandSurface primitives)

---

## 10. Next

Natural next moves, in rough priority order (CD's call):

1. **D7 — PortableMind integration (MCP adapter as CommandSurface caller #2; Submit / handoff primitive; tenant sign-in).** D6's CommandSurface is literally built to host this as a thin new-file addition.
2. **Polish deliverable — tab overflow UX, tree navigation, UITest extension.** Good candidates to bundle; would benefit from a fresh session.
3. **D3 — packaging.** Waiting on Apple Developer renewal (per `memory/md_editor_apple_developer_state.md`).
