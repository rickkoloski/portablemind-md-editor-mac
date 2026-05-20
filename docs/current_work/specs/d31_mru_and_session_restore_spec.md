# D31: Open Recent + Session Restore — Specification

**Status:** Draft
**Created:** 2026-05-15
**Author:** CD/CC
**Depends On:** D6 (workspace foundation), D14 (Save / Save As), D18 (Connector + PM tabs), D19 (PM save-back)

---

## 1. Problem Statement

Two adjacent gaps in the workspace experience:

1. **No Open Recent menu.** Users who switch between a handful of files re-traverse the sidebar each time. Standard macOS apps surface a `File → Open Recent` list; md-editor doesn't.
2. **Session restore is partial.** `WorkspaceStore` does persist open-tab paths and a focused-index to `UserDefaults` (`Sources/Workspace/WorkspaceStore.swift:191`), but the implementation has three live defects:
   - PM-origin tabs are silently dropped — only `url?.path` is persisted; PM docs (no local URL) leave no record.
   - Focused-index uses `integer(forKey:)`, which returns `0` when the key is absent — indistinguishable from "focus first tab," so a restore with no prior focus state silently jumps to index 0.
   - No scroll position is restored, so a restored doc always lands at line 1.

The dogfood loop has shifted decisively to PM tabs (D19 onwards). Restoring only local tabs means relaunch effectively clears the most-relevant half of the workspace.

This deliverable bundles the two because they share storage, the connector-aware open path, and a single round-trip test surface.

**Foundation trace:** Vision Principle 1 (Word/Docs-familiar authoring) — Open Recent and "pick up where you left off" are baseline expectations of any production editor; their absence is felt every session.

---

## 2. Requirements

### Functional — Open Recent menu

- [ ] **F1.** `File → Open Recent` submenu lists up to **15** most-recently-opened files, ordered newest first.
- [ ] **F2.** An item is added (or moved to the top) whenever a file is **opened** via any path: sidebar click (local + PM), `File → Open…`, `File → Open Folder…` (folder root only — see F3a), CommandSurface / CLI / URL scheme, drag-drop (if/when added), tab restore on launch.
- [ ] **F3.** The same logical file is de-duped:
  - Local: by absolute file URL (resolved symlinks not required for v1).
  - PM: by `(connectorID, fileID)`.
- [ ] **F3a.** Opening a workspace folder via `File → Open Folder…` appends a separate **"Recent Folders"** sub-section to the bottom of the same submenu (also capped at 5). Selecting a recent folder calls `WorkspaceStore.setRoot(url:)` as if the user had picked it from the open panel.
- [ ] **F4.** Each item renders as `<filename>` with a tooltip showing the full identifier:
  - Local → POSIX path (home-relative if under `$HOME`, matching D21 tooltip convention).
  - PM → `<displayPath>  ·  <connectorID>` (e.g., `portablemind/rick/notes.md  ·  portablemind`).
- [ ] **F5.** Items whose underlying file no longer resolves are still listed but **disabled** (greyed out) with an "(unavailable)" suffix. Clicking is a no-op. PM items require the matching connector to be loaded; if the PM connector isn't present (no token), PM items are disabled but **not** removed. Local items are disabled when `FileManager.default.fileExists(atPath:)` is false at menu-build time.
- [ ] **F6.** **Clear Menu** item at the bottom of the submenu (under a divider) wipes the MRU list. No confirmation dialog (matches AppKit standard).
- [ ] **F7.** Selecting a recent file opens it via the same code path as a fresh open:
  - Local: `workspace.tabs.open(fileURL:)`.
  - PM: rebuild a minimal `ConnectorNode` from persisted fields, then `connector.openFile(node)` → `workspace.tabs.openFromConnector(content:node:)` (the existing async path in `WorkspaceView.handleSelect`, lifted into `WorkspaceStore`).
- [ ] **F8.** Menu items appear in `File → Open Recent` after the standard `File → Open…` button. Standard macOS keyboard navigation (arrow keys) works.

### Functional — Session restore

- [ ] **F9.** On launch, `WorkspaceStore.restoreFromBookmarks()` restores **all** tabs that were open at quit, in their previous left-to-right order, including PM tabs.
- [ ] **F10.** The previously-focused tab is re-focused. Distinguish "no focus" (no tabs were open at quit) from "focus index 0" — see §3 storage shape (`focusedTabKey: String?` not `focusedIndex: Int`).
- [ ] **F11.** Each restored tab opens to the **scroll line** it had at quit (`scrollLine: Int`, 1-based, clamped to document length on restore).
- [ ] **F12.** A tab that **fails** to restore (local: file gone; PM: connector unloaded or fetch errors) is skipped without an alert. The MRU entry remains, however (F5 governs its display in the menu).
- [ ] **F13.** Quitting the app persists the open-tab + focused-tab + scroll-line state atomically (a single combined `UserDefaults` write per change, debounced — see NF3).
- [ ] **F14.** **Dirty buffers are not preserved.** A tab with unsaved changes at quit will restore the *on-disk* version (or for PM, the server version). This matches today's behavior and is called out in §5 (Out of Scope).
- [ ] **F15.** First-launch on a fresh install: no tabs to restore, no MRU entries, no error.

