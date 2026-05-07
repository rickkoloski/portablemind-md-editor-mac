# D23 Prompt — PortableMind file management

You are working on `~/src/apps/md-editor-mac` on branch `feature/d23-pm-file-management`. Your job is to close the PortableMind dogfood loop by adding **Save As / New File / Rename / Move** for PM-origin tabs, replacing the "Save As not yet supported" alert from D19.

This unblocks daily PM authoring inside the editor — today, creating a new PM doc requires a context-switch to Harmoniq's web UI, then back to the editor. After D23, ⌘⌥N drafts a new PM file directly; ⌘⇧S forks an existing PM tab to a different location; right-click in the sidebar renames or relocates a file.

The four operations share the same backend API (LlmFile CRUD) and are scoped as one deliverable per the D19 Q4 decision.

---

## Read first (in this order)

1. `docs/current_work/specs/d23_pm_file_management_spec.md` — the contract. Decision log Q1–Q9 captures all nine scope answers (CD-approved 2026-05-07). Q1 (custom modal, not NSSavePanel), Q2 (Save As switches the existing tab), and Q5 (no overwrite-on-conflict in v1) are the substantive UX decisions.
2. `docs/current_work/planning/d23_pm_file_management_plan.md` — six phases with DOD per phase. Phase 1 is an API spike that gates the deliverable on the model_api endpoint surface.
3. `docs/current_work/stepwise_results/d19_pm_save_back_COMPLETE.md` — D19's PM save infrastructure that D23 extends. Same Connector protocol, same APIClient pattern, same conflict-detection semantics carried forward.
4. `Sources/Connectors/Connector.swift` — the protocol you're extending. D23 adds `createFile`, `renameFile`, `moveFile`.
5. `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` — the API client surface. D19 added `updateFile` (PATCH); D23 adds `createFile` (POST) + extends PATCH to cover rename/move.
6. `docs/engineering-standards_ref.md` §2.1 — `accessibilityIdentifier` on every view. The new modals (SaveAsModal, MoveFileModal) need them on every interactive element.
7. Memory pointers (`~/.claude/projects/-Users-richardkoloski-src/memory/`):
   - `feedback_no_shortcuts_pre_users.md` — pre-user products: build the hard thing right.
   - `khoa_pham_customer_stakeholder.md` — early-adopter customer evaluating the editor as Jira replacement; PM file management is core to that evaluation.
   - `feedback_focus_stealing.md` — modals are focus-stealing; ask before invoking on a single-screen day.
   - `harmoniq_test_automation_project.md` — Project #52 covers test pipeline coordination if backend changes are needed.

---

## Reference behavior

PM file management mirrors familiar editors:
- **Save As** matches what TextEdit does (write the buffer to a new location; the original is unchanged; the open document is now the new file).
- **New File** matches ⌘N in any editor (empty buffer; on save, persists at the chosen location).
- **Rename** matches Finder's F2 / right-click → Rename (inline edit on the row; ⏎ commits, ⎋ cancels).
- **Move** matches Finder's "Move to…" (opens a folder picker; choose target; commit moves the file).

The deliberate divergence: **the tree picker is custom AppKit**, not NSSavePanel-with-accessoryView, because PM is a remote tree (not a filesystem) and we want to reuse the picker for Move and future tree-target dialogs (Q1).

---

## Where to work

Existing files (extended):

- `Sources/Connectors/Connector.swift` — protocol gains `createFile`, `renameFile`, `moveFile`.
- `Sources/Connectors/LocalConnector.swift` — implements the new methods via `FileManager`.
- `Sources/Connectors/PortableMind/PortableMindConnector.swift` — implements via `PortableMindAPIClient`.
- `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` — adds `createFile`, `renameFile`, `moveFile` HTTP methods.
- `Sources/App/MdEditorApp.swift` — `saveAsFocused` PM branch replaces the alert with the new modal; `newPortableMindFile` menu item + ⌘⌥N shortcut added.
- `Sources/Workspace/EditorDocument.swift` — small mutator so `connectorNode` and `url` can be replaced after Save As / Rename / Move.
- `Sources/Workspace/SidebarView.swift` (or wherever the file-tree row renders) — context menu items, F2 keyboard shortcut, inline rename mode.

New files:

- `Sources/UI/PickConnectorTreeView.swift` — the reusable tree picker (Save As, New File, Move all use it).
- `Sources/UI/SaveAsModal.swift` — the Save As / New File modal.
- `Sources/UI/MoveFileModal.swift` — the Move modal (variant of SaveAsModal).
- `Sources/Workspace/PMFileOperations.swift` — shared service the modals AND the harness call. Centralizes the post-mutation tab-lifecycle handling.

Harness extensions (`#if DEBUG`):

- `Sources/Debug/HarnessCommandPoller.swift` — new actions `pm_save_as`, `pm_new_file`, `pm_rename`, `pm_move`. Each goes through `PMFileOperations` so harness paths and UI paths share a single implementation.

---

## Phase-by-phase guidance

### Phase 1 — API spike

**Don't proceed past phase 1 without confirming the model_api endpoints exist.** Read `reference-code/model_api/app/controllers/api/v1/llm_files_controller.rb` and verify `POST` (create) and `PATCH` (with `name` / `llm_directory_id` for rename/move) work. If anything is missing, surface a `**Question:**` to CD with the gap + a proposed model_api PR scope.

