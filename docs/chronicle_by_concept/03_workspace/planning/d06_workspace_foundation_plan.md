# D6: Workspace Foundation — Implementation Instructions

**Spec:** `d06_workspace_foundation_spec.md`
**Created:** 2026-04-23

---

## Overview

Promote md-editor from single-file editing into a folder workspace with a sidebar tree, tabs, per-tab external-edit reconcile, and an external command surface (URL scheme + CLI shell wrapper). Ends with dogfooding our own docs folder in the app.

Largest deliverable since D2. New data layer (`Document`, `TabStore`, `WorkspaceStore`), new view layer (sidebar, tab bar, split view), new external-integration layer (URL scheme + CommandSurface + CLI). Existing D4 dispatcher and D5 toolbar connect through without changes — they already act on whatever text view they're handed; the tab-switching code swaps which text view that is.

---

## Prerequisites

- [ ] D5 Complete; all tests green.
- [ ] `DEVELOPER_DIR` sourced in pane 2.
- [ ] Spec Open Questions accepted or adjusted (defaults proceed: sidebar 240pt, scroll-for-overflow, restore-all-tabs, queue-and-drain URL events, no-above-root navigation).

---

## Implementation Steps

Six logical batches, one commit per batch.

### Batch 1 — Data layer + identifiers

**Files:**
- `Sources/Workspace/SecurityScopedBookmarkStore.swift`
- `Sources/Workspace/Document.swift`
- `Sources/Workspace/TabStore.swift`
- `Sources/Workspace/FolderTreeModel.swift`
- `Sources/Accessibility/AccessibilityIdentifiers.swift` (extend)
- `Sources/Settings/AppSettings.swift` (extend)

**`SecurityScopedBookmarkStore`** — per spec §3. Save/resolve bookmarks in UserDefaults with `.withSecurityScope` options.

**`Document`** — per-tab state:

```swift
@MainActor
final class Document: ObservableObject, Identifiable {
    let id = UUID()
    @Published var url: URL?
    @Published var source: String
    @Published var externallyDeleted: Bool = false
    let documentType: any DocumentType
    let watcher = ExternalEditWatcher()

    init(url: URL?, source: String, documentType: any DocumentType) {
        self.url = url
        self.source = source
        self.documentType = documentType
        if let url { watcher.watch(url: url) }
        watcher.onChange = { [weak self] newText in
            Task { @MainActor in self?.source = newText }
        }
    }

    deinit { watcher.stop() }
}
```

Dirty-flag deferred to polish; not in D6 per spec §5.

**`TabStore`** — ordered list + focus:

```swift
@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var documents: [Document] = []
    @Published var focusedIndex: Int? = nil

    var focused: Document? {
        focusedIndex.flatMap { documents.indices.contains($0) ? documents[$0] : nil }
    }

    @discardableResult
    func open(fileURL: URL, forceNewTab: Bool = false) -> Document {
        if !forceNewTab,
           let existing = documents.firstIndex(where: { $0.url == fileURL }) {
            focusedIndex = existing
            return documents[existing]
        }
        let source = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let type = DocumentTypeRegistry.shared.type(for: fileURL) ?? MarkdownDocumentType()
        let doc = Document(url: fileURL, source: source, documentType: type)
        let insertIndex = (focusedIndex.map { $0 + 1 }) ?? documents.count
        documents.insert(doc, at: insertIndex)
        focusedIndex = insertIndex
        return doc
    }

    func close(id: UUID) { … standard logic … }
    func focus(id: UUID) { … standard logic … }
}
```

**`FolderTreeModel`** — nodes + filter + lazy directory walk:

```swift
struct FolderNode: Identifiable, Hashable {
    let id: URL
    let name: String
    let isDirectory: Bool
}

enum FolderFilter {
    static let excludedNames: Set<String> = [
        ".git", ".build-xcode", "DerivedData", "node_modules",
        ".swiftpm", ".build", "Pods", ".DS_Store"
    ]
    static func shouldShow(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return !name.hasPrefix(".") && !excludedNames.contains(name)
    }
}

enum FolderTreeLoader {
    /// Returns direct children of `url`, filtered, sorted (dirs first, then alpha).
    static func children(of url: URL) -> [FolderNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter(FolderFilter.shouldShow)
            .map { childURL in
                let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FolderNode(id: childURL, name: childURL.lastPathComponent, isDirectory: isDir)
            }
            .sorted { ($0.isDirectory ? 0 : 1, $0.name.localizedCaseInsensitiveCompare($1.name))
                        < ($1.isDirectory ? 0 : 1, .orderedSame) }
    }
}
```

