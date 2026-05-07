# D23 — PortableMind file management

**Status:** DRAFT — frame for review. Decision log resolves Q1–Q9 up front; please confirm or push back before plan-time.

**Trace:**
- `docs/vision.md` Principle 1 (Word/Docs-familiar authoring) and Principle 2 (PortableMind-aware desktop surface).
- `docs/portablemind-positioning.md` — PM tabs are first-class citizens alongside local files.
- `docs/current_work/stepwise_results/d19_pm_save_back_COMPLETE.md` — D19 Q4 decision (2026-04-27) committed Save As + New File + rename + move as a unified D23+ deliverable. Save As on a PM tab today shows an "unsupported" alert.
- `docs/issues_backlog.md` — none directly; this is forward feature work, not a defect fix.
- `chronicle_by_concept/06_persistence_and_connectors/specs/d18_pm_connector_directory_tree_spec.md` — Connector protocol (the surface this deliverable extends).

**Position in roadmap:** D23 — closes the PM dogfood loop. Today you can edit existing PM files (D19) but you can't create new ones, rename them, or move them through the editor — those round-trips have to go through Harmoniq's web UI. Independent of D20 (connection-management UX) and decoupled from Apple Developer Program enrollment. Apple Developer state is currently de-prioritized per CD direction (2026-05-07); the i04 file-based token stopgap continues to hold.

---

## Why now

D19 (2026-04-28) made PM tabs editable — ⌘S routes through `Connector.saveFile`. But the PM tab's lifecycle is still incomplete:

- **Save As** on a PM tab triggers an explicit "not yet supported" alert (`MdEditorApp.saveAsFocused` lines 215-223). Created during D19 phase 3 as the Q4 deferral path.
- **New File** in PM is impossible from the editor. The only way to create a PM file is via the Harmoniq web UI; you then ⌘O / cmd-click in the sidebar to open it.
- **Rename / Move** of an existing PM file: same — has to go through the web UI.

Net effect on dogfood: "I want to draft a new spec doc in PM" requires three context-switches (open Harmoniq web, create empty file, switch back to md-editor, navigate sidebar to find it). For Rick this is a daily friction point in PortableMind authoring. D23 collapses it to a single ⌘N (or ⌘⇧S for an existing local doc) inside the editor.

The four operations share the same connector / API surface (LlmFile CRUD on the server side), so they ship as one deliverable.

---

## Scope

In scope:

| Operation | Trigger | Today's behavior | After D23 |
|---|---|---|---|
| **Save As** (PM tab) | ⌘⇧S on a PM tab; File → Save As… | Alert: "Save As not yet supported" | Modal with PM tree picker → choose target directory + filename → connector creates new file → tab switches to it |
| **Save As → PM** (Local tab) | ⌘⇧S on a local tab, choose "PortableMind" instead of a local folder | NSSavePanel only allows local destinations | Same modal as above; the Save As dialog can target any reachable connector |
| **New File** (PM) | File → New PortableMind File…; ⌘⌥N | No menu item exists | Same modal as Save As but with an empty initial buffer; on confirmation creates the file and opens it |
| **Rename** (PM) | Sidebar tree row right-click → Rename; F2 (Finder convention) | Right-click menu doesn't include Rename for PM nodes | Inline edit in the sidebar tree row → connector renames → tab title updates if the file is open |
| **Move** (PM) | Sidebar tree row right-click → Move to… | Not supported | Modal with PM tree picker → choose new parent directory → connector moves → tab path updates if open |

Out of scope (deferred to future deliverables):

