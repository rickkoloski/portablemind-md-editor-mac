# D31: Open Recent + Session Restore — Complete

**Spec:** `d31_mru_and_session_restore_spec.md`
**Plan:** `d31_mru_and_session_restore_plan.md`
**Branch:** `feature/d31-mru-and-session-restore`
**Completed (code):** 2026-05-15 (dogfood verification pending)

---

## Summary

Shipped `RecentItemsStore` — a UserDefaults-backed, schema-versioned, observable store that owns the Open Recent menu (files + folders) and the session-restore record (open tabs, focused tab, per-tab scroll line). PortableMind tabs participate in both surfaces by `(connectorID, fileID)` identity; scroll lines are captured via a 500ms-debounced bounds-change observer in `EditorContainer.Coordinator` and replayed on restore through D9's existing `pendingFocusTarget` primitive. The legacy partial-persistence in `WorkspaceStore` is gone — its keys are migrated on first launch and the legacy code path is removed.

The user-visible surface is a `File → Open Recent` submenu (15 files max, 5 folders max, divider + section header + Clear Menu). Unavailable entries (missing file or unloaded PM connector) stay listed but disabled with `(unavailable)` suffix. Empty state shows `(No Recent Files)`.

---

## Implementation details

### What was built

- `RecentItemsStore` — singleton ObservableObject; in-memory state mirrored to three UserDefaults keys (`recent.entries.v1`, `recent.folders.v1`, `session.state.v1`); reads schema-versioned; forward versions reset rather than crash.
- `RecentEntry` (local | portableMind kind) with `isAvailable(connectors:)` + `tooltip` + `displayName`; `RecentFolderEntry` with the same shape minus the kind discriminator.
- `SessionState` carrying `openTabs: [UUID]`, `focusedTab: UUID?`, `scrollLines: [UUID: Int]`, `schemaVersion: 1`.
- Legacy key migration (`openTabs`, `focusedTabIndex`) — runs once on first init; preserves focus across dropped (missing-file) tabs by tracking `originalIndex → newEntryID` rather than the post-filter array index.
- `WorkspaceStore` recording subscription on `tabs.$documents` (set-diff against prior snapshot so close + reorder don't re-record); folder recording in `setRoot(persistBookmark: true)` path.
- `WorkspaceStore.restoreSession()` — replaces `restorePersistedTabs()`. Local sync; PM async per-tab; focus + scroll-line assignment deferred until all PM fetches complete so the focused-tab-is-PM case works.
- `isRestoring` gate on the recording + persist subscriptions so rehydrated tabs aren't re-promoted and partial snapshots aren't persisted mid-restore.
- `EditorContainer.Coordinator.attachScrollLineCapture(to:)` — `boundsDidChangeNotification` observer on `scrollView.contentView`; 500ms trailing debounce; reads first-visible line via NSTextView's public `characterIndexForInsertion(at:)` (does **not** touch `layoutManager`); forwards to `WorkspaceStore.sessionScrollLineDidChange(docID:line:)`.
- `String.lineNumber(forCharacterIndex:)` — inverse of D9's existing `nsLocation(forLine:column:)`. Powers scroll-line capture.
- `WorkspaceStore.openRecentEntry(_:)` / `openRecentFolder(_:)` — mirror `WorkspaceView.handleSelect` / `setRoot` so menu selection is indistinguishable from sidebar click.
- `OpenRecentMenu` SwiftUI view (`Sources/App/OpenRecentMenu.swift`) — submenu contents with file items, folder section, Clear Menu, and empty placeholder.
- `--reset-recents` launch arg on `RecentItemsStore.init` — wipes all three D31 keys + the legacy keys before first read. Lets XCUITests (current and future) start from a known-empty state.
- Accessibility identifiers added for the submenu, individual items (positional), folders header, Clear Menu, and empty placeholder.

### Files created

| File | Purpose |
|------|---------|
| `Sources/Workspace/RecentItemsStore.swift` | The store + types (RecentEntry, RecentFolderEntry, SessionState). |
| `Sources/App/OpenRecentMenu.swift` | SwiftUI submenu view. |
| `UnitTests/RecentItemsStoreTests.swift` | 20 XCTests — LRU, dedup, PM identity, scroll clamp + prune, round-trip, schema-skip, Clear, 4 migration cases. |
| `UnitTests/StringLineLocationTests.swift` | 7 XCTests for the new `lineNumber(forCharacterIndex:)` helper + round-trip with the existing `nsLocation`. |
| `UITests/OpenRecentMenuTests.swift` | SC7 XCUITest, drafted but skipped per i03 (SwiftUI Menu AX bridge limitation). |
| `docs/current_work/testing/d31_mru_and_session_restore_manual_test_plan.md` | Section-organized manual test plan. |
| `docs/current_work/stepwise_results/d31_mru_and_session_restore_COMPLETE.md` | This doc. |

### Files modified

| File | Changes |
|------|---------|
| `Sources/Workspace/WorkspaceStore.swift` | Replaced legacy `persistTabs`/`restorePersistedTabs` with the new RecentItemsStore-backed path; added recording subscription with set-diff detection; added `restoreSession`, `openRecentEntry`, `openRecentFolder`, `sessionScrollLineDidChange`; added `isRestoring` + `seenDocumentIDs` private state. |
| `Sources/Editor/EditorContainer.swift` | Added `attachScrollLineCapture(to:)` + `scheduleScrollLineCapture(in:)`; new observer + debounce-task tokens with deinit cleanup. |
| `Sources/Support/StringLineLocation.swift` | Added `lineNumber(forCharacterIndex:)`. |
| `Sources/App/MdEditorApp.swift` | Added `Menu("Open Recent") { OpenRecentMenu(...) }` to the existing `CommandGroup(after: .newItem)` block. |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | Six new identifiers under the D31 section. |

---

## Testing

### Automated tests

- **Unit:** 27 new XCTests, 0 failures. Suite total 72/72 green.
  - `RecentItemsStoreTests`: 20 tests covering LRU eviction (files + folders), de-dup (local + PM), PM display-field refresh on re-record, JSON round-trip through UserDefaults, schema-version skip, scroll-line clamp + orphan pruning, `clear()`, and 4 migration cases (happy path, focus on dropped tab, focus out-of-range, all files missing).
  - `StringLineLocationTests`: 7 tests covering empty string, single-line, multi-line, trailing newline, negative-index clamp, multibyte / emoji UTF-16, and round-trip with the existing `nsLocation` helper.
- **XCUITest:** 1 new test drafted (SC7 empty-state), skipped via `XCTSkip` pointing at i03 — SwiftUI Menu's NSMenu AX bridge does not surface submenu items with their accessibilityIdentifier reliably (two query patterns tried). Same root cause as the existing skipped Mutation tests.
- **Build:** `xcodebuild build` and `xcodebuild build-for-testing` both green.

### Manual testing

**Not yet performed.** Manual test plan committed at `docs/current_work/testing/d31_mru_and_session_restore_manual_test_plan.md` with 8 sections (A–H + I harness recipe). Results table at the bottom for dogfood updates.

### Test coverage strategy

The persistence-rule disciplines (`feedback_testing_standards.md`, `~/src/ops/sdlc/disciplines/testing.md`) are satisfied by the unit-test round-trips through a real UserDefaults suite (not a mock). The SC1 (live restore) and SC2/SC3/SC4 (PM-token states) round-trips are in the manual test plan — automating them requires either harness instrumentation that doesn't exist yet (i03 follow-up) or a full launch-quit-launch XCUITest pattern that runs into the same SwiftUI Menu AX bridge limitation.

---

## Deviations from spec

- **SC9 XCUITest coverage is partial.** Spec called for SC1, SC5, SC6, SC7 in XCUITest. Actual: only SC7 was attempted, and it's skipped per i03. SC1 / SC5 / SC6 are covered by `RecentItemsStoreTests` at the state-machine level (the layer that holds the actual contract) + manual test plan at the user-facing level. The XCUITest infrastructure shipped (`--reset-recents` launch arg, disabled-Button placeholder) is the foundation for re-enabling tests once i03 lands harness-driven menu verification.
- **PM-restore parallelism.** Spec didn't constrain it; implementation fires one `Task` per PM tab and tracks a counter to know when to apply focus + scroll. Multiple concurrent connector requests are fine for v1 (the existing single PM file open already does this); could be serialized later if PM API rate-limiting surfaces.

No other deviations.

---

## Follow-up items

| Item | Sequencing |
|---|---|
| Live dogfood walk-through of the manual test plan | Before merge to main |
| SC9 XCUITest re-enablement | Blocked on i03 (harness-driven menu verification). When i03 ships, re-enable `OpenRecentMenuTests.testOpenRecentEmptyStatePlaceholder` and add SC1 / SC5 / SC6 coverage on the same harness. |
| **Connection-management UX** (D20) | Pre-D31, opening a PM `RecentEntry` whose connector isn't loaded leaves the entry disabled with a vague reason. When D20 lands, the disabled-click could trigger the sign-in flow. |
| Cross-window MRU sync | Single-window app today; out of scope. If multi-window ever lands, the `SessionState` will need to become per-window (extension strategy in spec §7). |
| Welcome / start-page surfacing of MRU | Roadmap candidate. The store API is already shaped for read-only consumers (no new work needed when that lands). |
| Per-recent-file security-scoped bookmarks | Spec NF5 — not in v1; recents outside the workspace root that lose access become "unavailable" per F5/F12. Extension strategy is documented. |
| Welcome / sub-line scroll precision | Spec §7 extension table. Both additive; no refactor risk. |
| Dirty-buffer preservation across quit | Explicitly OOS for D31; would need a `SwapBufferStore`. Roadmap candidate. |

---

## Notes

- **Branch ready to merge** once §A–§H of the manual test plan run green. No code changes anticipated unless dogfood surfaces a bug.
- **The placeholder being a Button (not Text)** was a forced workaround for the SwiftUI Menu AX bridge during XCUITest exploration. It turned out to be a UX + a11y improvement regardless — screen readers announce the empty state clearly. Worth keeping the pattern for any future "section headers in menus" need.
- **`isRestoring` is two-purpose** — gates both the recording subscription (prevent re-promotion) AND the session-state persist (prevent partial-snapshot writes during a multi-step restore). The single flag is fine because both gates have the same lifetime.
- **D30 Submit/Handoff session interest is NOT restored.** A tab that had a session interested in it pre-quit comes back as a fresh tab post-restore — the originating CC session is gone. This matches the spec OOS list.
- **Recurring memory note:** `feedback_focus_stealing.md` was broadened during this deliverable (2026-05-15) — "ask before focus-stealing operations" now applies to parallel-session usage too, not just single-screen / on-the-road. Reflected in the prompt's Constraints section and observed during the Phase 5 test runs (asked before the 60s UI test suite run).
- **Five commits on the branch** (excluding triad commit): Phase 1, Phase 2, Phase 3, Phase 4, Phase 5, Phase 5 follow-up. Each phase's commit message documents its scope and DOD.