(Final sort comparator needs fixing — write the tuple comparison correctly in the real code; sketch above is directional.)

**AppSettings** extensions:

```swift
@AppStorage("sidebarVisible") var sidebarVisible: Bool = true
@AppStorage("sidebarWidth") var sidebarWidth: Double = 240
// workspaceRoot bookmark lives under UserDefaults key "workspaceRootBookmark"
// (raw Data, not wrappable via @AppStorage's Bool/Int/Double/String constraint)
```

**AccessibilityIdentifiers** additions:

```swift
static let folderTree = "md-editor.sidebar.folder-tree"
static let folderTreeRowPrefix = "md-editor.sidebar.folder-tree.row"  // + "/" + URL.path.md5-ish
static func folderTreeRow(_ url: URL) -> String {
    "md-editor.sidebar.folder-tree.row:\(url.path)"
}
static let sidebarToggleButton = "md-editor.sidebar.toggle"
static let tabBar = "md-editor.tabs.bar"
static func tabButton(id: UUID) -> String { "md-editor.tabs.tab:\(id.uuidString)" }
static func tabCloseButton(id: UUID) -> String { "md-editor.tabs.close:\(id.uuidString)" }
static let emptyEditor = "md-editor.empty-editor"
static let openFolderMenuItem = "md-editor.menu.file.open-folder"
```

**Checkpoint build** — these files should compile with only imports and references that already exist.

### Batch 2 — Sidebar, tab bar, empty-state views

**Files:**
- `Sources/WorkspaceUI/FolderTreeView.swift`
- `Sources/WorkspaceUI/TabBarView.swift`
- `Sources/WorkspaceUI/EmptyEditorView.swift`

**`FolderTreeView`** — SwiftUI `OutlineGroup` over a recursive-children closure:

```swift
struct FolderTreeView: View {
    @ObservedObject var workspace: WorkspaceStore
    var body: some View {
        List {
            OutlineGroup(workspace.rootNode, children: childrenFor) { node in
                FolderRowView(node: node) {
                    if !node.isDirectory { workspace.tabs.open(fileURL: node.id) }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.folderTree)
    }

    private func childrenFor(_ node: FolderNode) -> [FolderNode]? {
        node.isDirectory ? FolderTreeLoader.children(of: node.id) : nil
    }
}
```

`FolderRowView` is a small subview: icon (SF Symbol `folder` or `doc.text`) + name, clickable, with its own `accessibilityIdentifier(AccessibilityIdentifiers.folderTreeRow(node.id))`.

**`TabBarView`** — horizontal scroll of pill-buttons:

```swift
struct TabBarView: View {
    @ObservedObject var tabs: TabStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(tabs.documents.enumerated()), id: \.element.id) { index, doc in
                    TabView(document: doc,
                            isFocused: tabs.focusedIndex == index,
                            onFocus: { tabs.focus(id: doc.id) },
                            onClose: { tabs.close(id: doc.id) })
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .accessibilityIdentifier(AccessibilityIdentifiers.tabBar)
    }
}
```

**`EmptyEditorView`** — centered text + placeholder prompt. `accessibilityIdentifier(AccessibilityIdentifiers.emptyEditor)`.

### Batch 3 — WorkspaceStore, WorkspaceView, EditorContainer refactor

**Files:**
- `Sources/Workspace/WorkspaceStore.swift`
- `Sources/Workspace/FolderTreeWatcher.swift`
- `Sources/WorkspaceUI/WorkspaceView.swift`
- `Sources/Editor/EditorContainer.swift` (refactor — no longer reads fileURL binding directly)
- `Sources/App/MdEditorApp.swift` (rewire scene to WorkspaceView)