- **Delete** of PM files. Higher-stakes destructive op; warrants its own dialog + undo/trash semantics. Deferrable.
- **Drag-drop in the sidebar tree** for move. Significant UX scope (drag previews, drop validation, multi-select). Context-menu Move flow is the v1.
- **Multi-select** operations (rename batch, move multiple). v1 is single-node only.
- **Cross-tenant moves.** A move from one tenant's tree to another's is conceptually two operations (delete from source + create in target) and crosses authorization boundaries; deferred. The tree picker in v1 only shows the current tenant's tree.
- **Save As → Local** from a PM tab. (Save As on a PM tab → PM destination only in v1; "Save a copy to my disk" can ship later if dogfood asks.)
- **New Folder / directory CRUD.** v1 creates files inside existing directories only. Folder mutation is a separate API surface and v1's pickers always show the current tree.
- **Conflict-resolution on rename/move.** If the target name already exists, v1 errors out; the user picks a different name. No overwrite-or-cancel dialog (we don't typically silently destroy data on rename).

---

## UX flows

### Save As (from a PM tab)

1. User triggers ⌘⇧S or File → Save As… on a PM tab.
2. **Save As… modal opens** (custom AppKit modal, not NSSavePanel — see Q1):
   - Filename text field (prefilled with current filename; user can edit).
   - Connector picker (segmented control or dropdown): "PortableMind" by default for PM-origin tabs, "Local" available too if the user wants to fork a copy to disk (Save As → Local is in scope).
   - Tree picker (per the selected connector). For PM, shows the current tenant's directory tree with disclosure controls; the user navigates to the target directory and selects it. For Local, NSSavePanel-style folder browsing.
   - Save / Cancel buttons.
3. On Save:
   - Validate (non-empty filename, doesn't conflict with sibling per Q5).
   - Call `connector.createFile(at: parentDirectory, name: filename, bytes: editorContents)`.
   - On success: open the new node in a tab (replace current tab? Q7), close the modal.
   - On error: surface inline in the modal (don't dismiss).

### New File

1. User triggers File → New PortableMind File… or ⌘⌥N (Q4 — discoverable and not in conflict with ⌘N for new local doc).
2. Same Save As modal as above, except:
   - Default filename suggestion is "Untitled.md".
   - The initial bytes are empty (or a one-line template — Q8).
3. On Save: connector creates the file, a new tab opens pointed at it.

### Rename (PM)

1. User right-clicks a PM file row in the sidebar tree (or selects a row and presses F2).
2. Context menu shows "Rename" (or F2 puts the row into edit mode directly).
3. **Inline rename** (Finder convention): the row's name label becomes a text field, prepopulated with the current name. User types, presses Return to confirm or Escape to cancel.
4. On Return:
   - Validate (non-empty, no `/`, doesn't conflict with siblings — Q5).
   - Call `connector.renameFile(node, to: newName)`.
   - On success: sidebar tree refreshes; if the file is open, its tab title updates and `EditorDocument.connectorNode` is replaced with the refreshed node. The buffer is preserved.
   - On error: revert the inline edit, show an inline error (red highlight + tooltip), let the user retry or Escape to cancel.

### Move (PM)

1. User right-clicks a PM file row → "Move to…" context menu item.
2. **Move modal** opens (custom AppKit modal, similar to Save As but read-only filename — only directory selection).
3. User picks new parent directory in the tree picker. Save / Cancel.
4. On Save:
   - Validate (target directory exists, no name conflict in target, not a no-op — Q5).
   - Call `connector.moveFile(node, to: targetDirectory)`.
   - On success: sidebar tree refreshes; if the file is open, its tab updates with the new node; the buffer is preserved.
   - On error: surface inline.

---

## Decision log

| Date | Decision | Decided by |
|---|---|---|
| 2026-05-07 | **Q1 — Save As modal: custom AppKit, not NSSavePanel.** NSSavePanel is local-FS-only; bolting a PM tree onto it via `accessoryView` is awkward and limits future capabilities (multi-connector targets, tenant-scoped trees). Build a small custom NSWindow-based modal with a tree picker view we can reuse for Move and future tree-target dialogs. Accepts the cost of writing accessibility / keyboard nav ourselves. Engineering-standards §2.1 (`accessibilityIdentifier` on every view) applies. | RAK |
| 2026-05-07 | **Q2 — Tab lifecycle on Save As.** When the user does Save As on a PM tab, **switch the existing tab to point at the new node** (don't open a second tab). Rationale: Save As semantics across most editors are "this is now a different file at a different location"; opening two tabs creates a phantom orphan tab pointing at the original (which the user explicitly wanted to fork from). For New File, a fresh tab is opened. | RAK |
| 2026-05-07 | **Q3 — Tab lifecycle on Rename / Move.** The tab stays open; the buffer is preserved across the operation. The tab's title and the document's `connectorNode` (and `lastSeenUpdatedAt`) refresh from the server's response. The buffer's dirty state is preserved (rename/move doesn't change content). Rationale: matches Finder's behavior on rename of an open file in TextEdit, and matches the dogfood expectation. | RAK |
| 2026-05-07 | **Q4 — Keyboard shortcuts.** ⌘⇧S → Save As (existing). **⌘⌥N → New PortableMind File** (new). Avoids stomping ⌘N (which keeps its existing meaning "New Local Document"). Discovery via the File menu. F2 → Rename in the sidebar (Finder convention; ⌥+drag → Move-Copy is a future drag-drop affordance, not v1). | RAK |
| 2026-05-07 | **Q5 — Name conflict handling.** v1: error out if the target name already exists in the destination directory. Modal stays open; the user picks a different name. Rationale: rename/move on existing data should never silently destroy anything; "overwrite the existing file" is a higher-stakes prompt that we can add later if dogfood asks for it. Save As may still be intentional (the user wants to overwrite a sibling) — for v1 also error out; a future Q can add an "overwrite existing" toggle. | RAK |
| 2026-05-07 | **Q6 — Cross-tenant scope.** v1's tree picker only shows the current tenant's directory tree. A user with multiple PM tenants must explicitly switch tenants (a future D20 connection-management concern) to target the other tenant's tree. Cross-tenant moves are not supported in v1 (decompose-into-create+delete plus authorization boundaries). | RAK |
| 2026-05-07 | **Q7 — Sidebar tree refresh model.** After any successful mutation (create / rename / move), the connector's cached tree gets the new node spliced in (or the old node updated/moved) and the sidebar re-renders. We do NOT do a full tree refetch — that's slow and would lose the user's expand state. The connector exposes a small mutation API (`upsertNode`, `removeNode`) the UI calls after each operation. | RAK |
| 2026-05-07 | **Q8 — New File initial content.** Empty buffer (zero bytes). Templating (e.g., a `# Untitled` heading) is parked — different users have different conventions and templates are ergonomic noise for v1. | RAK |
| 2026-05-07 | **Q9 — API endpoint surface.** Currently `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` only implements `PATCH /api/v1/llm_files/:id` (D19 save). D23 needs: `POST /api/v1/llm_files` (create), `PATCH /api/v1/llm_files/:id` extended (rename via `name`, move via `llm_directory_id`), and possibly `GET /api/v1/llm_directories/...` for the tree picker if not already covered by D18's children fetch. **Phase 1 spike verifies the model_api side has these endpoints** (likely yes — Rails LlmFiles CRUD is conventional); if any are missing, surface as a backend dependency before phase 2. | RAK |

---

## Edge cases

- **Save As when filename validates but the directory doesn't exist.** Tree picker only allows selecting existing directories; impossible by construction.
- **Save As when the user is editing a tab whose source has unsaved changes.** Save As writes the *current buffer* (with edits) to the new location. Original file untouched. Tab switches to new node (per Q2). The original is now untouched on the server with its original content.
- **Rename a file that's open in another app's window** (e.g., Harmoniq web UI). Server's PATCH on `name` succeeds; D19's conflict-detection on the next save handles the case where the OTHER user/tab edited concurrently. The web UI presumably refreshes via Harmoniq's realtime.
- **Move into a directory the user can't write to.** Connector returns `.writeForbidden` (existing error case from D19). Modal surfaces inline.
- **Network failure mid-operation.** Same `.network(Error)` handling as D19 save. Modal stays open with retry option.
- **Empty filename.** Disabled Save button until non-empty.
- **Filename containing `/`.** Disabled Save button with an inline hint ("Folders are not allowed in filenames; use Move to relocate.").
- **Storage quota exceeded** (Harmoniq returns 402 with `DOCUMENT_STORAGE_LIMIT_EXCEEDED` per D19's `.storageQuotaExceeded`). Modal surfaces the message with a link / hint to manage storage in Harmoniq web.
- **Rename to the same name** (no-op). Allowed; just close the editor (no-op on server is fine; a 200 response is enough). Or short-circuit client-side. Either is fine.
- **Move to the same parent directory** (no-op). Same as above.

---

## Acceptance criteria

1. **Save As on a PM tab** completes via the modal: user picks target directory + filename, connector creates the file, current tab switches to point at the new node, sidebar refreshes. Replaces the existing "unsupported" alert.
2. **Save As on a Local tab → PM destination** works through the same modal (the connector picker lets the user choose PM as the target).
3. **New File** menu item + ⌘⌥N shortcut create a fresh empty file at the user's chosen location and open it in a new tab.
4. **Rename** via inline edit in the sidebar (or F2) updates the file's name on the server and in the UI; the open tab's title refreshes.
5. **Move** via context menu and tree picker relocates the file under a new directory; the open tab's path updates.
6. **Sidebar tree refresh** is incremental — no full re-fetch on each operation; expand state is preserved across mutations.
7. **Error surfaces inline** in the modal for all failure modes (network, write-forbidden, quota, name-conflict). The ConnectorError → user-facing message map covers each case.
8. **Buffer state preserved** through rename and move; the editor doesn't reset the caret or scroll position.
9. **Manual test plan** at `docs/current_work/testing/d23_pm_file_management_manual_test_plan.md` covers each operation × success / each failure mode.
10. **Harness verification** — new actions for `pm_save_as`, `pm_new_file`, `pm_rename`, `pm_move` so harness drivers can exercise each flow without the UI modal. Drives reuse of the same connector calls that the UI invokes.
11. **D17 + D19 manual test plans rerun GREEN** — table rendering, in-place cell editing, save-back, conflict detection all unaffected. The Connector protocol additions are purely additive.

---

## Out of scope (deferred)

- **Delete PM file** — separate, higher-stakes deliverable.
- **Drag-drop move** in the sidebar — significant UX scope for v1.
- **Multi-select operations** — single-node only in v1.
- **Cross-tenant moves** — single-tenant tree picker in v1.
- **Save As → Local** from a PM tab (forking a copy to disk) — can ship later if dogfood asks.
- **New Folder / directory CRUD** — files only in v1.
- **Overwrite-on-conflict** prompt for Save As when a sibling already exists — v1 errors out.
- **Templates** for New File — empty buffer in v1.
- **Recent locations** in the tree picker — straight tree only in v1.

---

## Risks / open implementation questions

1. **API endpoint inventory (Q9).** Phase 1 spike confirms what `/api/v1/llm_files` accepts. If `POST` or PATCH-with-`llm_directory_id` is missing on the server side, this becomes a multi-repo deliverable (model_api + md-editor) rather than client-only. Per `feedback_feature_branch_threshold.md` that's still a single feature branch on each repo, but it doubles the scope.
2. **Tree picker reuse.** Save As, New File, and Move all use the same tree picker UI. Phase 2 builds it once and phases 3, 5 reuse. Risk: scope creep on the picker (search? recent locations? favorites?). v1 is straight tree, no extras. Defer ergonomics to dogfood-driven follow-ups.
3. **Sidebar inline rename UX.** SwiftUI's `TextField` inside a List row is finicky with focus management and accessibility identifiers. Phase 4 may need an AppKit fallback. Allocate spike time inside the rename phase if needed.
4. **F2 keyboard shortcut.** macOS apps don't all bind F2 to rename (Finder does; some don't). Verify it doesn't conflict with anything we have. Right-click → Rename is the always-discoverable path; F2 is the shortcut layer.
5. **`EditorDocument.connectorNode` mutability.** Currently `private(set)`. Rename/move need to update it. May require a small mutator added to `EditorDocument`. Phase 4/5 wires this.
6. **Realtime update surface.** If a third party (web UI) renames a PM file open in this editor, the editor doesn't know. D23 doesn't add realtime; D19's conflict-detection on save remains the safety net. Realtime is a future cross-cutting concern (memory: `harmoniq_test_automation_project.md` discusses Project #52).
7. **Harness reach.** Harness drives the file-based command poller, not the UI modal. New harness actions need to call into the same code paths the modal does (probably extracting a `PMFileOperations` service the modal and harness both invoke).
