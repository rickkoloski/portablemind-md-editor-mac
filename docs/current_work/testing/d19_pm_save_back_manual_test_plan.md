# D19 Manual Test Plan — PortableMind save-back

**Spec:** `docs/current_work/specs/d19_pm_save_back_spec.md`
**Plan:** `docs/current_work/planning/d19_pm_save_back_plan.md`
**Date authored:** 2026-04-28

Human-runnable mirror of the harness-driven verification used through phases 1–4 (per `docs/engineering-standards_ref.md` §0.1 — harness-first; the harness path is the primary verification surface, this plan is the manual rerun for someone without the harness driver).

D19 closes the human↔agent dogfood loop on PortableMind-stored docs: PM tabs become editable, ⌘S routes through `Connector.saveFile`, and an optimistic `updated_at` check prompts before overwriting concurrent edits. Save As on a PM tab presents the unsupported-feature dialog (Q4 decision) — the unified PM file-management deliverable (rename / move / new-file at a chosen location) follows post-D20.

---

## Setup

1. Build a Debug app:

   ```bash
   cd ~/src/apps/md-editor-mac
   source scripts/env.sh
   xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
     -configuration Debug -derivedDataPath ./.build-xcode build
   ```

2. Launch:

   ```bash
   open ./.build-xcode/Build/Products/Debug/MdEditor.app
   ```

3. Seed a PortableMind bearer token (per D18 plan §A — Debug menu paste, or `pm_token_set` harness action).

4. The canonical write-test fixture is `/test-sample.md` in the `portablemind` tenant (LlmFile id 916). It's a 74-byte sample; safe to overwrite repeatedly.

---

## §A — Read-only fallback still works

**Goal:** D19 is additive on D18's read-only path. When the connector reports `canWrite == false` (e.g. for connectors we add later that don't grant write), the tab stays read-only.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| A1 | Set token; open `/test-sample.md` in the PM tree. | Tab opens **without** a "READ-ONLY" pill (PM connector reports `canWrite == true` for any `.file`). | `connector_open_file` → `dump_save_state` shows `isReadOnly: false`, `lastSeenUpdatedAt` non-empty. |

---

## §B — Editable PM tab + ⌘S happy path

**Goal:** Editing a PM tab and pressing ⌘S writes the buffer to Harmoniq via `PATCH /api/v1/llm_files/:id`.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| B1 | Type a character in the open PM tab. | Buffer accepts edits. Dirty dot (`●`) appears in the tab title. | `focused_doc_info` → `dirty: true`. |
| B2 | ⌘S. | Brief saving indicator (mini progress spinner where the dirty dot was); on success the dirty dot is gone. No error dialog. | `attempt_save_focused` → `{ok: true, dirty: false, conflictDetected: false}`. |
| B3 | Quit the app. Relaunch. Reopen `/test-sample.md`. | The buffer reflects the value you wrote in B1+B2 (server returned the new content). | `connector_open_file` → bytes contain the B1 mutation. |

---

## §C — Conflict detection (Q2 decision: server-wins warning)

**Goal:** When the file's server `updated_at` is newer than what the client last saw, `⌘S` presents the **Overwrite / Cancel** dialog. Cancel keeps the buffer dirty; Overwrite re-saves with `force: true`.

