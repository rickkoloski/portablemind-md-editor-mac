# D23 + D23.1: PortableMind file management — Manual Test Plan

**Specs:**
- `docs/current_work/specs/d23_pm_file_management_spec.md` (Save As, New File, Rename, Move)
- `docs/current_work/specs/d23.1_pm_delete_and_folders_spec.md` (Delete file, New Folder, Delete folder)

**Created:** 2026-05-08
**Walks:** all 7 operations + the self-cleaning fixture pattern + D17/D19 regression spot-check.

> **Fixture pattern note:** every scenario in this plan uses the **self-cleaning fixture** recipe — a scratch directory created at the start, all test artifacts created inside it, the directory deleted at the end (cascade). PM tenant has zero residue after a clean run. This is the canonical pattern for all future PM-related smoke tests.

---

## Setup

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Pre-conditions:
- A PortableMind token is set (Debug menu → Set PortableMind Token… or i04 file at `~/Library/Application Support/ai.portablemind.md-editor/token.txt`).
- The PortableMind connector is loaded (visible in the sidebar).

---

## §1. Cross-cutting harness recipe

```bash
# Atomic file write — never use `>` direct (200ms poller race; see D14 lesson).
write_cmd() { echo "$1" > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json; }

# Wait until the result file is rewritten (poller takes ~200ms).
wait_result() { sleep 1; cat "$1"; }
```

Result-file conventions: each action writes `{ok: true, ...}` on success or `{ok: false, error: ...}` on failure to its `path` parameter.

---

## §2. The self-cleaning fixture pattern (canonical)

**This is the recommended path for every PM smoke test from D23.1 onward.** Before writing any new ad-hoc test artifact in the PM tenant, wrap it in a scratch directory that gets cascade-deleted at the end.

```bash
# 1. Create scratch dir at root.
TS=$(date +%s) ; SCRATCH="d23-smoke-scratch-$TS"
write_cmd "{\"action\":\"pm_create_directory\",\"parentNodeID\":\"portablemind:root\",\"name\":\"$SCRATCH\",\"path\":\"/tmp/r.json\"}"
sleep 1
SCRATCH_ID=$(jq -r .newNodeID /tmp/r.json)   # e.g. "portablemind:dir:162"

# 2. Run all the test ops inside $SCRATCH_ID.
#    pm_new_file / pm_save_as / pm_rename / pm_move / pm_delete_file all
#    parented to or scoped within $SCRATCH_ID.

# 3. Cascade-delete the scratch dir + everything inside.
write_cmd "{\"action\":\"pm_delete_directory\",\"nodeID\":\"$SCRATCH_ID\",\"path\":\"/tmp/r.json\"}"
sleep 1
jq .ok /tmp/r.json   # → true; PM tenant has no residue.
```

Smoke evidence captured 2026-05-08 in D23.1 phases-2+3 commit message — the recipe is verified against real Harmoniq dev.

---

## §3. Operations × scenarios

Each scenario assumes the §2 scratch fixture is set up; references `$SCRATCH_ID` for the parent directory.

### 3.1 New File (D23 phase 3)

| Step | Action | Expected | Verification |
|---|---|---|---|
| 3.1.1 | File → New PortableMind File… (⌘⌥N) — picker opens with intent=newFile, default name "Untitled.md", PM connector tree. Pick `$SCRATCH`. Click Create. | New empty file appears at `$SCRATCH/Untitled.md`. New tab opens, focused, source empty, `dirty=false`, `isReadOnly=false`. | `focused_doc_info` reports new origin/displayPath; `sourceLength=0`. |
| 3.1.2 | Harness equivalent: `pm_new_file parentNodeID=$SCRATCH_ID name=foo.md` | Same outcome; result file emits `{ok, newNodeID, newNodePath, newNodeName, newTabFocusedIndex}`. | `cat result.json`. |

### 3.2 Save As (D23 phase 2)

| Step | Action | Expected |
|---|---|---|
| 3.2.1 | Open an existing PM file (or use the doc opened in 3.1). Make a small edit so the buffer has content. ⌘⇧S → SaveAsSheet. Pick `$SCRATCH` as target directory; type a new filename. Click Save. | Server creates the new file; current tab **switches** to point at the new node (`origin.fileID` updates; `displayName` reflects new file). Buffer + caret + scroll preserved. `dirty=false` after save. |
| 3.2.2 | Harness: `pm_save_as parentNodeID=$SCRATCH_ID name=fork.md` (with a focused PM doc) | Same; result file emits `{ok, newNodeID, newNodePath, newNodeName}`. |