### Non-Functional

- [ ] **NF1.** **Persistence layer:** `UserDefaults` only. No new files, no new dependencies. (Aligns with CLAUDE.md "Local state: UserDefaults or small JSON; no Core Data / SwiftData.")
- [ ] **NF2.** **Schema versioning:** persisted records carry a top-level `schemaVersion: 1` integer; an unrecognized future schema is ignored on read (state resets to empty, no crash).
- [ ] **NF3.** **Write debounce:** scroll-line changes can fire frequently while the user scrolls. The session-state writer debounces to **500ms** of trailing inactivity per tab; tab-set + focus changes write immediately.
- [ ] **NF4.** **No async on launch path.** Local tabs restore synchronously. PM tabs restore asynchronously (the connector fetch is already async), but the UI doesn't block — restored PM tabs appear as their fetches resolve. Focus is set as soon as the focused-tab's content lands, or immediately if the focused tab is local.
- [ ] **NF5.** **No security-scoped surprises.** Restored local tabs that fall outside the workspace root use existing security-scoped bookmark resolution (already in place via `SecurityScopedBookmarkStore`). v1 does **not** add new bookmark entries per recent file — files outside the workspace root that lose access simply become "unavailable" per F5/F12.
- [ ] **NF6.** **Accessibility:** every menu item carries `accessibilityIdentifier`. New identifiers go in `AccessibilityIdentifiers`. Naming pattern: `fileMenuOpenRecent`, `fileMenuOpenRecentItem_<index>`, `fileMenuOpenRecentClear`, `fileMenuOpenRecentFoldersHeader`.

---

## 3. Design

### Approach

Add a single new service, `RecentItemsStore`, that owns both the MRU list and the session-restore record. A `RecentEntry` is the unit of storage; the `SessionState` references entries by ID so the menu and the restore path don't drift.

`WorkspaceStore` calls into `RecentItemsStore` on:
- `tabs.open(fileURL:)` / `tabs.openFromConnector(...)` → record / promote an entry.
- `setRoot(url:)` → record / promote a folder entry.
- `tabs.documents` / `tabs.focusedIndex` changes → persist `SessionState` (debounced).
- editor scroll changes → debounced scroll-line update on the matching entry (channel TBD in plan, but the source of truth is the existing `pendingFocusTarget` / coordinator surface from D9).

`MdEditorApp.commands` gains a new `CommandGroup(after: .newItem)` that renders the `Open Recent` submenu by reading the published `RecentItemsStore.entries`.

### Key Components

| Component | Purpose |
|-----------|---------|
| `RecentItemsStore` (new, `Sources/Workspace/RecentItemsStore.swift`) | Singleton `ObservableObject`. Owns `[RecentEntry]` (files), `[RecentFolderEntry]`, and `SessionState`. UserDefaults-backed JSON. Provides `recordOpen`, `recordFolder`, `clear`, `entriesForMenu` (filtered + decorated), `sessionState`, `updateSessionState`. |
| `RecentEntry` (new, same file) | Codable. `id: UUID`, `kind: .local(URL)` or `.portableMind(connectorID, fileID, displayPath, name, lastSeenUpdatedAt?)`, `addedAt: Date`. |
| `RecentFolderEntry` (new) | Codable. `url: URL` (resolved from bookmark on read), `addedAt: Date`. Path-only; bookmark resolution lives in `SecurityScopedBookmarkStore` already. |
| `SessionState` (new) | Codable. `openTabs: [RecentEntry.ID]`, `focusedTab: RecentEntry.ID?`, `scrollLines: [RecentEntry.ID: Int]`. `schemaVersion: Int = 1`. |
| `OpenRecentMenu` (new SwiftUI view, in `MdEditorApp.swift` or `Sources/App/OpenRecentMenu.swift`) | Reads `RecentItemsStore.entries`; renders the submenu including disabled/availability state, divider, "Recent Folders", "Clear Menu". |
| `WorkspaceStore` (modified) | `restorePersistedTabs()` replaced by `restoreSession()` that consults `RecentItemsStore.sessionState`. New `openRecentEntry(_:)` opens an entry via the right path. Adds scroll-line publisher subscription (mechanism in plan). |
| `TabStore` (modified) | No public-API change. Internal: emits a "tabs changed" signal (already does via `@Published`). |
| `EditorContainer` / coordinator (modified) | Publish current scroll line per focused tab to `WorkspaceStore.sessionScrollLineDidChange(docID:line:)`. Implementation detail in plan §Phase 3. |
| `AccessibilityIdentifiers` (modified) | Add identifiers from NF6. |

