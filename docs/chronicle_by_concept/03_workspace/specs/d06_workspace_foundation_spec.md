# D6: Workspace Foundation — Folder Navigation, Tabs, and External Command Surface — Specification

**Status:** Complete
**Created:** 2026-04-23
**Completed:** 2026-04-23 — see `docs/current_work/stepwise_results/d06_workspace_foundation_COMPLETE.md`
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D2 (Xcode project, NSFilePresenter pattern, DocumentType registry), D5 (toolbar dispatch via ObservableObject registry — same pattern scales to tab state)
**Traces to:** `docs/vision.md` Principle 1 (HITL agentic loops over folder-of-markdown); `docs/competitive-analysis.md` (Obsidian validates the vault/folder model; iA Writer Library; all three demonstrate tab UX); `docs/portablemind-positioning.md` (standalone-capable with external command integration); `docs/roadmap_ref.md` (D6 bumped ahead of post-D5 placeholders per CD); `docs/engineering-standards_ref.md` §2.4 (just added — external command surface declarative)

---

## 1. Problem Statement

md-editor-mac today opens one file at a time. For the HITL agentic loop our vision targets — where an agent writes to a *folder* of markdown files and the user reads/edits across them — single-file editing is a wall. Opening files one at a time means losing context every time an agent produces a new document, and there's no way to browse the set an agent is producing without dropping to Finder or VS Code.

D6 promotes md-editor from a single-file editor into a **workspace** — open a folder, see the tree on the left, open files in tabs across the top, and have every open file live-reflect external changes. Plus: the first **external command surface** (CLI + URL scheme) so agents can drive the app programmatically (open this file, focus this tab) via the same primitive a later MCP adapter would wrap.

The dogfooding moment: by the end of D6, `md-editor apps/md-editor-mac/docs/` opens our own SDLC artifacts in our own editor. Every subsequent feature gets built against the editor it's shipping in.

---

## 2. Requirements

### Functional — folder workspace

- [ ] **File → Open Folder…** (`Cmd+Shift+O`) opens an `NSOpenPanel` configured for `canChooseDirectories = true`.
- [ ] Selected folder becomes the **workspace root** — persisted via a **security-scoped bookmark** in `UserDefaults` (key: `workspaceRootBookmark`) so the folder reopens on next launch without a file-access prompt.
- [ ] A left sidebar (**Folder Tree**) displays the workspace root and its descendants. Directories expand/collapse; files are click-to-open.
- [ ] Hidden files (leading dot), `.build-xcode/`, `.git/`, `node_modules/`, and `DerivedData/` are excluded by default. (A user-visible "Show hidden" toggle is out of scope; filtering is hardcoded at D6.)
- [ ] The sidebar is **resizable** (horizontal drag handle) and **collapsible** via `View → Hide Sidebar` (`Cmd+Ctrl+S` — macOS convention). Collapsed state persists via `AppSettings.sidebarVisible`.

### Functional — tabs

- [ ] Clicking a file in the tree opens it in a **tab**:
  - If the file is already open in a tab, that tab is focused.
  - Otherwise a new tab is created to the right of the current tab and focused.
- [ ] **Tab bar** sits below the toolbar, above the editor. Each tab shows the file's `lastPathComponent` and an `×` close control.
- [ ] Clicking a tab's name focuses it; clicking the `×` closes it. If the closed tab was focused, focus moves to the neighboring tab (prefer right, fall back to left).
- [ ] Closing the last tab leaves the workspace open with an **empty-editor state** (a placeholder view telling the user to click a file in the sidebar, or drag one into the window).
- [ ] `Cmd+W` closes the current tab. `Cmd+Shift+[` / `Cmd+Shift+]` navigates between tabs (Chrome/Safari convention).
- [ ] Tabs persist across app launches — the set of open files, plus which one was focused, is restored when the workspace reopens.

### Functional — multi-file external-edit

- [ ] Each open tab owns an `NSFilePresenter` for its file. When an external process modifies the file, the tab's buffer reconciles (same D2 behavior, now per-tab).
- [ ] The workspace root is watched with `DispatchSourceFileSystemObject` at the folder level. When files are added or removed, the sidebar tree updates to reflect the change. Rename appears as a delete + add.
- [ ] If a file that's currently open in a tab is deleted externally, the tab shows a visible "file no longer exists" indicator. The tab is not auto-closed (the buffer content is preserved; the user decides what to do).

### Functional — external command surface

