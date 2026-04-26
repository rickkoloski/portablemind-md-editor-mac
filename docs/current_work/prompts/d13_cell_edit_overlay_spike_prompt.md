## D13 Spike: Cell-Edit Overlay — CC Prompt

**Spec:** `docs/current_work/specs/d13_cell_edit_overlay_spike_spec.md`
**Plan:** `docs/current_work/planning/d13_cell_edit_overlay_spike_plan.md`
**Production target spec:** `docs/current_work/specs/d13_cell_edit_overlay_spec.md`

---

## Context

D12 shipped per-cell table editing for single-line cells but exposed an architectural limit: NSTextView's `NSTextLineFragment` requires contiguous source ranges, so a row containing one wrapped cell + other cells cannot represent the wrapped cell's visual line 2 with a per-cell line fragment. Result: caret on visual-line-2 of a wrapped cell is inaccessible, and clicks on visual-line-2 route to visual-line-1 source offsets.

D13 proposes a **cell-edit overlay** (Numbers/Excel pattern): on click, mount an in-place reusable NSTextView over the cell, copy the cell's source content into it, and let the user edit there with native wrapping/caret/selection. On commit (Enter, Tab, click-out, scroll, focus-loss), splice the overlay's text back into the cell's source range and hide the overlay.

The load-bearing technical bet is the **click-to-caret math** (production spec §3.5): given a click point inside a cell's visual rect, compute the local character index within the cell content using `CTFramesetter` + `CTLineGetStringIndexForPosition` so that mounting the overlay with that selection puts the caret at the click position — including on visual-line-2+ of a wrapped cell.

**Pre-users principle:** no shortcuts. The overlay must feel and work consistent with what users of other text-editing apps (Word, Docs, Numbers) expect.

**Read before starting:**

- `docs/current_work/specs/d13_cell_edit_overlay_spec.md` — production target; §3.5 is the algorithm to validate.
- `docs/current_work/specs/d13_cell_edit_overlay_spike_spec.md` — what the spike must prove.
- `docs/current_work/planning/d13_cell_edit_overlay_spike_plan.md` — tier-by-tier roadmap.
- `spikes/d12_cell_caret/STATUS.md` — pattern reference for spike structure (tiers, harness, FINDINGS, resume prompt).
- `spikes/d12_cell_caret/run.sh`, `Package.swift`, `Sources/` — concrete model for SwiftPM scaffold + harness.
- `Sources/Editor/Renderer/Tables/TableLayout.swift` — production reference for `cellRanges`, `charXOffset`, `parseCellRanges`.
- `Sources/Editor/Renderer/Tables/TableRowFragment.swift` — production reference for cell drawing geometry (column widths, cellInset, header vs body).
- `Sources/Debug/HarnessCommandPoller.swift` — production harness; spike will mirror its action set retargeted to `/tmp/d13-command.json`.

---

## Task

Implement the D13 spike per the spec + plan. **Do not touch production `Sources/`.** Spike code lives at `spikes/d13_overlay/`.

### Phase 1 — Sandbox bring-up (plan Step 1 + Step 2)

1. Scaffold `spikes/d13_overlay/`:
   - `Package.swift` (SwiftPM executable; macOS 14+).
   - `Sources/D13Spike/main.swift` — NSApplication bring-up, window at `(100, 100)` ~900×700, scroll-view-hosted NSTextView on top, log pane below.
   - `run.sh` — build + bundle into `D13Spike.app/Contents/MacOS/D13Spike` + `open` it.
   - `D13Spike.app/Contents/Info.plist` — `NSPrincipalClass = NSApplication`, bundle ID `com.local.md-editor.d13spike`.

2. Implement a minimum viable subset of the production table renderer:
   - Parse the seed markdown buffer's GFM tables.
   - For each row, register a custom `NSTextLayoutFragment` that draws the cell grid (use `TableRowFragment`'s pattern as a model; keep the spike's version smaller).
   - Pre-compute `cellRanges`, `columnWidths`, `cellContentPerRow` per the production approach.
   - Wrap support is required — long content must wrap inside its column.

3. Seed buffer (verbatim from spike plan §1):

   ```markdown
   # D13 Spike

   ## Single-line cells (control)

   | A | B |
   |---|---|
   | one | two |

   ## Wrapped cells (PRIMARY)

   | Description                         | Status |
   |-------------------------------------|--------|
   | This is intentionally long enough to wrap across at least two visual lines inside its column. | OK |
   | Short                              | Triple-wrap candidate: this content is even longer to push it to three visual lines so the spike can validate clicks beyond line 2. |

   ## Empty cells

   | col1 |   | col3 |
   |------|---|------|
   | a    |   | c    |
   ```

4. Port the D12 harness to the spike:
   - `Sources/D13Spike/HarnessCommandPoller.swift` polls `/tmp/d13-command.json` every 200ms.
   - Actions: `dump_state`, `snapshot`, `window_info`, `cell_screen_rects`, `set_text`, `reset_text`, `set_selection`.
   - **New actions for D13:** `commit_overlay`, `cancel_overlay` — programmatic equivalents of user-driven commit/cancel for tier 5.
   - `dump_state` payload extended: include `overlay: { active, cellRow, cellCol, content, selectionLocation, selectionLength }` when the overlay is mounted, `null` otherwise.
   - Mark all harness code with `// TEST-HARNESS:`.

5. Verify build green and `./run.sh` opens a working app rendering the seed buffer with all three tables visible. **Commit Phase 1** before starting tier work.

### Phase 2 — Tier-driven validation (plan tiers 1–7)

Work through the tiers in order. **At the start of each tier, write a tier section header in `spikes/d13_overlay/FINDINGS.md`. After each case, append observed-vs-expected-vs-implication. At the end of each tier, update STATUS.md and commit.**