### Data Model

```swift
struct RecentEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var addedAt: Date
    var kind: Kind

    enum Kind: Codable, Hashable {
        case local(path: String)                 // POSIX path
        case portableMind(connectorID: String,
                          fileID: Int,
                          displayPath: String,
                          name: String,
                          lastSeenUpdatedAt: Date?)
    }
}

struct RecentFolderEntry: Codable, Hashable {
    let path: String
    var addedAt: Date
}

struct SessionState: Codable {
    var schemaVersion: Int = 1
    var openTabs: [UUID]                         // RecentEntry.id, in tab order
    var focusedTab: UUID?
    var scrollLines: [UUID: Int]                 // 1-based, clamped on restore
}
```

UserDefaults keys (all under `ai.portablemind.md-editor`):

| Key | Value |
|-----|-------|
| `recent.entries.v1` | `Data` — JSON of `[RecentEntry]`, capped at 15 |
| `recent.folders.v1` | `Data` — JSON of `[RecentFolderEntry]`, capped at 5 |
| `session.state.v1` | `Data` — JSON of `SessionState` |

The previous `openTabs` / `focusedTabIndex` keys are read once on first launch under the new build and migrated into `session.state.v1` (best-effort: local tabs become entries; missing files are dropped silently). Old keys are then deleted.

### API

```swift
@MainActor
final class RecentItemsStore: ObservableObject {
    static let shared: RecentItemsStore

    @Published private(set) var entries: [RecentEntry]            // files, newest first
    @Published private(set) var folders: [RecentFolderEntry]      // newest first

    func recordOpen(localURL: URL)
    func recordOpen(connectorID: String,
                    fileID: Int,
                    displayPath: String,
                    name: String,
                    lastSeenUpdatedAt: Date?)
    func recordFolder(_ url: URL)
    func entry(for id: UUID) -> RecentEntry?
    func clear()                                                  // wipes entries + folders + session

    // Session state — separate accessors so menu and restore don't entangle.
    var sessionState: SessionState
    func updateSessionState(openTabIDs: [UUID], focusedTabID: UUID?)
    func recordScrollLine(_ line: Int, for entryID: UUID)         // debounced internally
}
```

`WorkspaceStore` additions:

```swift
func restoreSession() async       // replaces restorePersistedTabs(); called from restoreFromBookmarks()
func openRecentEntry(_ entry: RecentEntry) async   // dispatched by the menu
func openRecentFolder(_ folder: RecentFolderEntry)
```

### Open Recent menu shape

```
File
  Open…                                  ⌘O
  Open Folder…                          ⌘⇧O
  Open Recent                            ▶ ── Untitled.md
                                            scratch.md
                                            test-sample.md  · portablemind
                                            … (up to 15)
                                            ──────────────
                                            Recent Folders
                                            ~/src/apps/md-editor-mac
                                            ~/src/notes
                                            ──────────────
                                            Clear Menu
  New PortableMind File…               ⌘⌥N
```

---

## 4. Success Criteria

- [ ] **SC1.** Opening a local file, then a PM file, then relaunching, lands both tabs back in the same order, with the previously-focused tab focused, scrolled to the same line (±1 line tolerance for end-of-document edge).
- [ ] **SC2.** `File → Open Recent` lists those two files (most-recent first), plus the workspace folder under "Recent Folders".
- [ ] **SC3.** Deleting the local file on disk → relaunch → its tab is silently skipped on restore; its MRU entry shows greyed out with "(unavailable)" suffix; selecting it is a no-op.
- [ ] **SC4.** Clearing the PM token (Debug → Clear) → its MRU entry shows greyed out (no connector); restoring the token re-enables it; clicking re-opens normally.
- [ ] **SC5.** Opening the 16th distinct file evicts the oldest from the list (LRU cap honored).
- [ ] **SC6.** "Clear Menu" empties both `Open Recent` sections and the session record.
- [ ] **SC7.** First-launch (deleted defaults domain): app opens cleanly, empty MRU submenu shows `(No Recent Files)` placeholder, no crash, no error.
- [ ] **SC8.** Migration smoke: a defaults file with only the old `openTabs` / `focusedTabIndex` keys produces a restored session with those local tabs and no MRU entries (the old store had no MRU concept).
- [ ] **SC9.** XCUITest covers SC1, SC5, SC6, SC7 (the deterministic, no-PM cases). PM cases (SC2/SC3/SC4) are in the manual test plan.
- [ ] **SC10.** XCTest covers `RecentItemsStore` (LRU eviction, dedup, JSON round-trip, schema-version skip, migration from old keys).

---

