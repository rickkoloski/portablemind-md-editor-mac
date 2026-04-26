# D14: Save / Save As — CC Prompt

**Status:** Backfilled — implementation shipped 2026-04-26 in `eca7bdb`. This prompt documents the work for chronicle and future-rerun reference.

**Spec:** `docs/current_work/specs/d14_save_save_as_spec.md`
**Plan:** `docs/current_work/planning/d14_save_save_as_plan.md`

---

## Context

CD discovered during D13 manual testing that the app doesn't save edits back to disk. `EditorDocument` had `source` + optional `url` but no save method. Edits live in memory only — D13's overlay edits, D12's cell-boundary nav results, every typed character — gone on app close.

D14 ships:
- `EditorDocument.save()` and `saveAs(to:)` with `SaveError` typed errors.
- File menu Save (⌘S) and Save As… (⌘⇧S).
- Untitled-doc behavior: Save → falls through to Save As.
- Watcher feedback-loop guard via stop/restart around write.
- Atomic writes (`atomically: true`).

Plus a related fix to the test-harness sync contract: surfaced during D14 verification when `sleeps` were being used as bandaids over a race in the driver↔harness file-IPC. Fix: harness removes the command file AFTER dispatch (not before), so file-disappearance signals "command processed AND result file written." Driver waits for disappearance before next write. CD direction 2026-04-26: "sleeps tend to be band-aids — fix the underlying race."

---

## Constraints

- **No `.layoutManager` references** (engineering-standards §2.2).
- **Preserve external-edit watcher behavior** — D6's watcher reflects external edits into the buffer; D14 must not break this. Verify by external-edit regression test.
- **Atomic writes only** — never partial-write a markdown file.
- **No silent failures** — all save errors surface via NSAlert.
- **No autosave / no dirty state in V1** — both deferred to V1.x.
- **NSSavePanel for Save As + Untitled** — never hardcode a path.

---

## Success criteria

(Mirror spec §4.)

- [x] ⌘S writes focused doc's buffer to disk.
- [x] ⌘⇧S opens save panel, writes to chosen URL, updates doc.url.
- [x] Untitled Save → falls through to Save As.
- [x] No watcher echo on save (watcher stop/restart).
- [x] External edits still reflect post-save (regression).
- [x] D13 overlay-edited content persists across save → reopen.
- [x] Failure surface: NSAlert with localized message.

---

## On Completion

(Already done in `eca7bdb`. Listed for chronicle pattern.)

1. `docs/current_work/stepwise_results/d14_save_save_as_COMPLETE.md`.
2. Roadmap: D14 row → ✅ Complete; change-log entry.
3. Manual test plan at `docs/current_work/testing/d14_save_save_as_manual_test_plan.md`.
4. Tag v0.3 (covers D14, D15, harness contract fix).
