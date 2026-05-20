# D31: Open Recent + Session Restore — Implementation Plan

**Spec:** `d31_mru_and_session_restore_spec.md`
**Created:** 2026-05-15
**Branch:** `feature/d31-mru-and-session-restore` (already cut off `main`)

---

## Overview

Add `RecentItemsStore`, replace the partial tab-persistence in `WorkspaceStore` with a session-state record that includes PM tabs and scroll lines, and surface MRU files + folders in `File → Open Recent`. Five sequential phases plus a close-out phase.

Estimated diff: ~600 LOC production + ~400 LOC tests.

---

## Prerequisites

- [x] Feature branch cut.
- [x] Spec approved.
- [ ] PM token present in Keychain (only needed for §Phase 4 PM-tab dogfood).

---

## Implementation Phases

### Phase 1 — `RecentItemsStore` foundation (no UI yet)

**Files:**
- `Sources/Workspace/RecentItemsStore.swift` (new)
- `Tests/RecentItemsStoreTests.swift` (new — XCTest target)

**Work:**
1. Define `RecentEntry`, `RecentEntry.Kind`, `RecentFolderEntry`, `SessionState` as Codable structs per spec §3 Data Model.
2. Implement `RecentItemsStore` singleton:
   - In-memory state initialized from UserDefaults JSON on `init`.
   - `recordOpen(localURL:)` and `recordOpen(connectorID:fileID:...)` — find-or-create entry, set `addedAt = Date()`, move to head, truncate to 15.
   - `recordFolder(_:)` — same shape, cap 5.
   - `clear()` — wipes entries + folders + session, calls `synchronize`.
   - JSON round-trip via `JSONEncoder` / `JSONDecoder`.
   - Schema-version gate on decode: if `schemaVersion > 1`, return defaults (don't crash, don't migrate).
3. UserDefaults keys exactly as spec §3.
4. Migration: on first `init` post-upgrade, check for legacy `openTabs` (`[String]`) + `focusedTabIndex` (`Int`). If present, build a `SessionState` with local entries for files that still exist, then delete legacy keys.

**Tests** (`RecentItemsStoreTests.swift`):
- Empty defaults → empty state, no crash.
- Record two local files → entries newest-first, correct addedAt ordering.
- Record same file twice → de-dup, addedAt updated.
- Record 16 files → cap honored, oldest evicted.
- Record local + PM with overlapping displayPath → distinct entries.
- Round-trip JSON: encode → decode → fields equal.
- Schema-version 2 on disk → store reads as empty, doesn't crash.
- Migration: seed legacy keys → init → entries are populated from existing files, missing files are dropped, legacy keys are gone.
- `clear()` → all three keys removed.

**Definition of done:** XCTests green; `RecentItemsStore.shared.entries` populates from a manual call in a debug breakpoint. No app-facing change yet.

---

### Phase 2 — Wire `RecentItemsStore` to opens (no menu yet)

**Files:**
- `Sources/Workspace/WorkspaceStore.swift` (modify)
- `Sources/Workspace/TabStore.swift` (modify — minimal)

