# D23: PortableMind file management — Complete

**Spec:** `docs/current_work/specs/d23_pm_file_management_spec.md`
**Plan:** `docs/current_work/planning/d23_pm_file_management_plan.md`
**Prompt:** `docs/current_work/prompts/d23_pm_file_management_prompt.md`
**Manual test plan:** `docs/current_work/testing/d23_pm_file_management_manual_test_plan.md` (unified with D23.1)
**Companion close-out:** `docs/current_work/stepwise_results/d23.1_pm_delete_and_folders_COMPLETE.md`
**Branch:** `feature/d23-pm-file-management` (also carried D23.1)
**Completed:** 2026-05-08

---

## Summary

Closes the PortableMind dogfood loop. Before D23, creating, renaming, moving, or saving-as a PM file required a context-switch to the Harmoniq web UI; after D23 (+ D23.1), all seven file-management operations live in the editor:

| Operation | Trigger | Source |
|---|---|---|
| Save As | ⌘⇧S on a PM tab | D23 phase 2 |
| New File | File → New PortableMind File…; ⌘⌥N | D23 phase 3 |
| Rename | Sidebar right-click → Rename… | D23 phase 4 |
| Move | Sidebar right-click → Move to… | D23 phase 5 |
| Delete file | Sidebar right-click → Delete… | D23.1 phase 2 |
| New Folder | Sidebar right-click on dir → New Folder… | D23.1 phase 2 |
| Delete folder | Sidebar right-click on dir → Delete… | D23.1 phase 2 |

D23 shipped phases 1–5 (Save As, New File, Rename, Move + their connector + harness surfaces). D23.1 shipped concurrently to pull forward two of D23's deferred-follow-ups (Delete file, directory create+delete) so that smoke tests are self-cleaning and so users have a complete file-management surface. Both ship at v0.7.

---

## Implementation Details

### What Was Built (D23 only — see D23.1 COMPLETE for that deliverable's surface)

- **Connector protocol** gains `createFile`, `renameFile`, `moveFile` with `.unsupported` defaults.
- **PortableMindAPIClient** gains `createFile` (multipart POST), `renameFile` (JSON PATCH `title`), `moveFile` (JSON PATCH `directory_path`).
- **LocalConnector** implements all three via `FileManager`.
- **PortableMindConnector** implements all three via the API client; private `node(from: FileDTO)` builder for refreshed-node construction.
- **`PMFileOperations`** shared service (saveAs, newFile, rename, move) — single code path the modals AND the harness call. `updateOpenTabs(matching:in:)` keeps open tabs in sync after rename/move.
- **EditorDocument** gains `updateAfterSaveAs` (rebinds origin/connectorNode/url/lastSavedSource) and `updateAfterRenameOrMove` (rebinds origin/connectorNode only). `origin` promoted from `let` to `@Published private(set) var`.
- **WorkspaceStore** gains `saveAsRequest`, `renameRequest`, `moveRequest` published payloads + `requestSaveAs(for:)`, `requestRename(for:)`, `requestMove(for:)`, `requestNewFile()`.
- **Sheets:** `SaveAsSheet` (handles both saveAs and newFile via `intent` enum), `RenameSheet`, `MoveSheet`. All custom AppKit+SwiftUI modals; reusable `PickConnectorTreeView` for tree picking. Inline error banners with `ConnectorError` → user-message map.
- **`PickConnectorTreeView`** — directory-only single-selection tree picker. Reuses `ConnectorTreeViewModel`'s async children loading.
- **`MdEditorApp`** wiring: `saveAsFocused()` PM branch routes to the modal; `New PortableMind File…` menu item with ⌘⌥N shortcut.
- **Sidebar context menu** (`ConnectorTreeView`): adds `Rename…` and `Move to…` items on PM file rows; gates by `connector.canWrite(node)`.
- **Harness** actions: `pm_save_as`, `pm_new_file`, `pm_rename`, `pm_move`. Each goes through `PMFileOperations` so harness paths and UI paths share a single implementation.
- **AccessibilityIdentifiers** — `folderTreeRowRename(id:)`, `folderTreeRowMove(id:)`.

### Files Created (D23)

