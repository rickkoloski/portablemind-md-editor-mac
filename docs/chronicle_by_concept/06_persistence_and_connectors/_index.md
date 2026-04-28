# 06 — Persistence and Connectors

## Overview

Three deliverables that gave the editor "a way to save". D14 added local Save / Save As (atomic UTF-8 write through ExternalEditWatcher pause/restart guard, ⌘S / ⌘⇧S menu items, untitled-Save → Save As panel fallback). D18 introduced the `Connector` abstraction (one of the nine cross-OS abstractions in `docs/stack-alternatives.md` §3) and shipped `LocalConnector` + `PortableMindConnector` — the editor's storage backend went from "the local filesystem" to "any backend that conforms to a small async protocol". D19 made PortableMind tabs editable, with a server-wins conflict-detection prompt before overwrite.

Together these three deliverables close the **agentic dogfood loop** — the round-trip where Claude Code drops a `**Question:**` into a doc, the human types an answer inline, and Claude Code logs a `**Decision:**`. Pre-D14 the loop didn't write back at all; pre-D19 it only worked on local files; with D19 the same loop runs against PortableMind-stored docs.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d14_save_save_as` | Local Save / Save As | `EditorDocument.save()` + `saveAs(to:)`; atomic UTF-8 writes; ExternalEditWatcher pause/restart around writes; ⌘S / ⌘⇧S menu items; untitled-Save → NSSavePanel. |
| `d18_pm_connector_directory_tree` | Workspace connector + PortableMind directory tree (read-only) | `Connector` protocol; `LocalConnector` (replaces `FolderTreeModel`) + `PortableMindConnector`; multi-root sidebar; cross-tenant badges; unsupported-file disabling; PM read-only file open against Harmoniq REST. |
| `d19_pm_save_back` | PortableMind save-back | PM tabs editable; ⌘S routes through `Connector.saveFile`; multipart `PATCH /api/v1/llm_files/:id`; server-wins `updated_at` conflict-detection prompt with graceful network fallback; Save As stub for PM tabs (Q4 decision). |

## Common Tasks

- **"How does ⌘S work today?"** → For local tabs: `EditorDocument.save()` calls `LocalConnector.saveFile` which atomic-writes the buffer (D14 + D18 phase 1 routing). For PM tabs: `EditorDocument.save()` async-routes through `PortableMindConnector.saveFile` which does `GET /llm_files/:id` for the conflict check, then `PATCH /llm_files/:id` with multipart body if the server `updated_at` matches (D19).
- **"How does the editor avoid file-watcher echo-loops on save?"** → D14 established the pattern: `writeAndRewatch` stops the watcher, writes, restarts the watcher. PM saves don't have this concern (PM is API-mediated, not filesystem).
- **"What's the conflict-detection contract?"** → `specs/d19_pm_save_back_spec.md` Q2 + Decision log. **Server-wins warning** before overwrite. Network-class meta-GET failures fall through to PATCH (last-writer-wins). Auth/server-class failures propagate.
- **"How are PortableMind paths formatted in the UI?"** → PM display paths use the `LlmDirectory.path` convention (`/`, `/projects`, `/projects/2024/docs`) — see `Sources/Connectors/PortableMind/PortableMindConnector.swift`. Cross-tenant nodes carry a `TenantInfo` rendered as a badge (see D18 phase 4 wiring).
- **"How do I drive a PM save from the harness?"** → Three actions: `connector_save_focused {force?}` for the connector-level save (with optional force-bypass of conflict check); `attempt_save_focused` for the user-facing flow including the conflict NSAlert; `dismiss_conflict_dialog {choice: overwrite|cancel}` for programmatic dialog dismissal. Full recipe in `testing/d19_pm_save_back_manual_test_plan.md` § cross-cutting harness recipe.

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

## Dependencies

- **Predecessors:** `01_foundation` (project), `02_authoring_basics` (mutations that produce dirty buffers), `03_workspace` (sidebar that the connector tree replaces; tabs that PM origin tabs use), `05_tables` (table content saved through these connectors).
- **Successors (committed but not yet started):**
  - **D20** — Connection-management UX (replaces the Debug-menu Token affordance).
  - **D23+** — Unified PM file management (Save As + New File at chosen location, per Q4).
- **Side-quests landed mid-stream:**
  - **i04** — file-based bearer-token storage stopgap (in `docs/issues_backlog.md`); replaces broken cdhash-bound Keychain ACL on ad-hoc-signed builds. Reverts when Apple Developer enrollment lands.
  - **D22** — tab right-click Copy Path / Copy Relative Path. Surfaced during D19 phase 4 dogfood. Documented in `docs/roadmap_ref.md`.