**Work:**
1. In `WorkspaceStore.init`, subscribe to `tabs.$documents` and on each newly-opened doc, call `RecentItemsStore.shared.recordOpen(...)`. Detect "new" via set-difference against the prior snapshot (no churn-recording on close).
2. Local opens flow via `tabs.open(fileURL:)` — the document's `url` is set, easy `recordOpen(localURL:)`.
3. PM opens flow via `tabs.openFromConnector(content:node:)` — pull `(connectorID, fileID, displayPath, name, lastSeenUpdatedAt)` off the `EditorDocument.origin` + `connectorNode`.
4. In `WorkspaceStore.setRoot(url:persistBookmark:...)`, after a successful bookmark save call `RecentItemsStore.shared.recordFolder(url)`.
5. Remove the existing `persistTabs()` / `restorePersistedTabs()` calls (they get replaced in Phase 5; leave the methods in place for one phase so Phase 3-4 work doesn't break behavior).

**Tests:**
- Manual smoke: opening a local file via sidebar → `RecentItemsStore.shared.entries` contains it (verified via a debug-only HUD log or breakpoint).
- Existing tests stay green.

**Definition of done:** Opens are recorded; nothing about restore behavior changes yet.

---

### Phase 3 — Scroll-line capture publisher

**Files:**
- `Sources/Editor/EditorContainer.swift` (modify)
- `Sources/Workspace/WorkspaceStore.swift` (add `sessionScrollLineDidChange(docID:line:)`)

**Work:**
1. In `EditorContainer.Coordinator`, observe `NSView.boundsDidChangeNotification` on the scroll view's `contentView` (the existing pattern used by the line-number ruler — see `LineNumberRulerView`).
2. On bounds change, compute first-visible line:
   ```swift
   let visibleRect = scrollView.documentVisibleRect
   let topPoint = NSPoint(x: 0, y: visibleRect.origin.y)
   let charIndex = textView.characterIndexForInsertion(at: topPoint)
   let line = textView.string.lineNumber(forCharacterIndex: charIndex)  // 1-based
   ```
   `String.lineNumber(forCharacterIndex:)` and `String.nsLocation(forLine:column:)` (the inverse, used by D9) already live in `Sources/Support`. If not, add `lineNumber` as the inverse.
3. Debounce 500ms (matches spec NF3). Use the existing `DispatchWorkItem` pattern in the codebase (see `EditorContainer` reflow debounce).
4. On settle, call `WorkspaceStore.shared.sessionScrollLineDidChange(docID: document.id, line: line)`.
5. `WorkspaceStore.sessionScrollLineDidChange` forwards to `RecentItemsStore.shared.recordScrollLine(_:for:)` — but the `RecentEntry.id` isn't the `EditorDocument.id`. Resolve the entry by matching kind:
   - Local: by `url`.
   - PM: by `(connectorID, fileID)`.
   Cache the lookup result on the `EditorDocument` (private `lazy var recentEntryID: UUID?`) to avoid per-bounds-change overhead.

**OQ4 resolution:** the editor does not currently expose first-visible-line; this phase adds it. Mechanism above. No new dependency on `NSTextView.layoutManager` (we use the public `characterIndexForInsertion(at:)`).

**Tests:**
- XCTest: a `String.lineNumber(forCharacterIndex:)` round-trip with `nsLocation(forLine:column:)` for several documents (multibyte chars, trailing newline, empty doc).
- Manual: scroll a doc, watch `RecentItemsStore.shared.sessionState.scrollLines` update after debounce.

**Definition of done:** Scroll lines are captured for the focused tab and persisted; verified by reading UserDefaults between scroll + quit.

---

### Phase 4 — Session restore on launch

**Files:**
- `Sources/Workspace/WorkspaceStore.swift` (replace `restorePersistedTabs` with `restoreSession`)

**Work:**
1. New `func restoreSession() async` called from `restoreFromBookmarks()` (which becomes async, or wraps in a `Task`). Reads `RecentItemsStore.shared.sessionState`.
2. For each `openTabs` entry ID, resolve the `RecentEntry`:
   - **Local kind:** if `FileManager.default.fileExists(atPath: path)`, call `tabs.open(fileURL:)` synchronously. Set `pendingFocusTarget = .caret(line: scrollLines[id] ?? 1, column: 0)` on the resulting doc.
   - **PM kind:** find a `PortableMindConnector` in `connectors` by `connectorID`. If absent, skip silently. If present, construct a minimal `ConnectorNode` with the persisted `(id, name, path, lastSeenUpdatedAt)`, async `connector.openFile(node)`, then `tabs.openFromConnector(content:node:)`, then set `pendingFocusTarget` to the scroll line.
3. After all sync (local) tabs are appended in order, set `tabs.focusedIndex` from `focusedTab` (resolve ID → current array index). PM tabs that land later don't disturb focus unless the focused tab was PM — in that case, defer focus assignment until that fetch resolves.
4. The recording subscription from Phase 2 fires during restore — gate it so restore-time opens don't re-record (a `private var isRestoring = false` flag on `WorkspaceStore`).
5. Delete the legacy `openTabsKey` / `focusedTabIndexKey` constants from `WorkspaceStore`; their migration was done in Phase 1's `RecentItemsStore` init.

**Tests:**
- Manual round-trip on local: open 2 local files, scroll the second to line 50, focus the second, quit, relaunch → both tabs back, second focused, second at line 50.
- Manual round-trip on PM: same with PM tabs (requires PM token present).
- Mixed: 1 local + 1 PM, quit, relaunch → both restored.
- Failure: rm the local file between quit and relaunch → the local tab is silently skipped; the other tab still focuses correctly.

**Definition of done:** §4 SC1, SC8 verified manually; one XCUITest covering local-only round-trip (PM round-trip is manual per spec SC9).

---

### Phase 5 — `Open Recent` menu

**Files:**
- `Sources/App/MdEditorApp.swift` (add command group)
- `Sources/App/OpenRecentMenu.swift` (new — the submenu view, kept in its own file for readability)
- `Sources/Accessibility/AccessibilityIdentifiers.swift` (add NF6 identifiers)

**Work:**
1. Add a new `CommandGroup(after: .newItem)` (after the existing "Open Folder…" group) that renders `Menu("Open Recent") { OpenRecentMenu() }`.
2. `OpenRecentMenu` is a SwiftUI view holding `@ObservedObject var store = RecentItemsStore.shared` and `@EnvironmentObject var workspace: WorkspaceStore`.
3. Render:
   - For each `RecentEntry`: `Button(entry.name) { Task { await workspace.openRecentEntry(entry) } }` with `.help(entry.tooltip)` and `.disabled(!entry.isAvailable(connectors:))`.
   - `Divider()` if any folders exist, then a non-interactive `Text("Recent Folders")` (styled as a section header — SwiftUI `Section { ... } header:` if Menu supports it; else a disabled label).
   - For each `RecentFolderEntry`: `Button(folder.displayName) { workspace.openRecentFolder(folder) }` with the home-relative tooltip.
   - `Divider()` then `Button("Clear Menu") { store.clear() }`.
   - Empty state: if zero files and zero folders, a single disabled `Text("(No Recent Files)")`.
4. Implement `RecentEntry.isAvailable(connectors:)`:
   - Local → `FileManager.default.fileExists(atPath: path)`.
   - PM → connector with matching `connectorID` present.
5. Implement `workspace.openRecentEntry(_:)` — drives the same path as Phase 4 restore for a single entry (extract a private helper used by both).
6. Implement `workspace.openRecentFolder(_:)` — calls `setRoot(url:)` (PM Welcome-style first-resolve handled by `SecurityScopedBookmarkStore` if applicable; for v1 just `setRoot` directly — entries the user can't access become "unavailable" on next attempt; flagged in spec NF5).
7. Accessibility identifiers per NF6.

**Tests:**
- XCUITest: open File menu → assert `Open Recent` submenu exists and contains the expected entry titles.
- XCUITest: open a file, then `File → Open Recent → <that file>` → tab opens.
- XCUITest: `Clear Menu` → `Open Recent` submenu now shows `(No Recent Files)`.
- Manual: PM-item rendering (badge / connector suffix in tooltip), disabled state when token cleared.

**Definition of done:** Spec §4 SC1, SC2, SC5, SC6, SC7 all green; SC3 + SC4 manual.

---

### Phase 6 — Close-out

**Work:**
1. `docs/current_work/testing/d31_mru_and_session_restore_manual_test_plan.md` — paired with the spec; covers SC3 (deleted file), SC4 (cleared token), SC6 (Clear Menu), SC8 (migration), and the mixed local+PM round-trip.
2. `docs/current_work/stepwise_results/d31_mru_and_session_restore_COMPLETE.md` — what shipped, deferred items, dogfood notes.
3. Update `docs/roadmap_ref.md`: D31 row → `✅ Complete — YYYY-MM-DD (feature/d31-mru-and-session-restore)`.
4. Branch merge to `main`; delete local + remote feature branch.
5. Memory: write `md_editor_session_2026-05-15.md` summarizing D31 shipment.

---

## Testing strategy

**Automated:**
- XCTest: `RecentItemsStore` (Phase 1) and the `String` line-number helpers (Phase 3) — both fast, no UI.
- XCUITest: menu surface (Phase 5) and a local-only restore round-trip (Phase 4).

**Manual:** PM-tab cases (no PM test infra in CI), error states (deleted file, cleared token), migration smoke (requires a seeded UserDefaults; covered by the test plan).

**Harness:** the existing `HarnessCommandPoller` already exposes `synthesize_keypress`, `synthesize_menu_action`, and tab-state introspection. Add a `dump_recent_items` action that returns the current `RecentItemsStore.entries` as JSON — needed for negative-assertion tests in Phase 4/5 ("entry X is *not* in the menu after Clear").

**Focus-stealing protocol** (per `memory/feedback_focus_stealing.md`, broadened 2026-05-15): ask before any `xcodebuild test` run or app launch. Harness-driven verification first; XCUITests only with permission.

---

## Verification checklist

- [ ] All 6 phases complete on branch.
- [ ] Spec SC1-SC8, SC10 verified.
- [ ] SC9 (XCUITest coverage of SC1/SC5/SC6/SC7) green.
- [ ] Manual test plan walked end-to-end.
- [ ] COMPLETE doc written.
- [ ] Roadmap updated.
- [ ] Branch merged to `main`, local + remote cleaned up.

---

## Notes

- **Focus-target on restore (Phase 4):** D9's `EditorFocusTarget.caret(line, column)` is the existing primitive. Setting `pendingFocusTarget = .caret(line, 0)` triggers `scheduleApply` which calls `scrollRangeToVisible`. This is exactly the same path the CLI uses for `md-editor file.md:42`. No new primitive needed.
- **Don't persist to UserDefaults on every scroll tick.** The 500ms debounce (Phase 3) is load-bearing; without it, fast scrolling burns IO. Verify with `defaults read` between phases.
- **Connector ID lookup (Phase 4 + 5):** `WorkspaceStore.connectors` is the source. PM connector ID is `"portablemind"` (single connector in v1); local is `"local"`. No registry needed — direct match.
- **Old keys cleanup:** Phase 1's `init` migrates and deletes `openTabs` + `focusedTabIndex`. Phase 4 deletes the in-code constants. Don't leave the read path live in two places.
- **Naming:** `RecentItemsStore` not `RecentFilesStore` because it also holds folders. Keeps the API surface honest.
