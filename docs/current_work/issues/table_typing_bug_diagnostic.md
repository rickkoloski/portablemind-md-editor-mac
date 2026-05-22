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

---

## Diagnosis (2026-05-22)

### Test result

Pristine fixture has empty cells `| TC-02 |  |  |`. After typing `x` into TC-02's Result cell and saving:

```
| TC | Result | Notes |
| --- | --- | --- |
| TC-01 | pass | first row, populated |
| TC-02 |  |  |        ← unchanged — `x` did NOT land in the cell
x                       ← NEW standalone paragraph

| TC-03 |  |  |        ← split into its own table
| --- | --- | --- |


| TC-04 | pass | last row, populated |
| --- | --- | --- |
```

### Pipeline trace

Every keystroke triggers `EditorContainer.Coordinator.textDidChange` → `TK1Serializer.serialize(storage)` → `document.source = serialized`. So the on-disk state after save is the result of:
1. NSTextView accepts the typed character
2. Serializer re-emits markdown from the attributed-string storage

### Why typing doesn't land in the cell

Each empty cell paragraph is built (`TK1TableBuilder.makeCell`) as just `"\n"` — a single newline carrying the cell's paragraph style (including `NSTextTableBlock`). The cell paragraph has length 0 in terms of visible content.

When the user clicks into the empty cell, `cellContentEnd(containingContainerPoint:)` returns the position OF the `\n`. NSTextView places the caret there.

When the user types, AppKit's NSTextTable handling has a known wart for empty cells: rather than inserting INTO the empty cell paragraph (which would extend the paragraph to `"x\n"`), it breaks out and creates a sibling non-cell paragraph for the typed character. The character lands without the table block attribute. The serializer then correctly treats that paragraph as a non-cell paragraph, ending the in-progress table, emitting `x\n`, then starting a new table for the rest of the rows.

### Secondary bug (not the primary cause but worth fixing alongside)

`TK1Serializer.serialize` line 73 has:

```swift
guard paraRange.length > 0 else { return nil }
```

This means even when a cell paragraph IS correctly preserved (just an empty `\n`), the serializer treats it as a non-cell paragraph and emits a blank line, splitting the table. The current renderer happens to preserve empty cells across load+save WITHOUT user edits because... actually it shouldn't even do that with this guard in place. Worth verifying with a no-edit round trip.

### Fix options

**Option A — zero-width placeholder (recommended, ~20-30 LOC).**
- `TK1TableBuilder.makeCell`: when `text` is empty, use `body = "\u{200B}\n"` instead of `"\n"`. Apply the cell's paragraph style to the ZWS too.
- `TK1Serializer.serialize`: when extracting `paraText`, strip leading/trailing `\u{200B}` chars before emitting.
- `TK1Serializer.serialize` line 73: also fix the `paraRange.length > 0` guard so even-truly-empty paragraphs are inspected for cell info (defense in depth).
- Pros: surgical, no input-pipeline changes, matches a well-known NSTextTable workaround used in production editors.
- Cons: ZWS chars now flow through the attributed string; need to be careful about width measurement (D24.2 cell measurement uses `cellNaturalText` which would now contain ZWS — would measure 0 width since ZWS is zero-width by definition, but verify).

**Option B — override `insertText` in `LiveRenderTextView` (heavier).**
- Before super.insertText, detect caret-in-empty-cell via `cellTableInfo` + paragraph length check.
- If so, explicitly set `typingAttributes` from the cell paragraph's style.
- Pros: addresses root cause (typingAttributes inheritance).
- Cons: touches the input pipeline; more edge cases (selection replace, multi-char paste, IME input).

### Recommendation

Option A. The ZWS workaround is the canonical fix for NSTextTable-empty-cell editing and is contained to two files. The secondary serializer guard fix is one line. Total ~30 LOC + tests.

Scope as a small D# deliverable (D32?) or land as a hotfix? Bug is reliably reproducible, has clear root cause, and the fix is well-bounded. Argues for hotfix discipline (small commits on main + dogfood retest) rather than full triad.
