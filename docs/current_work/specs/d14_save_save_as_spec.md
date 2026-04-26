# D14: Save / Save As — Specification

**Status:** Backfilled (implementation shipped 2026-04-26 in commit `eca7bdb`)
**Created:** 2026-04-26
**Author:** Rick (CD) + Claude (CC)
**Traces to:** `docs/vision.md` Principle 1 (Word/Docs-familiar authoring — saving edits to disk is a baseline expectation users have from any text editor); CD-discovered gap during D13 manual testing 2026-04-26 ("contents are not being saved back to disc").

---

## 1. Problem statement

Pre-D14, `EditorDocument` had a `source` buffer and an optional `url`, but no way to write the buffer back to disk. Edits made via the editor (typing, D13 cell-edit overlay, D13 modal popout) lived in memory only. Closing the app or the tab silently lost them.

This contradicts vision Principle 1 (the app behaves like Word/Docs). It also undermines D13's value — the user can edit a cell, but there's no way to keep the edit.

---

## 2. Goals

- **Save** writes the focused tab's buffer to its existing file URL.
- **Save As** opens NSSavePanel, lets the user pick a new URL, and writes there.
- **Untitled docs** behave like Save As on first save.
- **External-edit watcher** does not echo our own write back into the buffer.
- **Errors** surface to the user via `NSAlert`.

Out of scope:
- Dirty-state UX (modified-indicator dot in tab title). Future D14.x.
- Auto-save. Future polish.
- Per-document encoding selection (UTF-8 only in V1).
- Confirmation prompt on tab close with unsaved changes. Future when tab-close UX exists.
- Crash-recovery / scratch backups. Future polish.

---

## 3. Design

### 3.1 EditorDocument additions

Two methods + one error type:

```swift
enum SaveError: LocalizedError {
    case noURL
    case writeFailed(URL, Error)
}

func save() throws        // → SaveError.noURL if doc.url == nil
func saveAs(to: URL) throws
```

### 3.2 Watcher feedback-loop guard

`ExternalEditWatcher` uses NSFilePresenter + NSFileCoordinator. When we write to disk via `String.write(to:atomically:encoding:)`, the watcher's `presentedItemDidChange` will fire and read the file we just wrote, calling `onChange(text)` with content equal to our buffer.

The downstream `wireDocumentSubscription` already has an equality guard (`if textView.string != newText`), so the inner branch wouldn't fire in the simple case. **However**: there's a small race window. After save, the user might immediately type a character. The watcher's async callback then arrives with the OLD (saved) content. textView.string != newText (because of the just-typed char), so the guard branch FIRES, overwriting the user's new edit with the saved content.

**Solution:** pause the watcher around the write. `watcher.stop()` before, `watcher.watch(url)` after. The presentedItemDidChange call doesn't fire while the watcher isn't registered, so no echo.

### 3.3 Atomic write

`String.write(to:atomically:true,encoding:.utf8)` writes to a temp file in the same directory, then renames. Power loss / crash mid-write leaves either the old or new file intact, never corrupt. Standard NSString contract.

### 3.4 saveAs URL update on success

`saveAs(to:)` writes FIRST, then sets `self.url = newURL`. If the write throws, the document's url is unchanged — caller can retry or fall through to a different path. If we set url before write and write fails, the doc would point at a non-existent file.

### 3.5 Menu integration

`MdEditorApp.body.commands` adds `CommandGroup(replacing: .saveItem) { ... }`. Replacing the standard saveItem placement gives us two buttons:
- "Save" with ⌘S
- "Save As…" with ⌘⇧S

Actions run on the SwiftUI main actor. They fetch `workspace.tabs.focused` and dispatch to `doc.save()` or `doc.saveAs(to:)`.

For untitled docs (`doc.url == nil`), `saveFocused()` falls through to `saveAsFocused()`. The save-panel default name is "Untitled.md".

### 3.6 NSSavePanel configuration

- `allowedContentTypes`: `[.md, .plainText]` (md preferred, plainText as fallback).
- `nameFieldStringValue`: current url's lastPathComponent or "Untitled.md".
- `directoryURL`: current url's parent directory if available.

### 3.7 Error surface

`SaveError` conforms to `LocalizedError` with friendly messages. `presentSaveError` wraps in `NSAlert(error:)` with "Save Failed" message text and runs modally.

---

## 4. Success criteria

- [x] Save (⌘S) writes buffer to current url; file MD5 changes; subsequent reload from disk shows new content.
- [x] Save As (⌘⇧S) opens NSSavePanel, writes to chosen URL, updates doc.url.
- [x] Untitled doc Save → behaves like Save As.
- [x] External-edit watcher does NOT echo our own saved write back into the buffer (verified: post-save, no spurious source change).
- [x] External edits to disk DO still reflect into the buffer (regression check — watcher resumes after save).
- [x] Save failure (e.g., write to read-only path) surfaces NSAlert with localized message.
- [x] D13 cell-edit overlay edits persist after Save.

---

## 5. Implementation steps

(Implementation shipped in commit `eca7bdb` 2026-04-26. Steps below for reference.)

1. `EditorDocument.save() / saveAs(to:)` in `Sources/Workspace/EditorDocument.swift`.
2. `SaveError` enum.
3. `MdEditorApp.body.commands` → `CommandGroup(replacing: .saveItem)`.
4. `saveFocused()` / `saveAsFocused()` private methods on `MdEditorApp`.
5. `AccessibilityIdentifiers.fileMenuSave / fileMenuSaveAs`.
6. Harness extensions: `save_focused_doc`, `save_as_focused_doc`, `focused_doc_info`.

### Harness sync contract change (related)

D14 verification surfaced a race in the test driver↔harness IPC: the driver was overwriting commands faster than the 200ms poll could process. Fix: moved `removeItem(commandPath:)` to AFTER `dispatch()` in `HarnessCommandPoller.tick()`, so file-disappearance is a reliable synchronization signal. Per CD direction 2026-04-26: "sleeps tend to be band-aids — fix the underlying race."

---

## 6. Open questions (all resolved)

- **Q1:** Untitled-doc save semantics? **Resolved:** falls through to Save As (NSSavePanel).
- **Q2:** Watcher feedback-loop strategy? **Resolved:** pause watcher around save (not just rely on equality guard — race window is real).
- **Q3:** Atomic write? **Resolved:** yes, `atomically: true`.
- **Q4:** SaveAs URL update on failure? **Resolved:** url stays at old value if write throws; only updates on success.
- **Q5:** Encoding? **Resolved:** UTF-8 only for V1.
- **Q6:** Dirty state? **Deferred** to D14.x (modified-indicator UI).
- **Q7:** Tab-close confirmation prompt? **Deferred** until tab-close UX exists.
