# 06 — Persistence and Connectors

## Overview

Five deliverables that gave the editor "a way to save". D14 added local Save / Save As (atomic UTF-8 write through ExternalEditWatcher pause/restart guard, ⌘S / ⌘⇧S menu items, untitled-Save → Save As panel fallback). D18 introduced the `Connector` abstraction (one of the nine cross-OS abstractions in `docs/stack-alternatives.md` §3) and shipped `LocalConnector` + `PortableMindConnector` — the editor's storage backend went from "the local filesystem" to "any backend that conforms to a small async protocol". D19 made PortableMind tabs editable, with a server-wins conflict-detection prompt before overwrite. D23 + D23.1 (shipped together on `feature/d23-pm-file-management`, tag `v0.7`) closed the PM file-management surface — Save As, New File, Rename, Move, Delete, New Folder, Delete Folder — replacing the D19 "unsupportedSaveAs" alert and enabling self-cleaning smoke fixtures.

Together these deliverables close the **agentic dogfood loop** — the round-trip where Claude Code drops a `**Question:**` into a doc, the human types an answer inline, and Claude Code logs a `**Decision:**`. Pre-D14 the loop didn't write back at all; pre-D19 it only worked on local files; pre-D23 PM files couldn't be created/renamed/moved/deleted from inside the editor; with D23.1 the full file-CRUD surface lives in the editor.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d14_save_save_as` | Local Save / Save As | `EditorDocument.save()` + `saveAs(to:)`; atomic UTF-8 writes; ExternalEditWatcher pause/restart around writes; ⌘S / ⌘⇧S menu items; untitled-Save → NSSavePanel. |
| `d18_pm_connector_directory_tree` | Workspace connector + PortableMind directory tree (read-only) | `Connector` protocol; `LocalConnector` (replaces `FolderTreeModel`) + `PortableMindConnector`; multi-root sidebar; cross-tenant badges; unsupported-file disabling; PM read-only file open against Harmoniq REST. |
| `d19_pm_save_back` | PortableMind save-back | PM tabs editable; ⌘S routes through `Connector.saveFile`; multipart `PATCH /api/v1/llm_files/:id`; server-wins `updated_at` conflict-detection prompt with graceful network fallback; Save As stub for PM tabs (Q4 decision). |
| `d23_pm_file_management` | Unified PM file management | `Connector` protocol gains `createFile` / `renameFile` / `moveFile`; `PMFileOperations` shared service (single code path between modals and harness); Save As (⌘⇧S), New File (⌘⌥N), Rename + Move (sidebar context menu); reusable `PickConnectorTreeView` directory picker; `EditorDocument.updateAfterSaveAs` / `updateAfterRenameOrMove` mutators. Q4 from D19 spec retired. |
| `d23.1_pm_delete_and_folders` | PM delete-file + directory create/delete | `Connector` gains `deleteFile` / `createDirectory` / `deleteDirectory`; sidebar Delete… (NSAlert confirmation; child-count surfaced on directories) + New Folder…; `ConnectorTreeViewModel.upsertNode` / `removeNode` splice mutators; cascade-close of tabs whose file is inside a deleted directory. Bonus: retrofitted D23 saveAs/newFile/rename/move into the same splice — closes `TODO-D23-tree-splice`. |

## Common Tasks

- **"How does ⌘S work today?"** → For local tabs: `EditorDocument.save()` calls `LocalConnector.saveFile` which atomic-writes the buffer (D14 + D18 phase 1 routing). For PM tabs: `EditorDocument.save()` async-routes through `PortableMindConnector.saveFile` which does `GET /llm_files/:id` for the conflict check, then `PATCH /llm_files/:id` with multipart body if the server `updated_at` matches (D19).
- **"How does the editor avoid file-watcher echo-loops on save?"** → D14 established the pattern: `writeAndRewatch` stops the watcher, writes, restarts the watcher. PM saves don't have this concern (PM is API-mediated, not filesystem).
- **"What's the conflict-detection contract?"** → `specs/d19_pm_save_back_spec.md` Q2 + Decision log. **Server-wins warning** before overwrite. Network-class meta-GET failures fall through to PATCH (last-writer-wins). Auth/server-class failures propagate.
- **"How are PortableMind paths formatted in the UI?"** → PM display paths use the `LlmDirectory.path` convention (`/`, `/projects`, `/projects/2024/docs`) — see `Sources/Connectors/PortableMind/PortableMindConnector.swift`. Cross-tenant nodes carry a `TenantInfo` rendered as a badge (see D18 phase 4 wiring).
- **"How do I drive a PM save from the harness?"** → Three actions: `connector_save_focused {force?}` for the connector-level save (with optional force-bypass of conflict check); `attempt_save_focused` for the user-facing flow including the conflict NSAlert; `dismiss_conflict_dialog {choice: overwrite|cancel}` for programmatic dialog dismissal. Full recipe in `testing/d19_pm_save_back_manual_test_plan.md` § cross-cutting harness recipe.
- **"How does the editor create / rename / move / delete a PM file?"** → All seven D23+D23.1 ops go through `PMFileOperations` (`Sources/Workspace/PMFileOperations.swift`) — the modals AND the harness call the same service methods. The service routes to `Connector.createFile` / `renameFile` / `moveFile` / `deleteFile` / `createDirectory` / `deleteDirectory`; `PortableMindConnector` implements them via `PortableMindAPIClient`. Tab rebinding after rename/move goes through `EditorDocument.updateAfterRenameOrMove`; sidebar tree refreshes incrementally via `ConnectorTreeViewModel.upsertNode` / `removeNode`.
- **"What's the self-cleaning smoke recipe?"** → Create a scratch dir via `pm_create_directory`, run operations inside it, cascade-delete the dir via `pm_delete_directory` (the API client always passes `?cascade=true`). PM tenant has zero residue after a clean run. Documented in `testing/d23_pm_file_management_manual_test_plan.md`.
- **"How do I drive PM file management from the harness?"** → Seven actions, all routed through `PMFileOperations`: `pm_save_as`, `pm_new_file`, `pm_rename`, `pm_move`, `pm_delete_file`, `pm_create_directory`, `pm_delete_directory`. Single code path with the UI.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-26 | **Atomic UTF-8 write** for local save. Watcher pause/restart guard around the write to prevent echo. | D14 COMPLETE |
| 2026-04-27 | **Connector protocol is async by default**, even for local IO. Uniform call-site shape across all backends. | D18 spec |
| 2026-04-27 | **PM tree shows cross-tenant content with badges.** PM users see files shared from EpicDX, Rock Cut, etc., attributed via `TenantInfo`. | D18 spec |
| 2026-04-27 | **Save semantics (Q1):** Save-on-⌘S only for D19. Auto-save deferred. | D19 spec |
| 2026-04-27 | **Conflict resolution (Q2):** Server-wins warning. GET-before-PATCH; on conflict, modal Overwrite / Cancel. Graceful network fallback. | D19 spec |
| 2026-04-27 | **Save UX during in-flight save (Q3):** Optimistic — keep editor responsive; non-blocking error on failure. | D19 spec |
| 2026-04-27 | **Save As / rename / move on PM tabs (Q4):** Out of scope for D19; ⌘⇧S presents an unsupported-feature dialog. **D23+ commits the unified PM file-management deliverable** (rename / move / new-file at chosen location). | D19 spec |
| 2026-04-28 | **`Connector.openFile` returns `(Data, ConnectorNode)`** — refreshed node carries the meta `updated_at` so the conflict-detection baseline is set on first save (not just second). | D19 phase 4 finding F1 |
| 2026-05-08 | **Custom AppKit+SwiftUI modals over `NSSavePanel`** for PM file ops (Q1). NSSavePanel binds to the macOS filesystem; PM is a remote tree. Reusable `PickConnectorTreeView` for the picker. | D23 spec |
| 2026-05-08 | **Save As switches the existing tab to the new node** (Q2; TextEdit semantics — no phantom orphan). | D23 spec |
| 2026-05-08 | **`PATCH /api/v1/llm_files/:id` move uses `directory_path` (path string), not numeric `llm_directory_id`** — Q9 corrected during phase 1 endpoint spike. | D23 phase 1 |
| 2026-05-08 | **Hard delete with NSAlert confirmation** (Q1 in D23.1 spec). Server has no Trash table; matches the destructive semantics directly. Directory delete alert surfaces child-count when known. | D23.1 spec |
| 2026-05-08 | **`createDirectory` request body uses `path` field** (not just `parent_path` + `name`) — server's `validates :path` fires before `before_validation :set_parent_path`. Surfaced live in phase 2+3 smoke. | D23.1 deviation §1 |
| 2026-05-08 | **`deleteDirectory` always passes `?cascade=true`** — UX collects confirmation via NSAlert with child-count, so the API client supplies cascade unconditionally. | D23.1 deviation §2 |
| 2026-05-08 | **Sidebar tree refreshes incrementally** for all 7 PM ops via `ConnectorTreeViewModel.upsertNode` / `removeNode` — closes the lingering `TODO-D23-tree-splice` debt. | D23.1 deviation §4 |

## Dependencies

- **Predecessors:** `01_foundation` (project), `02_authoring_basics` (mutations that produce dirty buffers), `03_workspace` (sidebar that the connector tree replaces; tabs that PM origin tabs use; D25's Reveal-in-Tree consumes the tree splice helpers introduced here), `05_tables` (table content saved through these connectors).
- **Successors (committed but not yet started):**
  - **D20** — Connection-management UX (replaces the Debug-menu Token affordance).
  - **D26** — Full directory CRUD (rename / move). D23.1 only covered create + delete.
- **Side-quests landed mid-stream:**
  - **i04** — file-based bearer-token storage stopgap (in `docs/issues_backlog.md`); replaces broken cdhash-bound Keychain ACL on ad-hoc-signed builds. Reverts when Apple Developer enrollment lands.
  - **D22** — tab right-click Copy Path / Copy Relative Path. Surfaced during D19 phase 4 dogfood. Documented in `docs/roadmap_ref.md`.
