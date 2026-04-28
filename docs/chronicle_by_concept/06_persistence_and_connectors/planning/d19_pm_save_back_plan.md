# D19 Plan — PortableMind save-back

**Spec:** `docs/current_work/specs/d19_pm_save_back_spec.md`
**Created:** 2026-04-27
**Branch:** `feature/d19-pm-save-back`

---

## 0. Approach

Five phases, each independently buildable + smokeable. Compared to D18's six-phase shape, D19 is leaner because the connector + sidebar + tab UI infrastructure is already in place. What's new: a write path through the connector, a multipart-form-data upload helper, an `updated_at` conflict-detection prompt, and editable-tab state for PM origin.

1. **Protocol additions + `LocalConnector.saveFile`** — protocol grows `canWrite` + `saveFile`; LocalConnector's `saveFile` mirrors D14's local write-and-rewatch. EditorDocument routes `save()` through the connector for both Local and PM (Local through LocalConnector preserves D14 behavior). Behavior unchanged for users.
2. **`PortableMindAPIClient.updateFile` + multipart** — write the multipart-form-data builder; add the API client method; expose via a new harness action `pm_save_smoke`. No UI yet.
3. **PM tabs become editable + ⌘S routes to PM** — `EditorDocument.isReadOnly` becomes a `@Published` reactive flag, defaults driven by `connector.canWrite(node)`; `EditorContainer` subscribes; save menu re-enables for PM tabs when writable. End-to-end save path works against prod for the happy case.
3.1 — **Visible milestone.**
4. **Conflict-detection prompt (Q2)** — GET `updated_at` immediately before PATCH; if newer than last-seen, modal "Overwrite anyway?" with Overwrite / Cancel. Fallback: if the GET itself fails, write through (last-writer-wins). `ConnectorNode` carries `lastSeenUpdatedAt`.
5. **Manual test plan + COMPLETE + roadmap update** — close the deliverable. Optimistic save UX (Q3) verified; Save As on PM tabs presents the unsupported-feature dialog (Q4); harness assertions cover the loop without focus-stealing.

Each phase ends in a commit. Stop and surface a `**Question:**` if a phase reveals scope drift.

---

## 0.1 Verification approach (harness-first)

D19 continues the harness-first verification approach established in D18 plan §0.1. New harness actions land per phase:

- Phase 2: `pm_save_smoke {fileID, text, resultPath}` — async; calls `updateFile` directly against the API client; emits `{ok, byteCount, freshUrl}`.
- Phase 3: extended `dump_focused_tab_info` includes `dirty: bool` + `saving: bool`; new `connector_save_focused {resultPath}` programmatically triggers ⌘S.
- Phase 4: `dump_save_state {resultPath}` includes `lastSeenUpdatedAt`, `serverUpdatedAt` (when available), `conflictDetected`. New `dismiss_conflict_dialog {choice: "overwrite" | "cancel"}` for harness-driven dialog handling.
- Phase 5: harness migration of the i03 mutation tests is in scope here only as **opportunistic** — if it fits naturally with the new dirty/saving state, do it; otherwise leave for a focused testing deliverable.

Verify: write command JSON via `Bash`, wait for command-file disappearance, `cat` the result file, assert. App keeps focus wherever the user puts it.

---

## Phase 1 — Protocol additions + LocalConnector.saveFile

**Goal:** Connector protocol grows `canWrite` + `saveFile`. LocalConnector implements both. EditorDocument routes saves through the connector. User-visible behavior unchanged for Local; PM tabs still read-only for now (phase 3 flips them).

**Files updated:**

- `Sources/Connectors/Connector.swift`:
  - Add `func canWrite(_ node: ConnectorNode) -> Bool` (default impl returns false).
  - Add `func saveFile(_ node: ConnectorNode, bytes: Data) async throws -> ConnectorNode` (default impl throws `.unsupported`).
  - Add `case storageQuotaExceeded(String)` and `case writeForbidden(String)` to `ConnectorError`.
  - Add `lastSeenUpdatedAt: Date?` field to `ConnectorNode` (used by phase 4; init it to nil for D18-era construction sites).