### 3.3 Rename (D23 phase 4)

| Step | Action | Expected |
|---|---|---|
| 3.3.1 | Sidebar right-click on a PM file row → Rename… → RenameSheet opens, prefilled with current name. Type a new name. Click Rename. | Server PATCH succeeds. Sidebar tree row name updates without manual reload (tree splice). If the file is open, tab title refreshes; buffer/caret/scroll preserved. |
| 3.3.2 | Harness: `pm_rename nodeID=<file-id> newName=renamed.md` | Same; result emits `{ok, nodeID, newName, newPath}`. |
| 3.3.3 | Error case: rename to a name that already exists in the same dir. | Server returns 422; modal stays open with inline error showing the controller's collision message. |

### 3.4 Move (D23 phase 5)

| Step | Action | Expected |
|---|---|---|
| 3.4.1 | Sidebar right-click on a PM file row → Move to… → MoveSheet (tree picker). Pick a different directory. Click Move. | Server PATCH succeeds. Sidebar tree updates (file disappears from old parent, appears under new). If the file is open, tab `origin.displayPath` updates; buffer/caret/scroll preserved. |
| 3.4.2 | Harness: `pm_move nodeID=<file-id> newParentNodeID=<dir-id>` | Same; result emits `{ok, nodeID, newPath, name}`. |
| 3.4.3 | No-op move (target == current parent): Save button is disabled in the modal. | Modal accepts other directories; current parent is the disabled selection. |

### 3.5 Delete file (D23.1 phase 2)

| Step | Action | Expected |
|---|---|---|
| 3.5.1 | Sidebar right-click on a PM file row → Delete… | NSAlert: "Delete '`<name>`'? This can't be undone." Cancel + Delete buttons. |
| 3.5.2 | Click Delete in the alert. | Server DELETE succeeds; row removed from sidebar tree (splice). If the file was open in any tab, that tab is closed (cascade-close per Q4). |
| 3.5.3 | Harness: `pm_delete_file nodeID=<file-id>` | Same; result emits `{ok, nodeID}`. |

### 3.6 New Folder (D23.1 phase 2)

| Step | Action | Expected |
|---|---|---|
| 3.6.1 | Sidebar right-click on a PM directory row (or root) → New Folder… → CreateDirectorySheet. Type a folder name. Click Create. | Server POST succeeds; new folder appears in the tree under the parent (splice). |
| 3.6.2 | Harness: `pm_create_directory parentNodeID=<dir-id> name=foo` | Same; result emits `{ok, newNodeID, newNodePath, newNodeName}`. |
| 3.6.3 | Validation: empty name or name containing `/` disables the Save button with no error. |

### 3.7 Delete folder (D23.1 phase 2)

| Step | Action | Expected |
|---|---|---|
| 3.7.1 | Sidebar right-click on a non-root PM directory row → Delete… | NSAlert: "Delete '`<name>`'? This will also delete N item(s) inside. This can't be undone." (Child count surfaced from already-loaded data when known; otherwise omitted.) |
| 3.7.2 | Click Delete. | Server cascade-deletes (always passes `?cascade=true`); directory + all descendants removed from tree (splice + descendant cache eviction). Any open tab whose path is the deleted dir or starts with `<dir>/` is closed (Q4 trailing-/ boundary). |
| 3.7.3 | Harness: `pm_delete_directory nodeID=<dir-id>` | Same; result emits `{ok, nodeID}`. |
| 3.7.4 | Connector root row does NOT show Delete… in the context menu. | (The level == 0 guard in ConnectorRowView.) |

---

## §4. Self-cleaning end-to-end smoke

This is the canonical full-cycle test. Verified 2026-05-08 against real Harmoniq dev (D23.1 phase 2+3 commit smoke).