Drive every test case through the harness (cliclick + osascript + JSON commands). Do not ask CD for click tests until at least Tier 2 (the primary unknown) has been worked through automation. The D12 spike shipped tier 1–6 fully harness-driven; do the same here.

**Tier ordering rationale:**
- Tier 1 (lifecycle) before Tier 2 (math) because show/hide must work before caret position can be observed.
- Tier 2 (math) is the primary unknown — if it's RED, STOP and escalate.
- Tier 3 (visual continuity) follows because it's verified visually after the overlay can mount.
- Tiers 4–7 are progressively narrower — wrapping behavior, keyboard/scroll semantics, source-splice round-trip, edge cases.

Build the `CellEditOverlay` (NSTextView subclass) and `CellEditController` per production spec §3.1 — but as throwaway spike code, not as the final classes. The names + protocols can be reused on production merge; the implementations will be rewritten against the production codebase's conventions.

The click-to-caret math implementation should be a free function or a static method on the spike's TableLayout-equivalent: `cellLocalCaretIndex(forPoint:rowIdx:colIdx:layout:) -> Int`. Algorithm per production spec §3.5:

```
1. Click in view coords (cx, cy).
2. Convert to cell-content-local coords:
     relX = cx - (cellOriginX + cellInset.left)
     relY = cy - (cellOriginY + cellInset.top)
3. CTFramesetter on the cell's NSAttributedString, suggested frame = (columnWidth, .infinity).
4. Iterate CTFrameGetLines, accumulating per-line height (ascent + descent + leading):
     accumulatedY = 0
     for each line:
       lineHeight = ascent + descent + leading
       if relY ∈ [accumulatedY, accumulatedY + lineHeight):
         return CTLineGetStringIndexForPosition(line, CGPoint(relX, 0))
       accumulatedY += lineHeight
5. Click below all lines → return cell.content.length
6. Click above first line → return 0
```

Clamp the result to `[0, content.length]` to defend against `kCFNotFound`.

### Phase 3 — Wrap-up (plan Step 3 + Step 4 + Step 5)

1. Finalize `spikes/d13_overlay/FINDINGS.md` per spec §5 — one section per tier, math-algorithm-final section, production-merge-constraints section, go/no-go recommendation.
2. Finalize `spikes/d13_overlay/STATUS.md` per spec §5 + D12 STATUS.md as model — tier checkmarks, findings cross-refs, resume prompt, git state.
3. Present results to CD with the go/no-go recommendation. **Do not start the production triad without CD's accept on the spike outcome.**

---

## Constraints

- **Spike code is throwaway** — no migration of spike files into production `Sources/`. Production merge will be a separate deliverable with its own triad.
- **No production `Sources/` modifications during the spike.**
- **No `.layoutManager` references** in any code that may merge to production (spike is exempt for prototyping but document any such use in FINDINGS).
- **Source is truth** — overlay holds derived state; commit splices back to the markdown buffer's `NSTextStorage`.
- **No modal dialog fallback** — if the spike goes RED, escalate to CD before any plan B.
- **Pre-users principle** — build the right thing. Don't paper over a tier failure.
- **Harness-first** — drive tier validation via `/tmp/d13-command.json` + `cliclick` + `osascript`. CD click-tests are a final acceptance, not the iteration loop.
- **Commit per tier** — at minimum one checkpoint commit per major tier (D12 spike pattern). Use `git log` against `spikes/d12_cell_caret/` for commit-message style reference.

---

## Success Criteria

- [ ] `spikes/d13_overlay/` scaffolded; `./run.sh` opens a working overlay-equipped app rendering the three seed tables.
- [ ] Tier 1 (lifecycle) GREEN — show, type, commit, cancel, re-show all work via harness.
- [ ] Tier 2 (click-to-caret math) GREEN — click on every visual line of a wrapped cell places caret correctly. **(Primary spike success criterion.)**
- [ ] Tier 3 (visual continuity) GREEN — overlay over a cell is visually indistinguishable from the cell un-active.
- [ ] Tier 4 (wrapping in overlay) — Up/Down arrow + selection + reflow all work natively.
- [ ] Tier 5 (Tab/Enter/Escape + scroll) — semantics validated against spec Q1 and Q2.
- [ ] Tier 6 (source-splice round-trip) — pipe-escape, newline normalization, multi-row independence all GREEN.
- [ ] Tier 7 (empty cell + edge cases) GREEN.
- [ ] `spikes/d13_overlay/FINDINGS.md` complete with go/no-go recommendation.
- [ ] `spikes/d13_overlay/STATUS.md` complete with resume prompt.
- [ ] No production `Sources/` modifications.

---

## On Completion

1. Tag the spike completion commit (e.g., `d13-spike-green` or similar — confer with CD on tag scheme; v0.1 was the last release tag).
2. Present results to CD: tier-by-tier summary, go/no-go recommendation, any unknowns surfaced for the production merge.
3. **If GREEN:** draft the production triad next (`d13_cell_edit_overlay_plan.md` + `d13_cell_edit_overlay_prompt.md`) using spike findings as inputs. The existing `d13_cell_edit_overlay_spec.md` may need spec updates if the spike surfaced behavior the spec didn't anticipate.
4. **If YELLOW:** escalate with specific conditions; CD ratifies before production planning.
5. **If RED:** STOP. Discuss alternatives with CD: per-cell sub-views (refactor cost), modal break-glass (parked per memory `md_editor_d12_break_glass_fallback.md`), or abandon D13.
6. Update `docs/current_work/HYDRATION.md` with spike completion + next-step pointers (D12 pattern).