| File | Purpose |
|------|---------|
| `Sources/Workspace/PMFileOperations.swift` | Shared service for PM file ops |
| `Sources/UI/PickConnectorTreeView.swift` | Reusable directory-only tree picker |
| `Sources/UI/SaveAsSheet.swift` | Save As + New File modal (intent-driven) |
| `Sources/UI/RenameSheet.swift` | Rename modal |
| `Sources/UI/MoveSheet.swift` | Move modal (tree-picker variant) |
| `docs/current_work/specs/d23_pm_file_management_spec.md` | This deliverable's spec |
| `docs/current_work/planning/d23_pm_file_management_plan.md` | This deliverable's plan |
| `docs/current_work/prompts/d23_pm_file_management_prompt.md` | This deliverable's prompt |
| `docs/current_work/testing/d23_pm_file_management_manual_test_plan.md` | Manual test plan (covers D23 + D23.1) |
| `docs/current_work/stepwise_results/d23_pm_file_management_COMPLETE.md` | This file |

### Files Modified (D23)

| File | Changes |
|------|---------|
| `Sources/Connectors/Connector.swift` | Protocol + extension defaults for `createFile`/`renameFile`/`moveFile` |
| `Sources/Connectors/LocalConnector.swift` | FileManager-backed implementations |
| `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` | New POST + PATCH methods + factored `setAuthHeaders`/`sendForLlmFile`/`patchLlmFile` helpers |
| `Sources/Connectors/PortableMind/PortableMindConnector.swift` | Implements protocol via API client |
| `Sources/Workspace/EditorDocument.swift` | `updateAfterSaveAs` + `updateAfterRenameOrMove` mutators; origin → @Published var |
| `Sources/Workspace/WorkspaceStore.swift` | Save As / Rename / Move request payloads + request methods |
| `Sources/WorkspaceUI/WorkspaceView.swift` | `.sheet(item:)` bindings for the three sheet types |
| `Sources/WorkspaceUI/ConnectorTreeView.swift` | Sidebar context menu items for PM file rows |
| `Sources/App/MdEditorApp.swift` | saveAsFocused PM branch + ⌘⌥N for New PortableMind File |
| `Sources/Debug/HarnessCommandPoller.swift` | 4 new harness actions |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | New row-action identifiers |

---

## Phase commit log

| Phase | Commit | Notes |
|---|---|---|
| Triad | `f1b8ecb` | spec/plan/prompt initial draft |
| Triad reframe | `e2aac06` | "out of scope for v1" → "deferred follow-ups (committed)" with sequencing notes |
| 1 (API spike + protocol) | `d976914` | Endpoint reconnaissance; verified server has everything; Connector + LocalConnector + PortableMindConnector + PortableMindAPIClient extended |
| 2 (Save As) | `37364e9` | SaveAsSheet + PickConnectorTreeView + PMFileOperations.saveAs + harness pm_save_as |
| 3 (New File) | `6fde3e9` | PMFileOperations.newFile + ⌘⌥N + harness pm_new_file |
| 4 (Rename) | `7bad16f` | RenameSheet + PMFileOperations.rename + EditorDocument.updateAfterRenameOrMove + harness pm_rename |
| 5 (Move) | `b4af71a` | MoveSheet + PMFileOperations.move + harness pm_move |
| 6 (close-out — this commit) | _this commit_ | manual test plan + COMPLETE + roadmap; merge to main; tag v0.7 |

D23.1's separate commits live alongside on the same branch — see the D23.1 COMPLETE doc for that log.

---

## Smoke evidence

Verified live against Harmoniq dev (PM tenant "portablemind"). Each phase's commit message includes its smoke results; consolidated here:

