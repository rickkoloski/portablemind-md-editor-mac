# D14: Save / Save As — Manual Test Plan

**Spec:** `docs/current_work/specs/d14_save_save_as_spec.md`
**Plan:** `docs/current_work/planning/d14_save_save_as_plan.md`
**Created:** 2026-04-26

---

## Setup

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor -configuration Debug \
           -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Create a test file:
```bash
cat > /tmp/d14-test.md <<'EOF'
# D14 Save Test
Original line.
EOF
./scripts/md-editor /tmp/d14-test.md
```

---

## A. Save (⌘S) round-trip

| Test | Action | Expected |
|---|---|---|
| A1 | Type any text in the editor | Buffer updates; nothing on disk yet (`md5 /tmp/d14-test.md` unchanged) |
| A2 | File → Save (or ⌘S) | Save completes silently; `md5 /tmp/d14-test.md` is now different; `cat` shows new content |
| A3 | Edit again, ⌘S again | New content saved; D14 idempotent |

---

## B. Save As (⌘⇧S)

| Test | Action | Expected |
|---|---|---|
| B1 | File → Save As… (or ⌘⇧S) | NSSavePanel opens with current filename + parent dir defaulted |
| B2 | Pick a new filename + path, click Save | New file created at chosen path with current buffer content; tab title updates to new filename |
| B3 | After Save As, ⌘S | Saves to the NEW path (doc.url was updated by Save As) |
| B4 | Cancel the save panel | No file change; no error |

---

## C. Untitled docs

| Test | Action | Expected |
|---|---|---|
| C1 | Create an untitled doc (TBD when "New" menu lands; for now, open a non-existent path) | Tab title shows "Untitled" |
| C2 | Type content, ⌘S | Save As panel opens (Save falls through for untitled docs) |
| C3 | Save → file is created at chosen path with content | New file on disk |

---

## D. External edit watcher (regression)

| Test | Action | Expected |
|---|---|---|
| D1 | After saving, externally `echo "external content" > /tmp/d14-test.md` | Buffer reflects new content (NSFilePresenter still working post-save) |
| D2 | Save → external edit → save again | No corruption / no infinite loop |
| D3 | Type → save → IMMEDIATELY type again | Second typed text not overwritten (watcher pause-around-save prevents echo) |

---

## E. D13 overlay persistence

| Test | Action | Expected |
|---|---|---|
| E1 | Open a markdown file with a table | Tables render |
| E2 | Single-click a cell, type new content, Enter (commit) | Cell shows new content; source updated in buffer |
| E3 | ⌘S | Edit persisted to disk; reopening file shows the change |
| E4 | Right-click → Edit Cell in Popout… → edit → Save | Modal commit + ⌘S → both reach disk |

---

## F. Error handling

| Test | Action | Expected |
|---|---|---|
| F1 | Open a file in a read-only location (e.g., system path), type, ⌘S | NSAlert "Save Failed" with file-permission error message |
| F2 | Save As to an invalid path | NSAlert; doc.url unchanged from prior state |

---

## G. Multi-tab independence

| Test | Action | Expected |
|---|---|---|
| G1 | Open two files in two tabs, edit both, ⌘S in tab 1 | Only tab 1's file changes on disk; tab 2's edits stay in memory |
| G2 | Switch tabs, ⌘S | Saves the focused tab's doc only |

---

## H. Regression (D8/D9/D10/D11/D8.1/D12/D13/D15)

- D8 tables still render after save.
- D9 scroll-to-line still works (`./scripts/md-editor file.md:42`).
- D10 line numbers still toggleable.
- D11 CLI view-state flags still work.
- D8.1 / D12 reveal still triggers on double-click.
- D13 cell overlay still works post-save.
- D15 scroll-jump-on-typing fix still holds (no scroll movement when typing in a saved doc).

---

## Failure pointers

- A2 fails: `EditorDocument.save()` not invoked. Check menu wiring in `MdEditorApp.body.commands` `CommandGroup(replacing: .saveItem)`.
- B2 fails to update tab title: `doc.url` not being set after successful saveAs. Check `EditorDocument.saveAs(to:)` — must set `self.url = newURL` AFTER the write succeeds.
- D3 (post-save typing overwritten by watcher echo): watcher stop/restart guard not in place. Check `EditorDocument.writeAndRewatch` — `watcher.stop()` before write, `watcher.watch(url:)` after.
- F1 doesn't show alert: `presentSaveError` not called. Check the `do { ... } catch { presentSaveError(error) }` chain in `saveFocused()`.