**`WorkspaceStore`** — owns the workspace lifecycle:

```swift
@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published var rootURL: URL?
    @Published var rootNode: FolderNode?
    let tabs = TabStore()
    private var treeWatcher: FolderTreeWatcher?
    private var bookmarkAccessStop: (() -> Void)?

    func restoreFromBookmarks() {
        if let resolved = try? SecurityScopedBookmarkStore.shared.resolve(key: "workspaceRootBookmark") {
            setRoot(url: resolved.url, stopAccessing: resolved.stopAccessing)
        }
        // Restore open tabs and focus from JSON in UserDefaults (see "tab persistence" below).
    }

    func setRoot(url: URL, stopAccessing: (() -> Void)? = nil) {
        bookmarkAccessStop?()
        bookmarkAccessStop = stopAccessing
        rootURL = url
        rootNode = FolderNode(id: url, name: url.lastPathComponent, isDirectory: true)
        treeWatcher = FolderTreeWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.rootNode = FolderNode(id: url, name: url.lastPathComponent, isDirectory: true) }
        }
        try? SecurityScopedBookmarkStore.shared.save(url: url, forKey: "workspaceRootBookmark")
    }

    private init() {}
}
```

**Tab persistence** — on each `TabStore` change, serialize `[url string]` + focus index to `UserDefaults` ("openTabs", "focusedTabIndex"). On `restoreFromBookmarks`, re-open each URL (skip missing files; no crash on deleted-since-last-run).

**`FolderTreeWatcher`** — thin wrapper around `DispatchSourceFileSystemObject`. Debounce events (100ms) so a burst of writes produces one tree refresh.

**`WorkspaceView`** — top-level split:

```swift
struct WorkspaceView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView {
            if let root = workspace.rootNode {
                FolderTreeView(workspace: workspace)
                    .navigationTitle(root.name)
            } else {
                Text("Open a folder to start").foregroundStyle(.secondary)
            }
        } detail: {
            VStack(spacing: 0) {
                TabBarView(tabs: workspace.tabs)
                Divider()
                if let doc = workspace.tabs.focused {
                    EditorContainer(document: doc)
                } else {
                    EmptyEditorView()
                }
            }
        }
    }
}
```

**`EditorContainer` refactor** — take a `Document` instead of `@Binding var fileURL: URL?`:

```swift
struct EditorContainer: NSViewRepresentable {
    @ObservedObject var document: Document
    // makeCoordinator + makeNSView mostly unchanged; the text view's
    // string is set from `document.source` on creation and on
    // document change. On every textDidChange, write back to
    // document.source. Coordinator observes document changes via
    // Combine subscription (or SwiftUI rebuilds on doc-ID change).
}
```

The key subtlety: when the focused Document *changes* (user clicks another tab), SwiftUI will call `updateNSView` with the new document. Coordinator detects the ID change and:
1. Saves the current NSTextView state back to the old document (which is no longer the @ObservedObject we have — so we actually do the writeback every textDidChange, not on switch).
2. Resets the NSTextView to the new document's source.
3. Registers `EditorDispatcherRegistry` for the new text view.

Simplest implementation: one `EditorContainer` instance per Document, recreated by SwiftUI when the focused Document's ID changes. Costs a `makeNSView` call per tab switch but is conceptually cleaner than mutating a shared NSTextView. D6 takes the clean path; optimize if perf suffers.

**`MdEditorApp`** becomes:

```swift
@main
struct MdEditorApp: App {
    @ObservedObject private var workspace = WorkspaceStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 900, minHeight: 560)
                .background(WindowAccessor { window in
                    window.toolbar?.isVisible = settings.toolbarVisible
                })
                .onAppear { workspace.restoreFromBookmarks() }
                .onOpenURL { url in URLSchemeHandler.handle(url) }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.expanded)
        .commands {
            CommandGroup(replacing: .toolbar) { … unchanged from D5 … }
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { openFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .accessibilityIdentifier(AccessibilityIdentifiers.openFolderMenuItem)
            }
            CommandGroup(replacing: .sidebar) { … show/hide sidebar … }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            workspace.setRoot(url: url, stopAccessing: { url.stopAccessingSecurityScopedResource() })
        }
    }
}
```