## 5. Out of Scope

- **Dirty-buffer preservation across quit.** A tab with unsaved changes still loses those changes at quit. Following Xcode/VS Code requires a swap-file machinery worth its own deliverable; not bundled here. Confirmed with CD 2026-05-15.
- **Per-tab scroll position beyond line index.** Sub-line scroll (vertical pixel offset within a line) and horizontal scroll are not restored. Line-level granularity is the v1 commitment.
- **Selection / caret restoration.** D9's `pendingFocusTarget` already exists for explicit caret placement on open; v1 of restore does not save+replay the caret position.
- **Recent items shared across windows / Mac instances.** Single-window app today; cross-window sync would require its own design. iCloud sync is not in scope.
- **Drag-drop to add to MRU.** Drag-drop opens aren't supported today; when they are, F2 covers them automatically.
- **MRU surfaced anywhere besides the File menu.** No "Welcome" / start-page surface in v1. (Roadmap candidate.)
- **`Show in Finder` / `Reveal in File Tree` on MRU items.** D25 provides Reveal-in-Tree on open tabs; could extend later.
- **PM connector login from the MRU item itself.** If the PM connector isn't loaded, the item is disabled with a tooltip suggesting the Debug menu (or post-D20, the connection-management UI). v1 does not auto-prompt for sign-in.

---

## 6. Open Questions

- [ ] **OQ1.** Should the MRU cap (15 files, 5 folders) be a hidden UserDefaults knob? *Default position:* no — hard-code v1; revisit if dogfood surfaces a need.
- [ ] **OQ2.** Should "Recent Folders" live in a separate `File → Open Recent Folder` menu rather than a sub-section? *Default position:* sub-section keeps the discovery in one place; revisit if menu length becomes a complaint.
- [ ] **OQ3.** What happens if a PM `RecentEntry` is selected while the connector is loaded but the file has been deleted server-side? *Default position:* attempt `connector.openFile(node)`; on `ConnectorError` show the same alert WorkspaceView.handleSelect shows today; leave the MRU entry in place (next menu rebuild will re-check existence — but we don't poll the server eagerly).
- [ ] **OQ4.** Scroll-line capture mechanism — does the editor coordinator already publish first-visible-line, or do we need to expose it? *Default position:* if exposed, use it; if not, add a small `firstVisibleLine` publisher on the editor coordinator. Resolved in plan §Phase 3.
- [ ] **OQ5.** Should the migration from old keys also try to find a `RecentEntry` to attach the old `focusedTabIndex` to? *Default position:* migrate tabs to restored session only (no MRU entries created retroactively for old tabs that aren't still restorable); old `focusedTabIndex` becomes the `focusedTab` ID of whichever migrated tab lands at that index, or nil if out of range.

---

## 7. Extension Strategy

Captured per memory `feedback_extension_strategy.md` — what we're intentionally narrowing in v1 and how v1.1+ would broaden:

| Narrowing | Trigger to revisit | Expansion path | Refactor risk |
|---|---|---|---|
| Dirty-buffer not preserved | Dogfood complaint or data-loss incident | Add `SwapBufferStore` writing to `~/Library/Application Support/.../swap/<entryID>.md`; restore reads swap first, falls through to on-disk | Low — additive; `EditorDocument.lastSavedSource` already tracks the baseline |
| Line-only scroll granularity | Long-form docs feel "off" on restore | Persist `(line, intraLineOffset)`; restore computes line first then scrolls by offset | Low — additive field on `SessionState.scrollLines` value type |
| Single-window only | Multi-window (multiple workspaces) lands | Move `SessionState` from one record to `[WindowID: SessionState]`; window restoration replays each | Medium — `WorkspaceStore` would need to become non-singleton |
| MRU only in File menu | Welcome / start-page deliverable | Read same `RecentItemsStore.entries`; render in a Welcome view | None — read-only consumer |
| PM connector required for PM-item open | Connection-management UX (D20) | MRU item click could trigger D20's sign-in flow when matching connector is absent | Low — gated path |
| Per-recent-file security-scoped bookmarks | User complaints about files outside workspace root losing access on restore | Add bookmark per entry on first open; resolve on restore; fall through to "unavailable" if resolution fails | Medium — adds bookmark lifecycle to `RecentItemsStore` |

---

## 8. Engineering Standards Compliance

- [x] Accessibility identifiers (NF6).
- [x] No `NSTextView.layoutManager` access (no editor-internals work).
- [x] Sandbox-safe source — UserDefaults only.
- [x] Foundation trace (vision principle 1).
- [x] Persistence rule (testing.md): success criteria SC1 + SC10 require a full open → quit → restore round-trip, not just in-memory state.
- [x] Branch hygiene (memory `feedback_branch_hygiene_pre_commit.md`): all work on `feature/d31-mru-and-session-restore`.