Mutating the file out-of-band requires a second writer. Two ways:
- Web UI: open Harmoniq, edit `/test-sample.md` from there, save.
- Harness: `pm_save_smoke {fileID: 916, text: "external mutation", filename: "test-sample.md", path: …}` writes any content via the same PATCH endpoint, advancing `updated_at`.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| C1 | Open `/test-sample.md`. Type a change in the editor (don't save yet). | Buffer dirty. Editor is unaware of any external change. | `dump_save_state` → `dirty: true`, `lastSeenUpdatedAt: <T0>`. |
| C2 | Out-of-band write to LlmFile 916 (web UI or `pm_save_smoke`). | Server `updated_at` advances past `T0`. The editor doesn't know yet. | `pm_save_smoke` envelope includes `updatedAt: <T1>` where `T1 > T0`. |
| C3 | ⌘S in the editor. | Sheet appears: "Remote file has changed — This file was modified on PortableMind since you opened it. Server's last-modified time is `<T1>`. Overwrite the server version with your local edits?" — Overwrite / Cancel buttons. | `attempt_save_focused` runs; while running, `dump_save_state` returns `conflictDialogShown: true`. |
| C4 | Click **Cancel**. | Sheet closes. Tab still dirty (no save happened). No error dialog. | `dismiss_conflict_dialog choice=cancel` → `{dismissed: true, choice: "cancel"}`. `attempt_save_focused` envelope: `{userCancelled: true, conflictDetected: true, dirty: true, ok: false}`. |
| C5 | ⌘S again (server still ahead). Sheet reappears. Click **Overwrite**. | Sheet closes. Save proceeds with `force: true`. Dirty dot gone; the local content is the canonical server version. `lastSeenUpdatedAt` advances. | `dismiss_conflict_dialog choice=overwrite` → `{dismissed: true, choice: "overwrite"}`. `attempt_save_focused` envelope: `{ok: true, wentThroughDialog: true, conflictDetected: false, dirty: false}`. |

---

## §D — Graceful network fallback on the meta GET

**Goal:** If the GET-before-PATCH (`fetchFileMeta`) fails with a network error, save proceeds with the PATCH alone (last-writer-wins). A flaky network shouldn't block saves — the dialog is the firm protection; the fallback honors realistic field conditions.

| # | Action | Expected |
|---|--------|----------|
| D1 | Disable Wi-Fi (or otherwise drop the network). Type a character. ⌘S. | The PATCH itself fails. Error dialog: "Network error during save: …". Tab stays dirty. |
| D2 | Re-enable network. Type another character. ⌘S. | Save succeeds normally. (No way to provoke the *meta-fails-but-PATCH-succeeds* split without packet-level interception; the code path is exercised by code review of `PortableMindConnector.saveFile`'s `catch ConnectorError.network` clause.) |

**Code-review verification of the fallback split** (D2's hard-to-provoke case): inspect `Sources/Connectors/PortableMind/PortableMindConnector.swift` around the `if !force, let lastSeen = node.lastSeenUpdatedAt` block. The `catch ConnectorError.network` clause sets `serverUpdatedAt = nil`; the next `if let server = serverUpdatedAt` is then skipped, so we fall through to the PATCH. Other error classes (`ConnectorError.unauthenticated`, `.server`) are not caught and propagate normally — confirming "Auth/server failure on `fetchFileMeta` does NOT trigger fallback."

---

## §E — Permission denial + storage quota

**Goal:** 401/403 on PATCH surface as `writeForbidden`; 402 with `DOCUMENT_STORAGE_LIMIT_EXCEEDED` surfaces as `storageQuotaExceeded`. Both flip the tab to read-only (forbidden) or surface a useful error message.

| # | Action | Expected |
|---|--------|----------|
| E1 | Set an EXPIRED bearer token (overwrite via Debug menu with a known-bad JWT). Try ⌘S. | Error dialog: "Write denied by PortableMind: …". Tab flips to read-only (RO pill appears). |
| E2 | (Hard to provoke.) Tenant over storage quota. ⌘S. | Error dialog: "PortableMind storage quota exceeded: …". |

E2 is hard to provoke without filling the tenant. The catch case is exercised by code review of `PortableMindAPIClient.updateFile` — switch case for `402` maps to `ConnectorError.storageQuotaExceeded`.

---

## §F — Save As stub (Q4 decision)

**Goal:** ⌘⇧S on a PM tab presents the unsupported-feature dialog. Doesn't crash. Doesn't try to write anywhere.

| # | Action | Expected |
|---|--------|----------|
| F1 | Open a PM tab. ⌘⇧S. | Modal alert: "Save As not yet supported — Save As is not yet supported for PortableMind documents. Use the PortableMind web UI to rename or move; the editor will pick up the change. (A future deliverable will add Save As + New File for PortableMind.)". Single OK button. |
| F2 | ⌘⇧S on a Local tab. | Standard save panel (D14 behavior, unchanged). |

---

## §G — Regression sweep

D19 routes Local saves through `LocalConnector.saveFile`. This must preserve D14 behavior exactly.

| # | Action | Expected |
|---|--------|----------|
| G1 | Open a local `.md`. Edit, ⌘S. | File is updated on disk; ExternalEditWatcher pause/restart works (no echo-loop). |
| G2 | Open Untitled (⌘N). ⌘S. | Save panel opens (Save → Save As fallback for untitled local docs). |
| G3 | ⌘⇧S on a local doc. | Save panel opens. |

---

## §H — Concurrent ⌘S debounce

| # | Action | Expected |
|---|--------|----------|
| H1 | Mash ⌘S rapidly while a save is in flight. | Only one PATCH per save burst (`isSaving` guards re-entry). No queued retries. The first save completes; subsequent ⌘S during its in-flight window is a no-op. |

---

## Cross-cutting harness recipe (one-paste verification of §C)

For someone with access to the harness driver, the entire conflict-detection loop verifies in seconds without UI interaction:

```bash
# Open the fixture file
echo '{"action":"connector_open_file","connectorID":"portablemind","path":"/test-sample.md","resultPath":"/tmp/r.json"}' > /tmp/mdeditor-command.json
sleep 4

# Mutate out-of-band (advances updated_at)
echo '{"action":"pm_save_smoke","fileID":916,"text":"# external\n","filename":"test-sample.md","path":"/tmp/r.json"}' > /tmp/mdeditor-command.json
sleep 2

# Dirty the buffer
echo '{"action":"insert_text","text":"X"}' > /tmp/mdeditor-command.json
sleep 1

# Trigger the dialog flow
echo '{"action":"attempt_save_focused","path":"/tmp/r.json"}' > /tmp/mdeditor-command.json
sleep 2

# Confirm the dialog is up
echo '{"action":"dump_save_state","path":"/tmp/s.json"}' > /tmp/mdeditor-command.json; sleep 1; cat /tmp/s.json
# Expect: "conflictDialogShown" : true

# Dismiss with overwrite
echo '{"action":"dismiss_conflict_dialog","choice":"overwrite","path":"/tmp/d.json"}' > /tmp/mdeditor-command.json; sleep 2
cat /tmp/r.json
# Expect: "ok" : true, "wentThroughDialog" : true, "conflictDetected" : false
```