- [ ] A **URL scheme** `md-editor://` is registered via Info.plist `CFBundleURLTypes`. URL events route through `Sources/CommandSurface/CommandSurface.swift` — per engineering-standards §2.4.
- [ ] Supported commands in D6:
  - `md-editor://open?path=<url-encoded-absolute-path>[&tab=new|existing]` — open a file in a tab. Defaults to `tab=existing` (focus if already open; new tab otherwise). `tab=new` forces a new tab.
  - `md-editor://open-folder?path=<url-encoded-absolute-path>` — change the workspace root to the given folder.
- [ ] A shell **CLI wrapper** installed as `scripts/md-editor` in the repo (and optionally symlinked to `/usr/local/bin/md-editor` by the user). It accepts a path argument (file or folder) and invokes the URL scheme via `open "md-editor://..."`.
- [ ] If the app is not running, macOS launches it from the URL-scheme invocation (native behavior; requires the Info.plist registration to be correct).

### Functional — dogfooding validation

- [ ] End of D6: `./scripts/md-editor apps/md-editor-mac/docs/` (run from the repo root) opens md-editor with our own docs folder as the workspace. Sidebar shows the tree; clicking `vision.md` opens it in a tab. **We read our own specs in our own editor.**

### Non-functional

- [ ] Standards §1.1 (sandbox-safe) — folder access via security-scoped bookmarks. No direct `FileManager` access outside the bookmark scope. No hardcoded paths.
- [ ] Standards §1.2, §1.3 — unchanged; Info.plist gains `CFBundleURLTypes` for the `md-editor://` scheme.
- [ ] Standards §2.1 — every new interactive view has an `accessibilityIdentifier` from the central enum: tree rows, tab buttons, close controls, sidebar resize handle, empty-editor placeholder.
- [ ] Standards §2.2 — no `.layoutManager` references introduced.
- [ ] Standards §2.3 — new keyboard shortcuts (`Cmd+Shift+O`, `Cmd+Ctrl+S`, `Cmd+W`, `Cmd+Shift+[`, `Cmd+Shift+]`) declared in `KeyboardBindings.all` or via SwiftUI `.keyboardShortcut` on menu items (per the §2.3 rule's menu-chord carve-out).
- [ ] Standards §2.4 (new) — every external command routes through `CommandSurface`. No URL-event handler or CLI hook inlines its own dispatch logic.
- [ ] Performance — opening a folder with ≤500 markdown files builds the tree in <1s subjectively. Sidebar scroll is smooth at 10k visible nodes (SwiftUI `OutlineGroup` is lazy by default). Beyond 10k, we hit known SwiftUI lazy-rendering edges; note as a finding rather than optimize speculatively.

---

## 3. Design

### Module layout

```
Sources/Workspace/                    (new — the core D6 module)
├── WorkspaceStore.swift              ObservableObject: root URL, tree model, open tabs
├── Document.swift                    Per-tab state (URL, buffer, dirty flag, DocumentType)
├── TabStore.swift                    ObservableObject: ordered list of Documents, focus index
├── FolderTreeModel.swift             Tree node type + directory walk + filter rules
├── FolderTreeWatcher.swift           DispatchSourceFileSystemObject wrapper for the root
└── SecurityScopedBookmarkStore.swift UserDefaults-backed bookmark persistence

Sources/WorkspaceUI/                  (new — SwiftUI views for the workspace)
├── WorkspaceView.swift               Top-level split: sidebar + (tabs + editor)
├── FolderTreeView.swift              OutlineGroup-based sidebar
├── TabBarView.swift                  Horizontal tab strip with close buttons
├── EmptyEditorView.swift             Shown when no tab is focused
└── SidebarToggleModifier.swift       Show/Hide Sidebar plumbing

Sources/CommandSurface/               (new — per standard §2.4)
├── CommandSurface.swift              Single registry of external commands
├── URLSchemeHandler.swift            Receives md-editor://… events, parses, dispatches
└── ExternalCommand.swift             Protocol + command enum

scripts/md-editor                     (new — shell wrapper)
```

### Document and TabStore

`Document` replaces the single-file-state currently held on `EditorContainer.Coordinator`:

```swift
@MainActor
final class Document: ObservableObject, Identifiable {
    let id = UUID()
    @Published var url: URL?                // nil = untitled (post-D4 finding #1 still honored)
    @Published var source: String
    @Published var documentType: any DocumentType
    @Published var isDirty: Bool = false
    @Published var externallyDeleted: Bool = false
    let watcher = ExternalEditWatcher()
    // … helpers for read/write/reconcile …
}

@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var documents: [Document] = []
    @Published var focusedIndex: Int? = nil
    var focused: Document? { focusedIndex.map { documents[$0] } }
    func open(fileURL: URL, forceNewTab: Bool = false) { … }
    func close(documentID: UUID) { … }
    func focus(documentID: UUID) { … }
}
```

`TabStore` is the workspace's source of truth for "what's open." `EditorContainer` reads `tabStore.focused` and displays its buffer. `CursorLineTracker`, `CommandDispatcher`, etc. unchanged — they all operate on whatever `NSTextView` they're handed, and the view wires the focused `Document` into the text view on focus change.

### Folder tree model

```swift
struct FolderNode: Identifiable, Hashable {
    let id: URL
    let name: String
    let isDirectory: Bool
    var children: [FolderNode]?   // nil = not yet loaded or leaf
}

enum FolderFilter {
    static let excludedNames: Set<String> = [
        ".git", ".build-xcode", "DerivedData", "node_modules",
        ".swiftpm", ".build", "Pods", ".DS_Store"
    ]
    static func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".") || excludedNames.contains(url.lastPathComponent)
    }
}
```

`FolderTreeView` uses SwiftUI `OutlineGroup(_:children:)`; lazy loading of children on expand avoids walking deep trees eagerly.

### Security-scoped bookmarks

```swift
@MainActor
final class SecurityScopedBookmarkStore {
    static let shared = SecurityScopedBookmarkStore()

    func save(url: URL, forKey key: String) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    func resolve(key: String) throws -> (url: URL, stopAccessing: () -> Void)? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return (url, { url.stopAccessingSecurityScopedResource() })
    }
}
```

The workspace holds the `stopAccessing` closure for the lifetime of the open workspace; releases on workspace close. Any file operations read-through the scoped URL and inherit its access.

### CommandSurface

```swift
// Sources/CommandSurface/ExternalCommand.swift
enum ExternalCommandIdentifier: String {
    case openFile = "open"
    case openFolder = "open-folder"
}

protocol ExternalCommand {
    static var identifier: ExternalCommandIdentifier { get }
    static func execute(params: [String: String], in workspace: WorkspaceStore)
}

// Sources/CommandSurface/CommandSurface.swift
enum CommandSurface {
    private static let registry: [ExternalCommandIdentifier: any ExternalCommand.Type] = [
        OpenFileCommand.identifier: OpenFileCommand.self,
        OpenFolderCommand.identifier: OpenFolderCommand.self,
    ]
    static func dispatch(identifier: ExternalCommandIdentifier,
                         params: [String: String],
                         in workspace: WorkspaceStore) {
        registry[identifier]?.execute(params: params, in: workspace)
    }
}
```

`URLSchemeHandler` is the only caller in D6; a future MCP wrapper would be a second caller of the same `CommandSurface.dispatch` entry point.

### CLI wrapper

```bash
#!/bin/bash
# scripts/md-editor — thin wrapper. URL-encode the absolute path,
# compose a md-editor:// URL, hand to `open`. macOS launches the
# app if it's not already running.

set -euo pipefail
target="${1:-}"
if [[ -z "$target" ]]; then
    echo "usage: md-editor <path>" >&2
    exit 2
fi

absolute="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
encoded="$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$absolute")"

if [[ -d "$absolute" ]]; then
    open "md-editor://open-folder?path=$encoded"
else
    open "md-editor://open?path=$encoded&tab=existing"
fi
```

No Swift CLI binary in D6 — the shell wrapper is simpler and we don't need a Swift-side CLI until we have something stateful to run. A proper binary is a future deliverable if needed.

### Sandbox compatibility

A fresh file-system-operation rule that goes with §1.1: all file access must be either (a) through the workspace root's security-scoped bookmark, or (b) through `NSOpenPanel`/`NSSavePanel` which grant one-shot access. No direct `FileManager` calls against absolute paths that came from outside. The CLI wrapper is fine because URL-scheme launches go through macOS's `LSOpenURLWithRole` path, which carries scope with the user intent.

---

## 4. Success Criteria

- [ ] `xcodebuild build` clean.
- [ ] **File → Open Folder…** prompts via `NSOpenPanel`; selecting a folder sets it as the workspace root and persists.
- [ ] Sidebar displays folder contents; excluded directories are hidden; expand/collapse works.
- [ ] Clicking a `.md` file in the tree opens it in a tab. Clicking an already-open file focuses its tab.
- [ ] Tabs render with filename + close control. `Cmd+W` closes the current tab; `Cmd+Shift+]` / `[` navigate.
- [ ] External edit to an open file reflects in the correct tab (verified by `echo "# x" >> some-open-file.md` and watching the buffer update).
- [ ] Creating / deleting files in the workspace root updates the sidebar without restart.
- [ ] Deleting an open file shows the tab's "file no longer exists" indicator; the tab is not auto-closed.
- [ ] Quit app. Relaunch. **Workspace root, open tabs, and focused tab are restored.**
- [ ] `md-editor://open?path=<…>` opens the file in a tab (focuses if already open, new tab otherwise).
- [ ] `md-editor://open-folder?path=<…>` changes the workspace root.
- [ ] `./scripts/md-editor apps/md-editor-mac/docs/` from the repo root opens md-editor with the docs folder as the workspace, tree populated.
- [ ] `./scripts/md-editor apps/md-editor-mac/docs/vision.md` opens that file into a tab in the running app.
- [ ] `rg --type swift 'accessibilityIdentifier' Sources/` shows ≥20 matches (was 14 post-D5; add tree row, tab, close button, empty-editor, sidebar toggle, etc.).
- [ ] `rg --type swift 'md-editor://' Sources/` hits only `CommandSurface/` — proves §2.4 compliance.
- [ ] `rg --type swift 'layoutManager\\b' Sources/` still zero non-comment hits.
- [ ] UITest extended with a new test: launch app with workspace already open (pre-seeded via command-line args), assert tree root exists by identifier, assert a specific file's row exists, click it, assert a tab with that filename appears.

---

## 4.5 Validation approach

Phase 1 exploratory with a supplemental XCUITest. Scope-wise D6 is bigger than D5, so the demo script also grows — 20+ steps covering: folder open, tree navigation, tab open/close/focus, external edit to each of two open tabs, workspace persistence across quit-relaunch, URL scheme with app-not-running + app-running, CLI wrapper from shell.

**Dogfooding acceptance:** we read a D5 completion record in md-editor itself during the demo run. If that works, we declare the dogfooding moment and take a victory lap.

Evidence: screen recording, transcript in `evidence/d06/`, xcodebuild build + test logs, Info.plist excerpt showing the URL scheme registration.

---

## 5. Out of Scope

- **Submit / handoff primitive** (Level 2 agent-aware active side) — later deliverable. D6 is the *environment* agents work in; Submit is the *verb* between us and them.
- **File operations in the tree** — new file, rename, delete, move. Users do those in Finder / their shell for now.
- **Drag-and-drop** — neither within the tree nor from Finder into the app.
- **Git gutter, dirty-state indicators in the tab bar** — just "file externally deleted" indicator at D6. Full dirty-state UI is a polish deliverable.
- **Multi-window / multi-workspace** — single window, single workspace per app instance.
- **Non-markdown file display** — tree shows files of any type, but double-clicking a non-`.md` file is a no-op until a later DocumentType registers for it.
- **MCP server** — deferred per D6 triad discussion. CommandSurface architecture makes the future add trivial.
- **Swift CLI binary** — shell wrapper is sufficient; promote to real Swift binary if/when we need stateful CLI behavior.
- **Workspace switching UX** — no "recent workspaces" menu; Open Folder… is how you change it.
- **Full tree operations (expand-all, collapse-all, reveal in Finder)** — can add later via right-click menus; D6 keeps the tree minimal.

---

## 6. Open Questions

1. **Sidebar width default.** macOS convention is ~220–280 pt. Recommendation: **240 pt**. Persist the user's adjustment across launches via `AppSettings.sidebarWidth` (new @AppStorage key).
2. **Tab overflow handling.** When more tabs than fit, do we scroll horizontally, show a chevron with a dropdown, or compress? Recommendation: **horizontal scroll for D6**, with a chevron-dropdown as a polish add later. Matches Safari's current behavior; simpler to ship.
3. **Workspace restoration on launch: all previous tabs, or just the last-focused?** Recommendation: **all previous tabs with the last focus restored.** Matches Xcode / VS Code; essential for the agentic-loop use case where several files are "in progress" at once.
4. **CLI-launch race: what if the URL scheme arrives before the workspace is restored?** The URL-scheme event fires on `application(_:open:)` which can fire before our SwiftUI scene fully initializes. Recommendation: **queue URL events until the workspace is ready; then drain.** `CommandSurface` holds a pending-events queue internally.
5. **File tree for files outside the workspace.** Do we let the user navigate above the root? Recommendation: **no at D6.** Root is the root; go up via Open Folder… again. Simpler mental model; matches Obsidian vaults, Xcode projects.

Default decisions proceed unless you say otherwise.

---

## 7. Definition of Done

D6 is Complete when:
- All Success Criteria items check.
- Demo script executed end-to-end; evidence captured.
- Dogfooding moment achieved: we read `docs/vision.md` inside md-editor as part of the demo.
- UITest extended and passing.
- `docs/engineering-standards_ref.md` §2.4 grep-clean.
- `docs/roadmap_ref.md` updated — D6 marked complete, D7 proposed (likely: Submit / handoff primitive per `vision.md` Principle 1 Level 2, starting the active agent-aware layer).