### Batch 4 — URL scheme + CommandSurface

**Files:**
- `Sources/CommandSurface/ExternalCommand.swift`
- `Sources/CommandSurface/CommandSurface.swift`
- `Sources/CommandSurface/URLSchemeHandler.swift`
- `Sources/CommandSurface/OpenFileCommand.swift`
- `Sources/CommandSurface/OpenFolderCommand.swift`
- `project.yml` (extend Info.plist properties with CFBundleURLTypes)

**Info.plist additions** (via project.yml `info.properties`):

```yaml
CFBundleURLTypes:
  - CFBundleURLName: ai.portablemind.md-editor.url-scheme
    CFBundleURLSchemes:
      - md-editor
    CFBundleTypeRole: Editor
```

**`URLSchemeHandler`**:

```swift
enum URLSchemeHandler {
    static func handle(_ url: URL) {
        guard url.scheme == "md-editor",
              let host = url.host,
              let identifier = ExternalCommandIdentifier(rawValue: host) else { return }
        var params: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.forEach { if let v = $0.value { params[$0.name] = v } }
        Task { @MainActor in
            CommandSurface.dispatch(identifier: identifier,
                                    params: params,
                                    in: WorkspaceStore.shared)
        }
    }
}
```

**`OpenFileCommand`** reads `path`, optionally `tab`, calls `workspace.tabs.open(fileURL:forceNewTab:)`. **`OpenFolderCommand`** reads `path`, calls `workspace.setRoot(url:)`.