- `Sources/Connectors/LocalConnector.swift`:
  - `canWrite(_:)` returns true for any local file node.
  - `saveFile(_:bytes:)` writes atomically with a watcher-stop guard (mirroring D14 `EditorDocument.writeAndRewatch`); returns a fresh `ConnectorNode` with the same id.
- `Sources/Connectors/PortableMind/PortableMindConnector.swift`:
  - `canWrite(_:)` returns false for D19 phase 1 (will become capability-driven in phase 3).
  - `saveFile(_:bytes:)` throws `.unsupported("phase 3")` for now.
- `Sources/Workspace/EditorDocument.swift`:
  - `save()` and `saveAs(to:)` route through the connector when `origin` is non-local. For `.local`, behavior unchanged (still writes via local URL).
  - Add `connector` weak reference + `node` for re-routing through the connector. *Or:* keep the local URL path and add a separate `func saveViaConnector(connector:node:)` — pick whichever is least invasive at impl time.

**Harness actions added:** none (phase 2 ships the first new action).

**DOD:**
- Build clean.
- App behavior unchanged from a user POV: Local files save via ⌘S; PM tabs still read-only (RO pill present, save menu greyed).
- Existing harness actions (`save_focused_doc`, `focused_doc_info`) continue to work.
- D14 manual smoke (Save / Save As on a local file): still GREEN.

**Commit:** `D19 phase 1 — Connector protocol grows canWrite + saveFile; LocalConnector implements`

---

## Phase 2 — Multipart upload + PortableMindAPIClient.updateFile

**Goal:** Pure infrastructure; no UI. After this phase, `pm_save_smoke` against a real PM file succeeds end-to-end (writes new content, returns fresh signed URL).

**New file:**

- `Sources/Connectors/PortableMind/MultipartFormDataBuilder.swift` (~50 LOC):
  - Constructs `multipart/form-data` body with a generated boundary.
  - One method: `appendFile(name:filename:contentType:data:)`.
  - Returns `(body: Data, contentType: String)` (the latter includes the boundary).
  - Cribs from standard URLSession-multipart patterns; no third-party dep.

**Files updated:**

- `Sources/Connectors/PortableMind/PortableMindAPIClient.swift`:
  - New `updateFile(fileID: Int, bytes: Data, contentType: String = "text/markdown") async throws -> FileDTO`.
  - Constructs PATCH `/api/v1/llm_files/:id` with multipart body where `llm_file[file]` is a file part.
  - Maps server responses: 200 → `FileDTO`; 402 with `error_code: DOCUMENT_STORAGE_LIMIT_EXCEEDED` → `ConnectorError.storageQuotaExceeded(message)`; 401/403 → `.writeForbidden(...)`; other non-2xx → `.server(...)`.
- `Sources/Debug/HarnessCommandPoller.swift`:
  - New `pm_save_smoke {fileID, text, resultPath}` action. Async; calls `updateFile`; emits `{ok, byteCount, fileID, freshUrl, updatedAt}` envelope.

**DOD:**
- `pm_save_smoke` against a writable LlmFile in Rick's prod tenant returns `ok: true`. Verifiable via `Bash`: write command, await result file, `jq` the envelope.
- Round-trip: read content via D18 connector → modify → write via `pm_save_smoke` → read again → confirms new content.
- Storage-quota error returns `error: "storageQuotaExceeded"`. (Hard to provoke; smoke just confirms the case is wired.)
- App builds; no UI changes visible.

**Commit:** `D19 phase 2 — multipart upload + PortableMindAPIClient.updateFile`

---

## Phase 3 — PM tabs become editable + ⌘S routes to PM

**Goal:** Visible milestone. Click a `.md` in the PM tree → editable tab opens (no READ-ONLY pill, no greyed save menu). ⌘S triggers connector.saveFile, which PATCHes Harmoniq.

**Files updated:**

- `Sources/Workspace/EditorDocument.swift`:
  - `isReadOnly` → `@Published var isReadOnly: Bool`. Default for `.portableMind(...)` origin: `!connector.canWrite(node)` (resolved at construction; recomputed if the connector flips capability later).
  - `save()` for PM origin: build `bytes = source.data(using: .utf8)`, call `connector.saveFile(node, bytes:)`. Update `lastSeenUpdatedAt` from the response. Surface errors as `SaveError` cases.
