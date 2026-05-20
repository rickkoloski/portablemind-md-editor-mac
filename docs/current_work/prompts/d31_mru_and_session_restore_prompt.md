# D31: Open Recent + Session Restore — CC Prompt

**Spec:** `docs/current_work/specs/d31_mru_and_session_restore_spec.md`
**Plan:** `docs/current_work/planning/d31_mru_and_session_restore_plan.md`
**Branch:** `feature/d31-mru-and-session-restore` (already cut off `main`)

---

## Context

md-editor-mac currently persists open tabs partially (local URLs only, no PM tabs, no scroll position) and has no `File → Open Recent` menu. D31 bundles a real MRU list plus a complete session restore (open tabs, focused tab, first-visible scroll line) — local **and** PortableMind origins both participate.

The spec is approved with all three CD decisions captured:
- **Bundled scope** (MRU + restore in one deliverable).
- **PM tabs in** (persist by `connectorID + fileID`, reconstruct a minimal `ConnectorNode` on restore).
- **Scroll-line fidelity** (1-based line index, not pixel offset; dirty buffers explicitly NOT preserved).

The spec calls out three live defects in today's partial implementation that this deliverable fixes:
1. PM tabs dropped silently on restore (only `url?.path` is persisted at `Sources/Workspace/WorkspaceStore.swift:191`).
2. `focusedIndex` collapsed to 0 when key is absent (`UserDefaults.integer(forKey:)` returns 0 on miss).
3. No scroll restore.

**Key files to study before you touch anything:**

| File | Why |
|------|-----|
| `Sources/Workspace/WorkspaceStore.swift` | Owns root, connectors, the current partial persist/restore. Most of the deliverable's edits land here. |
| `Sources/Workspace/TabStore.swift` | `open(fileURL:)`, `openFromConnector(content:node:)`, `focusedIndex`. PM origin shape lives in `Self.origin(for:)`. |
| `Sources/Workspace/EditorDocument.swift` | `Origin` enum (.local vs .portableMind), `connectorNode`. The data you need to record on PM opens lives here. |
| `Sources/Connectors/Connector.swift` | `Connector` protocol, `ConnectorNode` struct. You will reconstruct a minimal `ConnectorNode` on PM restore. |
| `Sources/WorkspaceUI/WorkspaceView.swift:101-122` | `handleSelect` — the canonical local + PM open path. Mirror this in `WorkspaceStore.openRecentEntry`. |
| `Sources/App/MdEditorApp.swift:107-159` | The `.commands { … }` block where `Open Recent` goes (after the existing `Open Folder…` group). |
| `Sources/Editor/EditorContainer.swift` | Where the scroll-line publisher (Phase 3) lives. D9's `pendingFocusTarget` (line 217) is the writeback path on restore. |
| `Sources/Editor/LineNumberRulerView.swift` | Precedent for `boundsDidChangeNotification` on `scrollView.contentView`. Follow this pattern. |