Pending-queue for pre-init URL events (spec OQ #4): if the workspace hasn't called `restoreFromBookmarks` yet, `CommandSurface` buffers the event and drains on first workspace-ready notification. Implementation detail inside `CommandSurface`; `URLSchemeHandler` doesn't need to know.

### Batch 5 — CLI wrapper + UITest

**Files:**
- `scripts/md-editor` (new shell wrapper)
- `UITests/WorkspaceTests.swift` (new)

Shell wrapper as sketched in spec §3. Make executable (`chmod +x scripts/md-editor`).

**UITest**:

```swift
final class WorkspaceTests: XCTestCase {
    func testOpenFileViaURLSchemeOpensTab() throws {
        let app = XCUIApplication()
        // Pre-seed a workspace root via environment or launch argument.
        // Simplest: launch, then drive the UI to open a known fixture
        // folder. Alternative: bundle a small fixture folder into the
        // test target and point the URL scheme at a file inside.
        app.launch()
        // … open scripts/ or a fixture folder, then click a file,
        // assert a tab with that filename exists (query via
        // tabButton(id: UUID) isn't stable — use accessibilityLabel
        // with the filename as a fallback for the test's purposes).
    }
}
```

UITest scope is modest at D6: prove the workspace path can be exercised by AX. Comprehensive test coverage is a later polish deliverable; D6 needs one green smoke of the new path.

### Batch 6 — Build, launch, dogfood, polish

```bash
cd /Users/richardkoloski/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
  -configuration Debug -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Iterate on the demo script in spec §4.5. Fix whatever shakes out. Run `xcodebuild test` for the full suite (LaunchSmokeTests + MutationKeyboardTests + MutationToolbarTests + WorkspaceTests).

**Dogfooding moment**: from the repo root, `./scripts/md-editor apps/md-editor-mac/docs/`. Sidebar shows vision.md, competitive-analysis.md, the current_work/ subtree. Click vision.md. Read our own spec in our own editor. Commit with a celebratory message.

---

## Testing

**Manual demo** (20+ steps; captured in `evidence/d06/transcript.md` with screen recording):

1. Launch: empty-editor state, sidebar shows "Open a folder to start."
2. File → Open Folder… pick `~/src/apps/md-editor-mac/docs`.
3. Verify tree shows `vision.md`, `competitive-analysis.md`, `current_work/`, etc.
4. Click `vision.md` → tab opens, focused.
5. Click `competitive-analysis.md` → second tab, focused.
6. Click the first tab → focus moves to vision.
7. Close first tab via `×`. Verify focus moves to the remaining tab.
8. `Cmd+W` closes it. Empty-editor state.
9. Re-open both. Edit one. Switch tabs. Come back. Edit preserved.
10. External terminal: `echo "# new" >> .../vision.md` while vision.md tab is focused. Verify buffer updates.
11. `echo "# other" >> .../competitive-analysis.md` while vision.md is focused. Switch to competitive. Verify buffer has new line.
12. Delete a file externally. Verify tab shows externally-deleted indicator.
13. Create a file externally. Verify tree refreshes.
14. Quit. Relaunch. Verify workspace root, open tabs, and focused tab restored.
15. `./scripts/md-editor apps/md-editor-mac/docs/vision.md` from repo root. Running app focuses on vision.md tab.
16. `./scripts/md-editor apps/md-editor-mac/docs/stack-alternatives.md` → new tab.
17. Quit app. `./scripts/md-editor apps/md-editor-mac/docs/` → app launches, workspace opens.
18. `Cmd+Ctrl+S` toggles sidebar. Persists across relaunch.
19. Formatting (D4/D5) still works — e.g., Cmd+B inside a tab bolds the selection. (Regression check.)
20. Toolbar show/hide (D5) still works.

**Automated**: `xcodebuild test` — all prior test cases (Launch, MutationKeyboard, MutationToolbar) plus new WorkspaceTests smoke.

### Verification Checklist

- [ ] `rg --type swift 'md-editor://' Sources/` → only `Sources/CommandSurface/`
- [ ] `rg --type swift 'layoutManager\\b' Sources/` → only comments
- [ ] `rg --type swift 'accessibilityIdentifier' Sources/` → ≥20 matches
- [ ] `rg --type swift 'event\\.keyCode|event\\.charactersIgnoringModifiers' Sources/` → only `KeyboardBindings.swift`
- [ ] `rg --type swift 'FileManager.default.contentsOfDirectory' Sources/` → only `FolderTreeModel.swift` (all folder walks centralized)
- [ ] Info.plist (built) contains `CFBundleURLTypes` with the md-editor scheme (verify with PlistBuddy)
- [ ] `./scripts/md-editor` is executable and handles both file and folder args
- [ ] All prior UITests still pass
- [ ] New WorkspaceTests passes
- [ ] Dogfooding demo step 15–17 executed and captured
- [ ] COMPLETE doc written, roadmap updated, spec flipped to Complete

---

## Notes

- **Refactoring EditorContainer is the risky part.** It currently owns a lot of single-file state. Doing the TabStore-backed refactor carefully keeps D4 dispatch + D5 toolbar + D1 cursor-tracking behaviors intact. Expect some bug-hunt time here; add regression checks in the demo (step 19).
- **`NavigationSplitView` vs `HSplitView`:** `NavigationSplitView` has more native macOS behaviors (auto-collapsing, integrated sidebar toggle), but it's opinionated about navigation state. `HSplitView` is simpler and more direct. Recommendation: start with `NavigationSplitView` (Apple blessed); drop to `HSplitView` if we fight its assumptions.
- **Tab persistence format:** simple JSON array of strings (file paths) + an integer focused-index. Stored under `openTabs` / `focusedTabIndex` in UserDefaults. Handle missing-file case on restore (skip; don't error).
- **Security-scoped bookmark note:** `startAccessingSecurityScopedResource()` must be balanced with `stop`. The `WorkspaceStore` owns that lifecycle; drop the stop closure only when the workspace root changes or the app quits.
- **URL-scheme pending-queue:** implement as a simple `[(id, params)]` buffer inside `CommandSurface`, drained by a `markWorkspaceReady()` call from `WorkspaceStore.restoreFromBookmarks` completion. Keeps the asymmetric init / URL-event-arrival race explicit rather than papered over with DispatchQueue.main.async tricks.
- **Commit cadence:** one commit per batch (6 total) plus one or two bug-fix commits we're statistically likely to need during integration. Keep each commit's message precise about which primitives were added/changed.
- **Don't be clever about the NSTextView per tab.** Recreating the text view on tab switch (SwiftUI rebuilding EditorContainer when the Document changes) is simple and correct. Single-NSTextView-with-buffer-swap is an optimization target if needed.
