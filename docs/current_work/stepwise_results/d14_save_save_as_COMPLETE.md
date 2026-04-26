# D14: Save / Save As — COMPLETE

**Shipped:** 2026-04-26
**Spec:** `docs/current_work/specs/d14_save_save_as_spec.md`
**Plan:** `docs/current_work/planning/d14_save_save_as_plan.md`
**Prompt:** `docs/current_work/prompts/d14_save_save_as_prompt.md`
**Test plan:** `docs/current_work/testing/d14_save_save_as_manual_test_plan.md`

---

## What shipped

Two methods on `EditorDocument` — `save()` and `saveAs(to:)` — backed by atomic UTF-8 writes with watcher stop/restart to prevent feedback loops. File menu items wired (⌘S / ⌘⇧S). Untitled docs fall through to Save As via NSSavePanel.

CD-discovered gap during D13 manual testing: edits had been living in memory only, never reaching disk. Now they persist.

---

## Files modified

| File | Change |
|---|---|
| `Sources/Workspace/EditorDocument.swift` | Added `SaveError` enum + `save()` / `saveAs(to:)` methods + private `writeAndRewatch(url:)` helper that pauses the ExternalEditWatcher around the write |
| `Sources/App/MdEditorApp.swift` | `CommandGroup(replacing: .saveItem)` with Save / Save As… buttons + `saveFocused()` / `saveAsFocused()` / `presentSaveError()` private methods. NSSavePanel with .md/.plainText UTType filter |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | `fileMenuSave` + `fileMenuSaveAs` constants |
| `Sources/Debug/HarnessCommandPoller.swift` | Three new actions: `save_focused_doc`, `save_as_focused_doc`, `focused_doc_info`. Plus the **harness sync contract fix** (separate item below) |

---

## Harness sync contract fix (related)

Surfaced during D14 verification. The test driver was using `sleep` to space commands apart, but sleeps were just biasing the timing — they didn't fix the actual race.

**Race:** driver writes command A to `/tmp/mdeditor-command.json`, then writes command B before the 200ms-tick poller has read A. Command A is silently lost.

**Fix:** moved `removeItem(commandPath:)` to AFTER `dispatch()` in `HarnessCommandPoller.tick()`. File-disappearance is now a reliable synchronization signal: file gone = command processed AND result file written. Driver pattern: write command → poll for file-disappearance → read result.

All dispatch handlers are synchronous (no async hops inside) so this is safe.

CD direction (2026-04-26): "sleeps tend to be band-aids — fix the underlying race." This change applies that principle.

The harness↔app discussion clarified scope: the race is **entirely** in the harness's debug-only IPC. Real users encounter no analog (AppKit's run loop serializes input events on the main thread). So the fix is purely a test-infrastructure quality improvement.

---

## Verification

Three harness-driven tests, all using the synchronous wait-for-file-disappearance driver pattern (no sleep bandaids):

| Test | Verifies |
|---|---|
| 1: Save round-trip | Source 25 → insert 16 chars → 41; `save_focused_doc` → file MD5 changes; cat shows "INSERTED-CONTENT" appended |
| 2: External-edit watcher regression | External `echo > file` → buffer reflects new content via NSFilePresenter (watcher resumes correctly after save's stop/restart) |
| 3: Save As | `save_as_focused_doc(newURL)` → new file written; doc.url updated to new path |

UI-only tests (manual, in test plan): NSSavePanel opens for Save As + untitled-Save; NSAlert raises on save failure; ⌘S keyboard shortcut wired correctly.

---

## Production-relevant insights

1. **Atomic write is the default for any file editor.** `String.write(to:atomically:true,encoding:.utf8)` writes to a temp file then renames. Power loss / crash mid-write leaves either the old or new file intact — never partial. Free correctness from Foundation; we just had to use it.

2. **NSFilePresenter feedback loops are real.** Without `watcher.stop()` around the save, our own write triggers `presentedItemDidChange` → coordinator reads → `onChange(text)` → `document.source = text`. If the user typed between save and watcher callback, their new edit gets overwritten. Stop/restart eliminates the window.

3. **Update url AFTER successful write, not before.** If the write throws, the document keeps pointing at its old (working) URL instead of a non-existent new one.

4. **NSSavePanel + UTType filter just works.** No bookmarking, no sandbox dance — the panel grants ephemeral write permission for the chosen URL on each return. (Sandbox is `ENABLE_HARDENED_RUNTIME: NO` in project.yml; this would need revisiting if we sandbox.)

5. **Untitled-Save fall-through is a one-liner.** `if doc.url == nil { saveAsFocused(); return }`. Matches every other text editor.

---

## Roadmap impact

D14 row added (this commit) → ✅ Complete.
D15 row also added (scroll-jump fix, separate one-line bug fix).
Both shipped same day; tag `v0.3` covers them + the harness sync contract fix.

---

## Deferrals

| Gap | Disposition |
|---|---|
| Dirty-state indicator (modified dot in tab title) | V1.x — needs a `@Published var isDirty` on EditorDocument + tab UI |
| Auto-save on focus loss / debounce | Future polish |
| Confirm-on-close-with-unsaved-changes | Wait until tab-close UX exists (no close button on tabs yet) |
| Encoding selection (UTF-16 LE BOM, etc.) | Out of scope; UTF-8 only |
| Crash recovery (.swp files / scratch backups) | Future polish |