```bash
# Setup
TS=$(date +%s) ; SCRATCH="d23-smoke-scratch-$TS"
write_cmd "{\"action\":\"pm_create_directory\",\"parentNodeID\":\"portablemind:root\",\"name\":\"$SCRATCH\",\"path\":\"/tmp/r.json\"}"
sleep 1
SCRATCH_ID=$(jq -r .newNodeID /tmp/r.json)
echo "scratch: $SCRATCH_ID at /$SCRATCH"

# Operations exercised inside the scratch dir
write_cmd "{\"action\":\"pm_new_file\",\"parentNodeID\":\"$SCRATCH_ID\",\"name\":\"a.md\",\"path\":\"/tmp/r.json\"}"
sleep 1
A_ID=$(jq -r .newNodeID /tmp/r.json)

write_cmd "{\"action\":\"pm_rename\",\"nodeID\":\"$A_ID\",\"newName\":\"renamed.md\",\"path\":\"/tmp/r.json\"}"
sleep 1

# (optional: pm_save_as with a focused doc, pm_move to a sibling sub-folder, etc.)

# Cleanup — single cascade delete clears everything.
write_cmd "{\"action\":\"pm_delete_directory\",\"nodeID\":\"$SCRATCH_ID\",\"path\":\"/tmp/r.json\"}"
sleep 1
jq .ok /tmp/r.json   # → true. PM tenant has no residue.
```

---

## §5. Failure pointers

Drop here if a regression surfaces.

| Symptom | Look at |
|---|---|
| `Save As not yet supported` alert returns | `MdEditorApp.saveAsFocused` PM branch — should call `workspace.requestSaveAs(for:)`, not show NSAlert. |
| Tab doesn't switch after Save As | `EditorDocument.updateAfterSaveAs` — verifies origin/connectorNode/url/lastSavedSource are all updated. |
| Sidebar tree shows stale name after rename / doesn't show new file after Save As | `PMFileOperations.{rename,saveAs,newFile}` — ensure they call `vm.upsertNode(...)`. `ConnectorTreeViewModel.upsertNode` is PortableMind-only in v1. |
| Open tab not closed after delete | `PMFileOperations.delete` → `closeTabsForFile` (file) or `closeTabsInDirectory` (dir). Q4 trailing-/ boundary check. |
| Cascade delete fails with "Cannot delete non-empty directory without cascade option" | `PortableMindAPIClient.deleteDirectory` — must always pass `?cascade=true`. Server requires explicit cascade flag. |
| Create directory returns 422 | `PortableMindAPIClient.createDirectory` — must send `path` (full target path), not just `parent_path` + `name`. The model's `validates :path, presence: true` fires before `before_validation :set_parent_path`. |
| MoveSheet allows selecting current parent (no-op) | `MoveSheet.canMove` parent-path comparison; uses last-/-component path manipulation. |
| Cross-tenant move attempted | `PortableMindConnector.moveFile` — Q6 connector-level guard throws `.unsupported`. |

---

## §6. D17 + D19 regression check (subset)

Phase 4/5/D23.1 changes were strictly additive at the cell-rendering / save-back level. Spot-check:

| D17 / D19 ref | Scenario | Expected |
|---|---|---|
| D17 B1 | Click in a cell mid-table; type | Caret + characters insert correctly. (No D23 code changed table rendering.) |
| D17 C1 | Tab between cells | Standard NSTextView behavior preserved. |
| D19 conflict | Edit a PM file's content while a third party renames it via the web UI; ⌘S in editor | Renamed-elsewhere doesn't trigger conflict (rename doesn't change `updated_at`); save proceeds normally. (Server-side LlmFile model behavior.) |

Full D17 manual plan is in `docs/chronicle_by_concept/05_tables/testing/d17_textkit1_migration_manual_test_plan.md` if a deeper sweep is needed.

---

## §7. Graduation to XCUITest

The harness paths exercised here can promote to XCUITest in the future. Notes for that promotion:

1. **Tree-splice correctness** is the cross-cutting invariant — every D23/D23.1 operation should leave the cached tree consistent with the server. An XCUITest could `pm_create_directory` then `expand_sidebar_path` and assert the new node is present without re-fetching.
2. **Cascade-close** is testable harness-side via dump_state before/after delete operations.
3. **No-op-detection** in MoveSheet (current parent disabled) needs a UI driver — XCUITest accessibility identifiers are in place.

XCUITest expansion scoped to follow-up infrastructure work; manual + harness coverage is sufficient for v0.7 ship.
