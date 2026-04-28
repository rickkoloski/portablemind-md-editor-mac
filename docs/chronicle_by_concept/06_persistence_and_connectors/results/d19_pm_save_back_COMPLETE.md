# D19: PortableMind Save-Back — Complete

**Spec:** `docs/current_work/specs/d19_pm_save_back_spec.md`
**Plan:** `docs/current_work/planning/d19_pm_save_back_plan.md`
**Manual test plan:** `docs/current_work/testing/d19_pm_save_back_manual_test_plan.md`
**Branch:** `feature/d19-pm-save-back`
**Completed:** 2026-04-28

---

## Summary

D19 closes the human↔agent dogfood loop on PortableMind-stored documents. After D18 phase 5, PM tabs were read-only — the agentic editing loop (CC drops `**Question:**`, human answers inline, CC logs `**Decision:**`) only worked on local files. D19 makes PM tabs editable, routes ⌘S through `Connector.saveFile`, and lands a server-wins conflict-detection prompt so simultaneous edits from another agent or the web UI don't silently overwrite each other.

The deliverable spans five phases on `feature/d19-pm-save-back`:

1. **Connector protocol** grew `canWrite` + `saveFile`; `LocalConnector` implements both (mirroring D14's atomic-write-and-rewatch). Behavior unchanged for users.
2. **Multipart-form-data upload** + `PortableMindAPIClient.updateFile` against `PATCH /api/v1/llm_files/:id`. Smoke-tested against prod via the new `pm_save_smoke` harness action — no UI yet.
3. **PM tabs become editable** (visible milestone). `EditorDocument.isReadOnly` becomes `@Published`; `EditorContainer` subscribes; `EditorDocument.save()` is async; ⌘S routes through the connector. Saving indicator on the tab.
4. **Conflict-detection prompt** (Q2 decision: server-wins warning). `openFile` now returns `(Data, ConnectorNode)` so the meta call's `updated_at` reaches the doc as a baseline. `PortableMindConnector.saveFile` GETs the meta before each PATCH and throws `.conflictDetected` when the server is newer; `MdEditorApp.saveFocused` catches it and presents an Overwrite / Cancel sheet via `ConflictDialogPresenter`. Network-class failures on the meta GET fall through to the PATCH (graceful fallback per the spec); auth/server errors propagate.
5. **Save As stub** (Q4 decision) — ⌘⇧S on a PM tab presents the unsupported-feature dialog. Manual test plan + COMPLETE + roadmap update.

D22 (tab right-click context menu — Copy Path / Copy Relative Path) landed mid-stream off `main` to unblock CD's two-agent dogfood workflow during phase 4 verification, then merged back into the D19 branch.

i04 (bearer-token persistence stopgap — file-based replacement for the cdhash-bound Keychain ACL) also landed off `main` during D19 phase 4 setup; reverts when Apple Developer enrollment lands.

---

## Implementation Details

### What Was Built

- **Connector protocol additions** — `canWrite(_:)` (sync), `saveFile(_:bytes:force:)` (async). `openFile` switched to `(Data, ConnectorNode)` so connectors can return a freshness-refreshed node alongside the bytes. New `ConnectorError` cases: `storageQuotaExceeded`, `writeForbidden`, `conflictDetected(serverUpdatedAt:)`. `ConnectorNode.lastSeenUpdatedAt` carries the server-side baseline for the conflict check.
- **`LocalConnector.saveFile`** — atomic UTF-8 write; mirrors D14's `EditorDocument.writeAndRewatch` semantics. Watcher pause/restart owned at the EditorDocument layer (per D18's contract).
- **`MultipartFormDataBuilder`** — small URLSession-multipart helper (~50 LOC, no third-party dep).
- **`PortableMindAPIClient.updateFile`** — multipart PATCH with bearer + JWT-derived `X-Tenant-ID`; status-code mapping to `ConnectorError` (200/201/204 → success, 401/403 → `writeForbidden`, 402 → `storageQuotaExceeded`, others → `server`). `fetchSignedBlob` bumped private → internal so the connector can drive the open-time meta + blob fetch as two visible steps (it needs the meta's `updated_at` separately for the conflict-detection baseline).
- **`PortableMindConnector.saveFile`** — two-step: optional meta GET for conflict check, then multipart PATCH. Conflict check is gated on `force == false && node.lastSeenUpdatedAt != nil`; throws `.conflictDetected` on server-newer; on network failure of the meta GET, falls through to PATCH. `openFile` now exposes the meta's `updated_at` in the refreshed node.
- **`EditorDocument` rework** — `isReadOnly` → `@Published`; `save(force:)` async; routes by origin (local stays in-process via `writeAndRewatch`, PM goes through the connector). `dirty: Bool` predicate. `connectorNode` field; refreshed after every successful PM save. New `SaveError` cases: `writeForbidden`, `storageQuotaExceeded`, `networkSaveFailed`, `unsupportedSaveAs`.
- **`MdEditorApp`** — `saveFocused()` wraps the save in a small `attemptSave` helper that catches `ConnectorError.conflictDetected` and presents the dialog. On Overwrite the helper recurses with `force: true`. Save As on PM tabs is a single-button NSAlert with the Q4 message.
- **`ConflictDialogPresenter`** (new file) — singleton owner of the in-flight conflict NSAlert. Uses `beginSheetModal` so the harness `Timer` keeps firing while the dialog is up; `dismiss(choice:)` programmatically clicks Overwrite or Cancel.
- **`TabBarView`** — saving spinner + dirty dot indicators alongside the existing read-only pill. Right-click context menu (D22 — Copy Path / Copy Relative Path).
- **`PathFormatting`** (D21 helper) — extended with doc-level `absolutePathForCopy(_:)` / `relativePathForCopy(_:)` for tab right-click.
- **Harness actions** — `pm_save_smoke` (phase 2; bypass-UI write smoke-test), `connector_save_focused` (phase 3; programmatic ⌘S equivalent, extended in phase 4 with `force` param + `conflictDetected` envelope), `dump_save_state` (phase 4; reports dirty / saving / lastSeenUpdatedAt / conflictDialogShown), `dismiss_conflict_dialog` (phase 4; programmatic button-click on the active sheet), `attempt_save_focused` (phase 4; mirrors `MdEditorApp.attemptSave` so harness drivers exercise the full user-facing path including the dialog).
- **i04 stopgap** — `KeychainTokenStore` now persists to `~/Library/Application Support/ai.portablemind.md-editor/token.txt` (0600). Ad-hoc-signed builds attach a cdhash-bound ACL to Keychain items, so each rebuild invalidates the entry; the file-based stopgap survives until real signing identity lands.

### Files Created

| File | Purpose |
|------|---------|
| `Sources/Connectors/PortableMind/MultipartFormDataBuilder.swift` | Multipart-form-data body builder for PATCH |
| `Sources/App/ConflictDialogPresenter.swift` | Singleton owner of the active conflict NSAlert; sheet-modal presentation; harness-driven dismissal |
| `docs/current_work/specs/d19_pm_save_back_spec.md` | Spec (APPROVED FRAME) |
| `docs/current_work/planning/d19_pm_save_back_plan.md` | Plan |
| `docs/current_work/prompts/d19_pm_save_back_prompt.md` | Prompt |
| `docs/current_work/testing/d19_pm_save_back_manual_test_plan.md` | Manual test plan (this deliverable's runnable verification) |
| `docs/current_work/stepwise_results/d19_pm_save_back_COMPLETE.md` | This doc |

### Files Modified

| File | Changes |
|------|---------|
| `Sources/Connectors/Connector.swift` | `canWrite` + `saveFile` on protocol; `openFile -> (Data, ConnectorNode)`; new error cases; `ConnectorNode.lastSeenUpdatedAt` |
| `Sources/Connectors/LocalConnector.swift` | `canWrite` returns true for files; `saveFile` does atomic write; `openFile` returns input node unchanged in tuple |
| `Sources/Connectors/PortableMind/PortableMindConnector.swift` | `canWrite` returns true for PM file nodes; `saveFile` does GET-before-PATCH conflict check; `openFile` populates `lastSeenUpdatedAt` from meta |
| `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` | `updateFile` (multipart PATCH); `fetchSignedBlob` private→internal |
| `Sources/Workspace/EditorDocument.swift` | `isReadOnly` → `@Published`; async `save(force:)`; PM origin routes through connector; `connectorNode` storage; `lastSavedSource`; `dirty`; new `SaveError` cases |
| `Sources/Workspace/TabStore.swift` | `openFromConnector(content:node:)` — replaces D18's `openReadOnly`; computes `isReadOnly` from `connector.canWrite(node)`; de-dupes on PM (connectorID, fileID) |
| `Sources/Editor/EditorContainer.swift` | Subscribes to `document.$isReadOnly`; reactively flips `textView.isEditable` |
| `Sources/WorkspaceUI/WorkspaceView.swift` | Updated for `openFile -> tuple` and `openFromConnector` |
| `Sources/WorkspaceUI/TabBarView.swift` | Saving spinner + dirty dot + (via D22 merge) right-click Copy Path / Copy Relative Path |
| `Sources/App/MdEditorApp.swift` | `saveFocused` → `attemptSave` helper (catches conflictDetected, presents dialog, recurses on Overwrite); Save As PM stub |
| `Sources/Debug/HarnessCommandPoller.swift` | 5 new D19 actions + extended `focused_doc_info` (dirty, isSaving, lastSeenUpdatedAt) and `connector_save_focused` envelope (conflictDetected, serverUpdatedAt) |
| `docs/roadmap_ref.md` | D19 → ✅ Complete; new "PM file management — Save As + New File" candidate row |

---

## Verification

### Phase 4 conflict-detection — verified end-to-end against prod 2026-04-28

Drove the full set of harness scenarios against `/test-sample.md` (LlmFile id 916, `portablemind` tenant). All four GREEN:

| Scenario | Path | Outcome |
|---|---|---|
| Connector save, no force, server ahead | `connector_save_focused force=false` | `conflictDetected: true`, `serverUpdatedAt` populated, no PATCH |
| Connector save, force=true | `connector_save_focused force=true` | `ok: true`, `lastSeen` advances to post-PATCH timestamp |
| Dialog Cancel | `attempt_save_focused` → `dismiss_conflict_dialog choice=cancel` | `userCancelled: true`, `dirty: true`, no PATCH |
| Dialog Overwrite | `attempt_save_focused` → `dismiss_conflict_dialog choice=overwrite` | `ok: true`, `wentThroughDialog: true`, `lastSeen` advances |

Two DOD bullets remained code-review-only because they require URLSession-level mocking we'd rather not add to prod test infra: (a) network-class meta GET failure → graceful fallback to PATCH; (b) auth-class meta GET failure → propagates instead of falling back. Both verified by inspection of the `PortableMindConnector.saveFile`'s `catch ConnectorError.network` clause and the absence of broader `catch` patterns. Documented in §D of the manual test plan.

### Build status

`xcodebuild build` GREEN on every phase commit. UITests carried forward from D18 phase 6 (i03 LaunchSmoke fix + 2 mutation tests `XCTSkip`'d) — `xcodebuild test` is GREEN at 1 passing + 2 skipped + 0 failures.

### Open implementation considerations (per plan §Risks)

1. **`canWrite` heuristic.** PM connector returns `true` for any `.file` node. Per-file write denial surfaces as `ConnectorError.writeForbidden` from the PATCH (401/403) and the tab flips to read-only. Per-node permission metadata from the read response is a future ergonomic — track for D20 / future.
2. **`lastSeenUpdatedAt` plumbing.** Initial baseline set in `openFile`'s refreshed node; refreshed after every successful save by `saveFile`'s returned node. Multi-tab views of the same PM file would each track their own baseline (no shared cache); de-dupe in `openFromConnector` re-uses the existing tab's doc, so a second click on the same file just re-focuses without resetting the baseline.
3. **Multipart body size.** D19 keeps bytes in memory. Fine for `.md` (typical < 1MB); revisit if PM ever stores larger content.
4. **Concurrent ⌘S debounce.** `EditorDocument.save` returns early when `isSaving == true`. Second ⌘S during an in-flight save is a no-op (no queue, no second PATCH).
5. **Test fixture for conflict detection.** Phase 4 harness tests use `pm_save_smoke` to advance the server's `updated_at` out-of-band — same endpoint, same machinery. Documented in the manual test plan §C.

---

## Decisions Recorded

The spec's Decision log captured CD's resolution of the four open questions on 2026-04-27:

- **Save semantics (Q1):** Save-on-⌘S only. Auto-save deferred.
- **Conflict resolution (Q2):** Server-wins warning before overwrite, with graceful network fallback.
- **Save UX during in-flight save (Q3):** Optimistic — keep the editor responsive.
- **Save As / rename / move on PM tabs (Q4):** Out of scope for D19; ⌘⇧S presents an unsupported-feature dialog. Future commitment: unified PM file-management deliverable (rename / move / new-file at chosen location) post-D20.

---

## Findings During Implementation

| # | Finding | Resolution |
|---|---------|------------|
| F1 | `openFile -> Data` doesn't carry the meta's `updated_at` to the EditorDocument layer; phase 4's conflict check would skip on the *first* save after open (no baseline) — exactly the most common case. | Bumped `openFile` to `(Data, ConnectorNode)` so the refreshed node propagates the timestamp. Two callers updated (`WorkspaceView.handleSelect`, `HarnessCommandPoller.connectorOpenFile`). |
| F2 | `tv.keyDown` (what `synthesize_keypress` uses) doesn't fire SwiftUI's `keyboardShortcut` bindings — menu key equivalents dispatch at the window level, not the text-view level. The harness couldn't drive `MdEditorApp.saveFocused`'s ⌘S path. | New `attempt_save_focused` harness action mirrors `MdEditorApp.attemptSave` so test drivers exercise the same flow including the dialog. Documented in the action's comment block. |
| F3 | `ConflictDialogPresenter.runModal()` blocks the main thread in `NSModalPanelRunLoopMode`, which doesn't process Timers scheduled in `.default` mode — the harness Timer would freeze with the dialog up, blocking `dismiss_conflict_dialog`. | Switched to `beginSheetModal(for:)` with `withCheckedContinuation`. Sheet-modal keeps the main runloop in default mode; the harness Timer keeps firing. Falls back to `runModal` if no visible window is found (defensive — shouldn't happen in normal operation). |
| F4 | Ad-hoc-signed Debug builds (`CODE_SIGN_IDENTITY: "-"`) attach a cdhash-bound ACL to Keychain items — every rebuild invalidates the bearer token. CD had to re-paste through the Debug menu every build. | i04 stopgap on `main`: file-based token storage at 0600 in Application Support. Reverts when Apple Developer enrollment lands. Tracked in `docs/issues_backlog.md`. |
| F5 | CD's two-agent dogfood (one agent opens a file via the CLI surface; CD wants to share the link with another agent) was friction-heavy because the sidebar tree isn't auto-expanded to the open file. | D22 (off `main`, merged back) — tab right-click context menu with Copy Path / Copy Relative Path. "Reveal in Sidebar" deferred to a future iteration. |

---

## Future Work

Out of scope for D19 — committed for follow-up:

- **D20 — Connection-management UX.** Replaces the dev-only Debug-menu Token affordance with a Finder-style add/edit/remove flow. Per-connection auth, token refresh.
- **PM file management — Save As + New File.** Q4 decision committed this for a future deliverable (post-D20). Unified surface for rename, move, and create-at-target-location.
- **Auto-save / debounced save.** Q1 deferral. Should land once we have telemetry on how often users forget to ⌘S on a PM tab.
- **Three-way merge.** Q2 deferral. The server-wins warning is D19's protection.
- **Per-document share / permissions UI.** Editor reflects what the API allows; doesn't grant or revoke.
- **Offline queue.** Save-while-disconnected, replay on reconnect. D19 surfaces network errors but doesn't queue retries.
- **"Reveal in Sidebar" on the tab context menu** (D22 follow-up). Expands tree ancestors and scrolls to the row.
- **Per-node `permissions` plumbing** so the editor can color the UI before the user types (if the read response surfaces capability data).