After endpoints are verified, extend `Connector` with the three new methods + provide default `.unsupported` implementations. Implement on `LocalConnector` (FileManager-backed) and `PortableMindConnector` (APIClient-backed). The cache mutation API (`upsertNode` / `removeNode`) lives on `PortableMindConnector` for now; if `LocalConnector` ever needs it, it can be hoisted to the protocol later.

The phase 1 deliverable is **plumbing without UI**. The next phase wires the first UI consumer (Save As).

### Phase 2 — Save As

The visible milestone for the Save As path. Build `PickConnectorTreeView` minimally — just disclosure + selection. No search, no recents, no favorites in v1.

Replace `MdEditorApp.saveAsFocused`'s PM branch with a `SaveAsModal.present(for: doc)` call. The modal stays open across errors; only Save success or Cancel dismisses it.

`PMFileOperations.saveAs(...)` is the shared entry point — both the modal and the new harness action call it. The function:
1. Calls `connector.createFile(in: parent, name: filename, bytes: doc.source.data(using: .utf8)!)`.
2. On success: switches `doc.connectorNode` and `doc.url` to the new node (Q2 — same tab, new file).
3. Returns the refreshed node so the modal closes and the sidebar refreshes.

### Phase 3 — New File

Wires the menu item + shortcut to `PMFileOperations.newFile(in: connector)`. The modal opens in "newFile" mode (empty buffer, default filename "Untitled.md"). On success a new tab opens; the user types into the empty buffer.

### Phase 4 — Rename

The trickiest UX. SwiftUI's `TextField` inside a List row is finicky for focus management; expect to spike if the row's first-responder behavior fights the rename mode. Engineering-standards §2.1 — every interactive element (the rename TextField, the row in non-rename mode) needs an `accessibilityIdentifier`.

Server PATCH with `name=newName` should return the refreshed node. On success, splice into the cached tree; if the file is open in any tab, update the tab's `connectorNode` (preserving the buffer + caret + scroll).

### Phase 5 — Move

The `MoveFileModal` is a SaveAsModal variant — same tree picker, no filename field, Save → "Move" label. The tree picker DISALLOWS selecting the file's current parent (no-op move).

Server PATCH with `llm_directory_id=newParentID` should succeed. Cache mutation: remove the node from its old parent's children list, upsert under the new parent.

### Phase 6 — Close-out

Manual test plan covers each operation × (success / each error mode). Harness recipes inline. COMPLETE doc references the spec, plan, prompt, harness actions, and any model_api PR that shipped alongside.

---

## Conventions

- **Branch:** `feature/d23-pm-file-management` (already created).
- **Commits:** one per phase. Phase 1 commit may include a small `spikes/d23_api_recon/README.md` note if the endpoint inventory is non-trivial.
- **Multi-repo:** if backend gaps surface in phase 1, the model_api PR is its own branch (`feature/d23-llm-files-write-endpoints` or similar) on `reference-code/model_api` (per `harmoniq_*` memories — backend goes off `development`, not `master`). The md-editor branch waits for the model_api PR to merge.
- **Harness-first verification.** UI modal flows have harness analogs so headless test drivers can exercise every operation.
- **Manual test plan is a first-class artifact** — D17 / D19 / D24 conventions carry forward.
- **Markdown dogfood markers:** `**Question:**` / `**Decision:**` / `**Bug:**` / `**Assumption:**`, own line, greppable.
- **Focus-stealing protocol:** modals (Save As, Move) ARE focus-stealing by definition; manual smoke testing requires app-frontmost. Per `feedback_focus_stealing.md`, ask before launching on a single-screen day.
- **Engineering-standards §2.1:** accessibilityIdentifier on every interactive element in the new modals + rename TextField.

---

## Done means

1. All six phases complete; one commit per phase on `feature/d23-pm-file-management`.
2. **Save As** on a PM tab opens the new modal; user picks target → file created → tab switches.
3. **Save As** on a Local tab → PM destination works through the same modal.
4. **New File** menu item + ⌘⌥N create a fresh empty PM file.
5. **Rename** via inline edit (sidebar + F2) updates the file's name.
6. **Move** via context menu + tree picker relocates the file under a new directory.
7. Open tabs preserve buffer / caret / scroll across rename + move.
8. Sidebar tree refreshes incrementally; expand state preserved.
9. Inline errors surface for: network, write-forbidden, quota, name-conflict.
10. `xcodebuild test` GREEN.
11. D17 + D19 manual test plans rerun GREEN.
12. D23 manual test plan walked end-to-end with results recorded.
13. D23 COMPLETE doc references spec, plan, prompt, manual test plan, harness actions, any backend PR.
14. Roadmap reflects D23 ✅.
15. **Deferred items carried forward.** Spec §"Out of scope for v1" enumerates 10 follow-ups (Delete, drag-drop, multi-select, cross-tenant moves, Save As → Local from PM, folder CRUD, overwrite prompts, templates, recents, realtime sync). Phase 6 COMPLETE doc §Follow-Up Items lists them all with proposed sequencing notes; the roadmap's "Candidates (unscheduled)" gets the new entries added so they're trackable as future deliverables.
16. Branch merged to `main`; tag `v0.7` annotated and pushed (D23 ships a meaningful chunk of PM-integration capability — minor-version bump from v0.6.x).