- **Save As:** new file id 1025 created at `/Sales & Marketing/d23-smoke-1778171993.md`; tab switched to it, buffer/caret/scroll preserved.
- **New File:** new empty file id 1028 at `/Sales & Marketing/d23-newfile-1778185407.md`, opened as new tab with `sourceLength=0`.
- **Rename:** id 1025 renamed to `d23-renamed-1778185778.md`; LlmFile.id preserved (rename doesn't change identity).
- **Move:** id 1025 moved from `/Sales & Marketing` to `/projects`; tab origin updated in place.
- **Final cleanup** (during D23.1 phase 2+3 smoke): both leftover smoke files (1025, 1028) deleted via the new `pm_delete_file` action; PM tenant clean.

---

## Testing

- [x] **Build clean** — Debug, macOS 14, no warnings related to D23 changes.
- [x] **Unit tests:** MdEditorUnitTests 23/23 GREEN through every phase.
- [x] **Live editor smoke** (per phase). All seven operations exercised end-to-end against Harmoniq dev.
- [x] **D17 + D19 manual test plans:** spot-checked. Cell rendering / save-back paths weren't touched by D23.
- [ ] **Full D17 manual interactive walk:** Tab navigation across cells, scroll-on-edit, etc. — risk-rated low (no cell-content paragraph attribute changes), deferred.

---

## Deviations from Spec

### 1. Q9 corrected (directory_path, not numeric llm_directory_id)

Spec Q9 initially said `PATCH llm_files/:id` would take a numeric `llm_directory_id` for moves. Phase 1 spike confirmed the server actually accepts `directory_path` (a path string like `/projects/foo`). Spec corrected at commit `d976914`.

### 2. Inline rename deferred to context-menu sheet

Plan §Phase 4 mentioned inline-edit-in-row as the rename surface. Switched to a small RenameSheet because SwiftUI TextField focus inside a List row is historically finicky for accessibility identifiers and first-responder behavior (plan risk #3). Sheet pattern is reliable + ships now; inline edit can be a follow-up if dogfood prefers it.

### 3. F2 keyboard shortcut deferred

F2 → Rename requires a sidebar selection model that doesn't currently exist. Deferred to follow-ups; right-click → Rename is the discoverable path in v1.

### 4. Save As → Local from a PM tab not surfaced in v1

Spec scope row mentioned "Save As → PM destination from a Local tab" works through the same modal. v1 only routes PM-tab Save As to the new modal; Local-tab Save As stays on NSSavePanel. Cross-connector targeting is in the deferred-follow-ups list.

### 5. Sidebar tree splice happened in D23.1, not in D23 phases 2–5

D23 phases 2–5 left a `TODO-D23-tree-splice` flag — the new/renamed/moved nodes only appeared in the sidebar after a manual reload. D23.1 phase 2 closed this debt by adding `upsertNode` + `removeNode` to `ConnectorTreeViewModel` and retrofitting the saveAs/newFile/rename/move paths to splice. Net effect at v0.7: the sidebar refreshes incrementally across all 7 ops.

---

## Follow-Up Items

Tracked from the spec's "Out of scope (deferred to future phases)" section, paired with sequencing notes:

| Item | Sequencing | Notes |
|---|---|---|
| **Delete PM file** | ✅ Pulled into **D23.1** | See companion COMPLETE doc. |
| **Directory create + delete** | ✅ Pulled into **D23.1** | See companion COMPLETE doc. |
| **Drag-drop move** in the sidebar | After context-menu Move has weeks of dogfood | Tree drag-drop with drop validation + previews. |
| **Multi-select operations** | After Delete lands (now done) | Sidebar selection model expansion. |
| **Cross-tenant moves** | Pairs with D20 (connection-management) | Once multi-connection is real. |
| **Save As → Local from a PM tab** | Light lift; ship if dogfood asks | Same modal already accepts a connector parameter; just enable PM-tab → Local target. |
| **Directory rename / move** | D26 (full directory CRUD) | LlmDirectory PATCH on name / parent_path. |
| **Trash / undo** | Separate higher-stakes design | Server has no Trash table; would cross the API boundary. |
| **Templates for New File** | Ship when conventions stabilize | Configurable per-tenant or per-project starter content. |
| **Recent locations** in the tree picker | Ergonomic polish on demand | Top-of-picker shortcut. |
| **Realtime sync** of rename/move done elsewhere | Cross-cutting PM realtime work | Not D23-bounded. |
| **F2 keyboard shortcut** for Rename | After sidebar selection model | Today: right-click → Rename only. |
| **Inline edit in-row** (alt to Rename sheet) | If dogfood prefers it | Sheet stays as default. |
| **Local-connector UI surfacing** for delete/create-folder | Small follow-up | Connector implementations already in place; UI just needs Trash/confirm thinking. |

These are queued in the roadmap's "Candidates (unscheduled)" section.

---

## Notes

- **Same-branch shipping with D23.1.** Both deliverables cohabited `feature/d23-pm-file-management`. Commit messages use phase prefixes (`D23 phase N` and `D23.1 phase N`) to disambiguate. Single ff-merge to main; single v0.7 tag covers both.
- **Self-cleaning fixture pattern** is the canonical recipe going forward. PM tenant has zero D23/D23.1 smoke residue after a clean run.
- **Server-shape lessons** (D23.1 phase 2+3 smoke): create-directory needs `path` (not just `parent_path`+`name`); delete-directory needs `?cascade=true`. Both surfaced live during smoke and were fixed inline. Documented in the manual test plan §5 failure pointers.