- `Sources/Connectors/PortableMind/PortableMindConnector.swift`:
  - `canWrite(_:)` returns `true` for any `.file` node (we don't have per-file capability data on the read response; D19 trusts the read existence as evidence of read access — write may still fail with `.writeForbidden` and we handle that). Future: respect a `permissions` field if the API surfaces one.
  - `saveFile(_:bytes:)` parses fileID from `node.id`, calls `api.updateFile(fileID:bytes:)`, returns a refreshed `ConnectorNode` with the new `lastSeenUpdatedAt`.
- `Sources/Editor/EditorContainer.swift`:
  - `wireDocumentSubscription` adds a sink on `document.$isReadOnly` that updates `textView.isEditable` reactively.
- `Sources/WorkspaceUI/TabBarView.swift`:
  - "READ-ONLY" pill conditional now reads `document.isReadOnly` (already does); the value flips to `false` for writable PM tabs, so the pill disappears.
  - Add a small "saving…" indicator that shows when `document.isSaving` is true (new `@Published var isSaving: Bool` on EditorDocument).
- `Sources/App/MdEditorApp.swift`:
  - `saveFocused()` now handles non-local origins by calling `doc.save()` directly (which routes through the connector). The error-presentation path stays the same; new error cases get clearer messages via `LocalizedError`.
- `Sources/Workspace/TabStore.swift`:
  - Drop the `isReadOnly: true` lock-in in `openReadOnly`. Instead: `openFromConnector(content:origin:isReadOnly:)` where the boolean is computed from `connector.canWrite(node)` at open time.

**Harness actions added (phase 3):**
- Extend `focused_doc_info`: emit `dirty: bool` (source != lastSavedSource), `saving: bool`, `lastSeenUpdatedAt: ISO8601 string`.
- New `connector_save_focused {resultPath}`: programmatically trigger save on the focused tab; emits `{ok, error?}`.

**DOD:**
- Click a PM `.md` (e.g. `/rockcut-site-guide.md`) → tab opens **editable** (no RO pill).
- `dump_command_state` → `save: true, saveAs: true` (Save As pending Q4 dialog work in phase 4).
- Type into the buffer → `dirty: true` in `focused_doc_info`.
- ⌘S (or `connector_save_focused`) → buffer hits prod; `pm_save_smoke` follow-up confirms the new content; `dirty: false` after success.
- Save fails with bad token → error dialog; tab stays editable; buffer not lost.
- D18 read-only behavior remains the fallback for tabs where `canWrite == false`.

**Commit:** `D19 phase 3 — PM tabs become editable; ⌘S routes through PortableMindConnector`

---

## Phase 4 — Conflict detection (Q2)

**Goal:** Before each PATCH, GET the file's current `updated_at`. If newer than `lastSeenUpdatedAt`, present a modal: "This file changed on PortableMind since you opened it. Overwrite anyway?" Overwrite proceeds with the PATCH; Cancel keeps the buffer dirty without saving. **Graceful fallback:** if the GET itself fails, write through (last-writer-wins) — flaky network shouldn't block saves.

**Files updated:**

- `Sources/Connectors/PortableMind/PortableMindConnector.swift`:
  - `saveFile(_:bytes:)` becomes a two-step:
    1. `api.fetchFileMeta(fileID:)` to get current `updated_at`.
    2. If `updated_at > node.lastSeenUpdatedAt`, throw a new `ConnectorError.conflictDetected(serverUpdatedAt: Date)` with the new timestamp.
    3. Otherwise PATCH and return refreshed node.
  - The fallback semantics: if step 1's `fetchFileMeta` itself throws (network error, etc.), proceed directly to step 3 (last-writer-wins). Server errors on the meta GET that aren't network-class still throw normally (don't paper over auth failures).
- `Sources/Connectors/Connector.swift`:
  - Add `case conflictDetected(serverUpdatedAt: Date)` to `ConnectorError`.
- `Sources/Workspace/EditorDocument.swift`:
  - New `save(force: Bool = false)`. When `force == true`, the connector skips the conflict check (passes a flag through). When the connector throws `.conflictDetected`, `save()` rethrows; caller (the menu handler) catches and presents the dialog.
- `Sources/App/MdEditorApp.swift`:
  - `saveFocused()` catches `ConnectorError.conflictDetected`; presents `NSAlert` with Overwrite / Cancel; on Overwrite, calls `doc.save(force: true)`.

**Harness actions added (phase 4):**
- `dump_save_state {resultPath}` — emits `{lastSeenUpdatedAt, serverUpdatedAt (if known), conflictDetected, conflictDialogShown}`.
- `dismiss_conflict_dialog {choice: "overwrite" | "cancel"}` — programmatically dismisses the conflict NSAlert. Required because XCUIDialog interaction is flaky and we want this verifiable from the harness.

**DOD:**
- Open a PM file in the editor; in a separate process (curl, web UI, or another harness instance) PATCH the same file with different content; type a change in the editor; ⌘S → conflict dialog appears with the right text.
- `dismiss_conflict_dialog choice="overwrite"` → save proceeds; the buffer becomes the canonical version.
- `dismiss_conflict_dialog choice="cancel"` → save is skipped; buffer stays dirty; no error.
- Network-failure fallback: with the API client patched to return network error on `fetchFileMeta`, save proceeds via PATCH alone (last-writer-wins).
- Auth/server failure on `fetchFileMeta` does NOT trigger fallback — surfaces as a normal error.

**Commit:** `D19 phase 4 — conflict-detection prompt (Q2); GET-before-PATCH with graceful fallback`

---

## Phase 5 — Save As stub + manual test plan + COMPLETE + roadmap

**Goal:** Q4 unsupported-feature dialog for Save As on PM tabs; close the deliverable.

**Files updated:**

- `Sources/App/MdEditorApp.swift`:
  - `saveAsFocused()` for PM tabs: present `NSAlert` "Save As is not yet supported for PortableMind documents. Use the PortableMind web UI to rename or move; the editor will pick up the change. (Future deliverable will add Save As + New File for PortableMind.)" — with a single OK button.
- New files:
  - `docs/current_work/testing/d19_pm_save_back_manual_test_plan.md` — sections cover write happy-path, dirty-state, error cases (network down, quota, forbidden), conflict prompt + fallback, Save As stub, regression on Local save / D18 read-only behaviors.
  - `docs/current_work/stepwise_results/d19_pm_save_back_COMPLETE.md` — completion record per template.
- `docs/roadmap_ref.md` — D19 → ✅ Complete; D20 stays pending; the unified PM-file-management deliverable (Save As + New File) gets a row.

**DOD:**
- Manual test plan walked; results recorded.
- COMPLETE doc references the test plan + decisions + follow-ups.
- Roadmap reflects D19 ✅; PM-file-management deliverable queued.
- `xcodebuild test` GREEN (carried forward from D18 i03 fix).

**Commit:** `D19 phase 5 — Save As stub + manual test plan + COMPLETE + roadmap update`

---

## Risks / open implementation questions

1. **`canWrite` heuristic.** D19 phase 3 returns `true` for any PM file node. If write denial happens server-side (401/403 on PATCH), we surface `.writeForbidden` and re-flip the tab to read-only with a message. Better: get a `permissions` field from the read response so we can color the UI before the user types. Track for D20 / future.

2. **`lastSeenUpdatedAt` plumbing.** ConnectorNode is a value type; refreshing it after save means the EditorDocument needs to swap to a fresh node reference. Carefully thread this through TabStore so other tabs viewing the same file see the update.

3. **Multipart body size.** D19 doesn't stream — bytes go in memory. For large `.md` (>10MB) this is fine; if PM ever stores larger content, swap to a streaming InputStream-based body in a future deliverable.

4. **Concurrent saves on the same tab.** If a user mashes ⌘S while a save is in flight, debounce or coalesce? D19 phase 3's "saving" state grays the menu; a second ⌘S no-ops while saving. Document in the COMPLETE.

5. **Test fixture for conflict detection.** Phase 4 needs a way to mutate a file out-of-band during a test. Two options: (a) the harness has a `pm_save_smoke` action which we already added in phase 2, run twice; (b) curl from the test driver. (a) is simpler.
