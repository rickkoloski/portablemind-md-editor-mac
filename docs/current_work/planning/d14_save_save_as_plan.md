# D14: Save / Save As — Plan

**Spec:** `d14_save_save_as_spec.md`
**Status:** Backfilled. Implementation shipped 2026-04-26 in commit `eca7bdb`.

---

## Overview

Three small additions: methods on `EditorDocument`, menu items in `MdEditorApp`, and harness actions for testing. Plus a related fix to the test-harness sync contract surfaced during D14 verification.

This plan is a single phase — D14 is small enough that per-phase test gates aren't needed.

---

## Phase 1 — Implementation

### 1a. EditorDocument

`Sources/Workspace/EditorDocument.swift`:

```swift
enum SaveError: LocalizedError {
    case noURL
    case writeFailed(URL, Error)
    var errorDescription: String? { ... }
}

func save() throws { ... }
func saveAs(to newURL: URL) throws { ... }

private func writeAndRewatch(url: URL) throws {
    watcher.stop()
    defer { watcher.watch(url: url) }
    try source.write(to: url, atomically: true, encoding: .utf8)
}
```

Watcher stop/start prevents the post-save `presentedItemDidChange` echo from overwriting the buffer if the user types between save and watcher callback.

### 1b. Menu integration

`Sources/App/MdEditorApp.swift`:

```swift
.commands {
    // ... existing CommandGroups ...
    CommandGroup(replacing: .saveItem) {
        Button("Save") { saveFocused() }
            .keyboardShortcut("s", modifiers: .command)
        Button("Save As…") { saveAsFocused() }
            .keyboardShortcut("s", modifiers: [.command, .shift])
    }
}

private func saveFocused() {
    guard let doc = workspace.tabs.focused else { return }
    if doc.url == nil { saveAsFocused(); return }
    do { try doc.save() }
    catch { presentSaveError(error) }
}

private func saveAsFocused() {
    guard let doc = workspace.tabs.focused else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.md, .plainText]
    panel.nameFieldStringValue = doc.url?.lastPathComponent ?? "Untitled.md"
    panel.directoryURL = doc.url?.deletingLastPathComponent()
    guard panel.runModal() == .OK, let chosen = panel.url else { return }
    do { try doc.saveAs(to: chosen) }
    catch { presentSaveError(error) }
}

private func presentSaveError(_ error: Error) {
    let alert = NSAlert(error: error)
    alert.messageText = "Save Failed"
    alert.runModal()
}
```

### 1c. Accessibility identifiers

`Sources/Accessibility/AccessibilityIdentifiers.swift`: add `fileMenuSave` + `fileMenuSaveAs`.

---

## Phase 2 — Harness extensions

`Sources/Debug/HarnessCommandPoller.swift`:

- `save_focused_doc` — invokes `doc.save()` on focused doc; writes `{saved, url, sourceLength}` or `{error}`.
- `save_as_focused_doc(newURL)` — invokes `doc.saveAs(to:)`; same result shape.
- `focused_doc_info` — writes `{url, displayName, sourceLength, externallyDeleted}`.

These let tests verify the save path without driving NSMenu / NSSavePanel.

---

## Phase 3 — Harness sync contract fix

Discovered during D14 verification: rapid consecutive writes to `/tmp/mdeditor-command.json` could overwrite a command before the 200ms-tick poller read it.

Fix: move `removeItem(commandPath:)` from BEFORE dispatch to AFTER dispatch in `HarnessCommandPoller.tick()`. Driver pattern: write command, poll for file-disappearance, then read result. File-disappearance == command processed AND result file written.

All dispatch handlers are synchronous (no async hops) so this is safe.

Per CD direction 2026-04-26: "sleeps tend to be band-aids — fix the underlying race."

---

## Verification

Three end-to-end harness-driven tests on the running app, all using the synchronous driver pattern (no sleep bandaids):

1. **Save round-trip.** Source 25 → insert 16 chars → 41 → save → file MD5 changes → cat shows new content.
2. **External edit watcher regression.** External `echo > file` → buffer reflects new content via NSFilePresenter (verifies watcher resumes after our save's stop/restart).
3. **Save As.** `saveAs(to: newURL)` → new file written → doc.url updated.

---

## Out of scope

- Dirty-state indicator UI (D14.x).
- Confirm-on-close-with-unsaved-changes.
- Auto-save.
- Encoding selection.
- Crash recovery.