**Related deliverables:** D6 (workspace foundation), D9 (`pendingFocusTarget` / `EditorFocusTarget.caret`), D14 (Save), D18 (Connector + PM tabs), D19 (PM save-back, `connectorNode` lifecycle), D21 (home-relative path tooltip convention), D30 (the `RecentItemsStore` pattern is similar to `HeartbeatPruner`'s store — durable UserDefaults-backed observable).

---

## Task

Follow the plan's six phases in order. Do not collapse phases — each one has its own DOD and verification step.

### Phase 1 — `RecentItemsStore` foundation
Per plan §Phase 1. Create the store + types + tests. No app-facing change yet. Migration of legacy `openTabs` / `focusedTabIndex` UserDefaults keys happens here.

### Phase 2 — Wire recording to opens
Per plan §Phase 2. Subscribe `WorkspaceStore` to `tabs.$documents` for new-doc detection. Record local opens and PM opens. Record folder opens in `setRoot`. Do NOT remove the old `restorePersistedTabs()` yet (it gets replaced in Phase 4).

### Phase 3 — Scroll-line capture
Per plan §Phase 3. New observer on `scrollView.contentView` `boundsDidChangeNotification` in `EditorContainer.Coordinator`. Compute first-visible line via `characterIndexForInsertion(at:)` + a `String.lineNumber(forCharacterIndex:)` helper (the inverse of D9's existing `nsLocation(forLine:column:)`). 500ms debounce. Forward to `WorkspaceStore.sessionScrollLineDidChange(docID:line:)`, which resolves the `RecentEntry.id` from the doc's `origin` and updates the store.

### Phase 4 — Session restore on launch
Per plan §Phase 4. Replace `restorePersistedTabs()` with `restoreSession() async`. Set `isRestoring = true` while restoring so the Phase 2 subscription doesn't re-record. Local tabs synchronous; PM tabs async via the existing connector path. Focus assignment defers if focused tab is PM. Use `pendingFocusTarget = .caret(line: N, column: 0)` to restore scroll line — this is exactly D9's CLI path.

### Phase 5 — `Open Recent` menu
Per plan §Phase 5. New `Sources/App/OpenRecentMenu.swift` view. Add to `.commands { … }` block after the existing `Open Folder…` `CommandGroup(after: .newItem)`. Files section → divider → "Recent Folders" header + folders → divider → "Clear Menu". Empty state: `(No Recent Files)`. Disabled-state per spec F5 (unavailable file or missing PM connector).

### Phase 6 — Close-out
Per plan §Phase 6. Manual test plan, COMPLETE doc, roadmap update, branch merge.

---

## Decisions already locked (do not re-litigate)

| Decision | Source |
|---|---|
| Bundled scope: MRU + restore in one deliverable | CD 2026-05-15 (spec §1) |
| PM tabs participate in both MRU and restore | CD 2026-05-15 (spec §2 F2/F9, §3) |
| Scroll-line granularity (not pixel offset) | CD 2026-05-15 (spec F11, §5) |
| Dirty buffers NOT preserved | CD 2026-05-15 (spec F14, §5) |
| MRU cap: 15 files, 5 folders (hard-coded) | Spec OQ1 default position |
| Recent Folders as a sub-section of `Open Recent` (not a separate menu) | Spec OQ2 default position |
| Unavailable items stay in list, disabled | Spec F5 |
| `UserDefaults` persistence, JSON values, schema-versioned | Spec NF1, NF2 |
| Single `RecentItemsStore` singleton owns both MRU and SessionState | Spec §3 + plan rationale |

If the implementation surfaces a real reason to revisit any of these, **stop and ask** — do not silently deviate. Use the spec's `## Decisions` table convention to record any change (per `feedback_answered_questions_decision_table.md`).

---

## Constraints

- **Branch:** `feature/d31-mru-and-session-restore`. Verify with `git branch --show-current` before every commit (`feedback_branch_hygiene_pre_commit.md`).
- **Engineering standards** (`docs/engineering-standards_ref.md`):
  - Never touch `NSTextView.layoutManager` — Phase 3 uses public `characterIndexForInsertion(at:)`, not the layout manager.
  - Accessibility identifiers on every interactive view (spec NF6 names).
  - Sandbox-safe — UserDefaults only; no new file writes outside `Application Support` (none needed in this deliverable).
- **No `NSDocumentController` `recent*` APIs.** This app is not document-architecture; rolling our own is correct.
- **No new dependencies.** Codable + UserDefaults + Combine cover it.
- **Existing `openTabs` / `focusedTabIndexKey` UserDefaults keys** must be migrated then deleted by Phase 4. Don't leave two read paths live.
- **Don't persist scroll line on every tick.** 500ms debounce is load-bearing (spec NF3).
- **Test discipline** (`feedback_testing_discipline_signals.md` + `feedback_blackbox_first_testing.md`): full open → quit → restore round-trip is required for SC1 (persistence rule). In-memory state alone is not verification.
- **Focus-stealing protocol** (`feedback_focus_stealing.md`, broadened 2026-05-15 for parallel sessions): **ASK before any `xcodebuild test` run or app launch** — Rick is working in multiple sessions at once and any XCUITest or app-launch grabs the screen. Default to harness-driven verification. Pure `xcodebuild build` is fine without asking; tests + launches are not.
- **PM-tab dogfood** requires the PM token present in the Keychain. If not present when you reach Phase 4 PM verification, ask Rick to set it via the Debug menu rather than running the verification against a missing connector.

---

## Open questions to resolve in-flight (with default positions)

The spec leaves these in §6 with default positions you can act on, but flag if you find evidence to change them:

- **OQ3** — PM file deleted server-side at MRU click → mirror `WorkspaceView.handleSelect`'s error alert; leave the MRU entry in place.
- **OQ4** — Scroll-line capture mechanism → resolved in plan §Phase 3 (boundsDidChange observer). Verify the mechanism works against TextKit 1 NSTextTable docs (D17) — they should be fine since `characterIndexForInsertion(at:)` is layout-system-agnostic.
- **OQ5** — Migration of `focusedTabIndex` → migrate to `focusedTab: UUID` mapped via the restored entries' order; out-of-range → `nil`.

OQ1 and OQ2 are locked (Decisions table above).

---

## Success criteria

All ten spec §4 SCs:

- [ ] SC1: Local + PM round-trip (tabs, focus, scroll line ±1)
- [ ] SC2: Both files in `Open Recent`; workspace folder under "Recent Folders"
- [ ] SC3: Deleted local file → silent skip on restore; disabled "(unavailable)" entry in menu
- [ ] SC4: Cleared PM token → disabled entry; restored token re-enables; click re-opens
- [ ] SC5: 16th file evicts oldest (LRU cap)
- [ ] SC6: "Clear Menu" empties both sections + session record
- [ ] SC7: First-launch / wiped defaults → empty submenu with `(No Recent Files)` placeholder, no crash
- [ ] SC8: Migration from legacy keys — local tabs restore, no MRU entries created retroactively
- [ ] SC9: XCUITest covers SC1, SC5, SC6, SC7 (deterministic, no-PM cases)
- [ ] SC10: XCTest covers `RecentItemsStore` (LRU, dedup, JSON round-trip, schema-version skip, migration)

Plus the verification checklist in plan §Verification.

---

## On completion

1. Write `docs/current_work/stepwise_results/d31_mru_and_session_restore_COMPLETE.md` per template — what shipped, files touched, deviations from spec, deferred items (any that surfaced during build), dogfood notes.
2. Write `docs/current_work/testing/d31_mru_and_session_restore_manual_test_plan.md` covering SC3 (deleted file), SC4 (cleared token), SC6 (Clear Menu), SC8 (migration), and the mixed local+PM round-trip. Include a one-paste harness recipe per `feedback_pipeline_trace_as_pattern.md` style.
3. Update `docs/roadmap_ref.md` D31 row → `✅ Complete — YYYY-MM-DD (feature/d31-mru-and-session-restore)`.
4. Merge `feature/d31-mru-and-session-restore` to `main`. Delete local + remote feature branch (per memory `md_editor_session_2026-04-28b.md` conventions section).
5. Save `md_editor_session_2026-05-15.md` (or whatever today's date is on completion) summarizing D31 shipment + any findings worth carrying forward into the next deliverable.

---

## Reference: legacy state to migrate

For Phase 1's migration code:

```swift
// Legacy keys (defined in WorkspaceStore.swift today):
private static let openTabsKey = "openTabs"            // [String] of POSIX paths
private static let focusedTabIndexKey = "focusedTabIndex"  // Int, -1 sentinel for "none"
```

Migrate by reading once on first `RecentItemsStore.init` post-upgrade, then `removeObject(forKey:)` both keys.

---

## Reference: PM origin reconstruction

For Phase 4 PM restore, reconstruct the `ConnectorNode` like this (sketch — verify field names against `Sources/Connectors/Connector.swift:215`):

```swift
let node = ConnectorNode(
    id: "\(connectorID):file:\(fileID)",   // matches PortableMindConnector's id scheme
    name: name,
    path: displayPath,
    kind: .file,
    fileCount: nil,
    tenant: nil,                            // re-resolved on next fetch
    isSupported: true,
    lastSeenUpdatedAt: lastSeenUpdatedAt,
    connector: matchingPortableMindConnector
)
let (bytes, refreshedNode) = try await matchingPortableMindConnector.openFile(node)
let text = String(data: bytes, encoding: .utf8) ?? ""
workspace.tabs.openFromConnector(content: text, node: refreshedNode)
```

The `refreshedNode` from `openFile` carries the current `lastSeenUpdatedAt` and `tenant` — that's what `TabStore.openFromConnector` keys off for D19's conflict-detection baseline. So even though the reconstructed node is minimal, the post-fetch node is full-fidelity.

---

## Reference: don't break

- D9 CLI scroll-to-line (`md-editor file.md:42`) — sets `pendingFocusTarget` directly. Your Phase 4 restore also sets `pendingFocusTarget`. The coordinator's `scheduleApply` handles either source identically; don't add a guard that prevents one path from winning over the other.
- D19 conflict-detection — `connectorNode.lastSeenUpdatedAt` must be the value the server vended on the last successful save/load, not what you reconstructed. Always use the `refreshedNode` from `openFile`, never the minimal one, post-load.
- D30 Submit/Handoff — session interest is on `EditorDocument.interestedSessions`, not the connector. Restoring a tab is a fresh open from interest's perspective (the session that was watching the tab pre-quit is gone). Do not attempt to restore interest state.
- D24.2 responsive table columns — the resize-reflow debounce shares the `EditorContainer` coordinator. Your new bounds-observer is on a different notification (`boundsDidChangeNotification` on contentView, vs `frameDidChangeNotification` on scroll view). They don't collide, but verify both still fire by manual scrolling + resizing during Phase 3 dogfood.
