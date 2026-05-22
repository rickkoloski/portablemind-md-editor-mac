# Table Typing Bug — Diagnostic Plan

**Bug:** Typing into an empty table cell breaks the table rendering — the typed character appears outside the cell, the row structure visibly fragments, the source markdown gets corrupted (line ends up as just the typed character, no pipes).

**Repro:** Reliable per Rick 2026-05-22.

**Symptom (from Rick's screenshot, 2026-05-22 5:12 AM):**
- Source line 169 (an empty table row `| | | |`) became just `d` after the user typed `d` into the first empty cell of that row.
- Visual: header row + first data row render normally, then a stray `d` below, then a single orphan cell.
- The pipes were stripped from the typed-into row in the source.

**Hypothesis tree:**
1. **Cell-edit code stripping pipes** — `LiveRenderTextView`'s in-place cell edit (D17) replaces the cell with the typed text but uses the wrong replacement range (whole row instead of cell-interior).
2. **NSTextTable boundary detection off** — typing dispatches to a normal text-edit path because the caret isn't recognized as being inside a table cell.
3. **Renderer mis-attributing on re-render** — source is fine; rendering after typing fails to re-apply the table block attribute to the typed-into row.

(2) and (3) leave the source unchanged; (1) corrupts it. We can disambiguate by reading the on-disk source after typing (with explicit save) and comparing to the in-buffer state via harness `dump_state`.

---

## Fixture

`docs/current_work/testing/table_typing_bug_fixture.md`

Pristine table:

```
| TC | Result | Notes |
|----|--------|-------|
| TC-01 | pass | first row, populated |
| TC-02 |  |  |
| TC-03 |  |  |
| TC-04 | pass | last row, populated |
```

Two empty rows (TC-02, TC-03), each with two empty cells. Bordered above and below by populated rows so we can see if corruption bleeds.

---

## Repro Steps

### A. Setup

1. Make sure the fixture is at its pristine state:

   ```bash
   cd ~/src/apps/md-editor-mac && git diff docs/current_work/testing/table_typing_bug_fixture.md
   ```

   If the diff is empty, the fixture is pristine. If not, reset:

   ```bash
   cd ~/src/apps/md-editor-mac && git checkout docs/current_work/testing/table_typing_bug_fixture.md
   ```

2. Open the fixture in md-editor:

   ```bash
   ~/src/apps/md-editor-mac/scripts/md-editor ~/src/apps/md-editor-mac/docs/current_work/testing/table_typing_bug_fixture.md
   ```

### B. Reproduce the bug

1. Click into the empty Result cell of the TC-02 row.
2. Type a single character: `x`.
3. Observe the visual: does the table break? (Probably yes per the Nimble repro.)
4. **Without quitting the app**, save with ⌘S.

### C. Capture state

After step B4 (save), run from terminal:

```bash
cat ~/src/apps/md-editor-mac/docs/current_work/testing/table_typing_bug_fixture.md
```

**Paste the cat output back to CC.**

This shows the on-disk state AFTER save — telling us whether the source corruption is in the typing path or just the renderer.

### D. (Optional) In-buffer state via harness

If the on-disk state matches the pristine source (table intact in source, just rendered wrong), the bug is in the renderer. Skip this section.

If the on-disk state shows corruption, we can also peek at the in-buffer state to confirm corruption happens at typing time (not at save time):

```bash
echo '{"action":"dump_state"}' > /tmp/mdeditor-command.json && sleep 0.5 && cat /tmp/mdeditor-command-result.json
```

(Exact file paths depend on the harness contract — confirm with CC if unsure.)

---

## Inspection check (CC runs this between steps)

```bash
cat ~/src/apps/md-editor-mac/docs/current_work/testing/table_typing_bug_fixture.md
```

CC will read the fixture between Rick's actions to see source state at each point.

---

## Decision matrix (after step C)

| On-disk after save | Diagnosis |
|---|---|
| Pristine (table intact, no `x` visible) | Save didn't flush, or buffer corruption is in renderer only — proceed to D for in-buffer inspection. |
| `x` correctly inserted into the Result cell of TC-02 (table still intact: `| TC-02 | x |  |`) | Bug is in render path — source mutation is correct, NSTextTable re-attribution is broken. |
| TC-02 row mangled: pipes stripped, line is just `x` or `\| x` | Bug is in cell-edit mutation path — replacement range is too greedy. |
| Something else | New failure mode; CC investigates. |

---

## Followup

When the diagnosis is in, file as `i07` in `docs/issues_backlog.md` if not blocking, or scope a D# deliverable if it warrants a fix pass. The D17 NSTextTable migration retired ~3,200 lines of custom-fragment code; we expect some sharp edges to surface during real-world cell editing.
