## D13 Spike: Cell-Edit Overlay — Implementation Plan

**Spec:** `d13_cell_edit_overlay_spike_spec.md`
**Production spec (target):** `d13_cell_edit_overlay_spec.md`
**Created:** 2026-04-25
**Timebox:** 1–2 days; extendable per D12 pattern.

---

## Overview

Build a self-contained SwiftPM app at `spikes/d13_overlay/` that places a single in-place overlay text view over GFM table cells. Validate the click-to-caret math from production spec §3.5 against wrapped-cell content. Run validation tiers via the D12 harness pattern. Record findings in FINDINGS.md; track tier completion in STATUS.md. Escalate any RED outcome before touching production `Sources/`.

---

## Prerequisites

- [ ] D12 shipped at v0.1 (commit `30f65a9`, tag `v0.1`).
- [ ] D12 spike harness pattern reviewed (`spikes/d12_cell_caret/STATUS.md` § Automation harness).
- [ ] Production D13 spec drafted (`d13_cell_edit_overlay_spec.md`).
- [ ] `cliclick` installed; macOS Accessibility permission granted to `osascript` + `cliclick` (one-time grant from D12 spike persists).

---

## Phase 1 — Sandbox bring-up

### Step 1: SwiftPM scaffold

**Files:** `spikes/d13_overlay/Package.swift`, `spikes/d13_overlay/Sources/D13Spike/main.swift`, `spikes/d13_overlay/run.sh`, `spikes/d13_overlay/D13Spike.app/` (template Info.plist)

Mirror D12 spike's structure:

- SwiftPM executable target.
- `run.sh` builds the executable, copies into `D13Spike.app/Contents/MacOS/`, opens the bundle.
- `Info.plist` includes `NSPrincipalClass = NSApplication`, `LSUIElement = false`, bundle identifier `com.local.md-editor.d13spike`.
- Window opens at screen `(100, 100)`, sized ~900×700, with split layout: top = scroll-view-hosted NSTextView, bottom = log pane + status row.

The seed document is a markdown buffer with three tables targeted at the spike's tier needs:

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

Render the buffer through a thin reusable subset of the production renderer — minimum needed: parse the GFM tables into `(cellRanges, columnWidths, rowHeights)`, draw each row as a custom `NSTextLayoutFragment`. **Avoid re-implementing the full production stack** — copy only what's needed to render a wrapped grid; document any divergence in FINDINGS.

### Step 2: Reuse the D12 harness pattern

**Files:** `spikes/d13_overlay/Sources/D13Spike/HarnessCommandPoller.swift`, plumbing in `main.swift`.

Port the D12 harness verbatim, retargeted to `/tmp/d13-command.json`:

| Action | Result file | Purpose |
|---|---|---|
| `dump_state` | `/tmp/d13-state.json` | source, selection, parsed cellRanges, **overlay state** (active? cell? content? selection?) |
| `snapshot` | `/tmp/d13-shot.png` | window content PNG for visual-diff checks |
| `window_info` | `/tmp/d13-window.json` | window screen coords for cliclick targeting |
| `cell_screen_rects` | `/tmp/d13-cells.json` | per-cell screen rects for tier-driven precise clicks |
| `set_text` / `reset_text` / `set_selection` | inline result | drive editor state |
| `commit_overlay` / `cancel_overlay` (NEW) | inline result | force commit/cancel programmatically for tier 5 |

Marked with `// TEST-HARNESS:` comments per project convention.

---

## Phase 2 — Tier-driven validation

The spike progresses by tier. Each tier ends with: (a) a tier section in FINDINGS.md with case IDs + observed-vs-expected, (b) a check-mark in STATUS.md, (c) a checkpoint commit on `main` if non-trivial code changed (D12 spike pattern: ≥1 commit per major tier).

### Tier 1 — Overlay show / hide / commit lifecycle ⏱ ~2h

Cases:

- **1a** — single-click in single-line cell shows overlay at cell rect; overlay content matches cell text; caret at offset 0.
- **1b** — type in overlay; characters appear; caret advances.
- **1c** — click outside overlay → commit fires; source range replaced; overlay hides; grid re-renders with new content.
- **1d** — Escape → cancel; overlay hides; source unchanged.
- **1e** — Enter → commit (V1 default per spec §3.3).
- **1f** — re-click in different cell after commit → fresh overlay shows; no leaked state.

Mechanism: `CellEditOverlay: NSTextView` subclass with `commit()` / `cancel()` methods + delegate callback. `CellEditController` owns the singleton overlay, holds show/hide methods, and is wired to a click handler in the spike's NSTextView subclass.

### Tier 2 — Click-to-caret math (PRIMARY) ⏱ ~3–4h

Cases (in priority order):

- **2a** — single-line cell, click left half → overlay shows with caret in left half. Verify x-position via dump_state.
- **2b** — single-line cell, click right of last char → caret at end of content (`length`).
- **2c** — wrapped cell, click on visual-line-1 → caret on line 1 at clicked x.
- **2d** — wrapped cell, click on visual-line-2 → caret on line 2 at clicked x. **(THE primary case.)**
- **2e** — triple-wrapped cell, click on visual-line-3 → caret on line 3.
- **2f** — wrapped cell, click below all lines → caret at content-end.
- **2g** — wrapped cell, click in cellInset.top region → caret at offset 0.
- **2h** — proportional-font cell content (if Q tests it) — caret accuracy via `CTLineGetOffsetForStringIndex` / `CTLineGetStringIndexForPosition`.

Mechanism: implement spec §3.5 algorithm in a `cellLocalCaretIndex(forPoint:rowIdx:colIdx:layout:)` helper. Build CTFramesetter on the cell's NSAttributedString at `CGSize(columnWidth, .infinity)`, suggest a frame, iterate `CTFrameGetLines`, accumulate per-line height as `ascent + descent + leading`, find the line containing `relY`, call `CTLineGetStringIndexForPosition`.

Exit criteria: every case visually correct via dump_state + snapshot. If any case is RED, STOP and escalate.

### Tier 3 — Visual continuity ⏱ ~1h

Cases:

- **3a** — overlay over a cell with the same content → screenshot diff between "overlay active" and "overlay inactive" should differ only in caret presence.
- **3b** — header cell vs body cell font/weight/color matches (if header support is implemented).
- **3c** — overlay's text origin matches cell content origin (no 1-px y-jitter on show).

Mechanism: snapshot before show + immediately after show; visually compare via the tile pane (or external image diff if needed). Adjust overlay's `textContainerInset`, font, and frame until indistinguishable.

### Tier 4 — Wrapping behavior in overlay ⏱ ~1h

Cases:

- **4a** — type past column-width-1 in single-line cell → overlay reflows to line 2; caret on line 2.
- **4b** — Up/Down arrow in wrapped overlay traverses visual lines.
- **4c** — Selection across wrapped lines paints natively (NSTextView's standard highlighting).
- **4d** — Click on line 1 then line 3 → caret moves to line 3 within the overlay (overlay's own click handling, not the show-overlay click).

Mechanism: mostly verify NSTextView default behavior — overlay is just an NSTextView with `isHorizontallyResizable = false`, `textContainer.widthTracksTextView = true`. Document any deviation.

### Tier 5 — Tab / Enter / Escape semantics + scroll ⏱ ~1.5h

Cases:

- **5a** — Tab in overlay commits + re-shows overlay on next cell at offset 0.
- **5b** — Shift+Tab → previous cell, end-of-content.
- **5c** — Tab at last cell of last row → commits + dismisses overlay; main editor caret on line below table.
- **5d** — Shift+Tab at first cell of first row → commits + dismisses.
- **5e** — Enter → commit + (V1) dismiss; OR commit + advance to next-row first cell (validate Q2).
- **5f** — Escape → cancel without committing.
- **5g** — scroll while overlay active → commit fires, overlay hides.
- **5h** — programmatic `commit_overlay` / `cancel_overlay` from harness produces same result as user-driven commit/cancel.

Mechanism: subclass `CellEditOverlay.keyDown(with:)` for Tab/Shift+Tab/Escape interception. Observe `NSScrollView.willStartLiveScrollNotification` on the host scroll view → call `controller.commit()`.

### Tier 6 — Source-splice round-trip ⏱ ~1h

Cases:

- **6a** — type `|` in overlay → commit → source contains `\|` at the typed position; cell content on next show shows `|`.
- **6b** — type a 50-char string in a 5-char cell → row re-renders with widened column (or wrapped, depending on `maxCellWidth` policy).
- **6c** — commit empty content into a cell that previously had text → cell's source range becomes zero-length; row re-renders with empty cell.
- **6d** — paste a multi-line clipboard into overlay → newlines normalized to space on commit.
- **6e** — multi-row table: edit row 2 cell 1 → row 1 and row 3 source unchanged.

Mechanism: `CellEditController.commit()` reads overlay text, applies pipe-escape (`|` → `\|`), normalizes newlines, and replaces the cell's source range via `NSTextStorage.replaceCharacters(in:with:)`.

### Tier 7 — Empty cell + edge cases ⏱ ~0.5h

Cases:

- **7a** — click on an empty cell → overlay shows with 0-length content + caret at 0.
- **7b** — type a char → overlay has 1 char; commit → source has 1 char in cell.
- **7c** — last cell on last row, missing trailing pipe → overlay shows correctly, commit doesn't break the row structure.
- **7d** — cell with leading/trailing whitespace in source → overlay shows trimmed content (consistent with D12's current handling).

---

## Phase 3 — Wrap-up

### Step 3: FINDINGS.md

Final findings document at `spikes/d13_overlay/FINDINGS.md` with:

- One section per tier, with case-level expected/observed/implication-for-production lines.
- A "Math algorithm — final" section documenting the click-to-caret implementation as it ended up (in case the spec §3.5 algorithm needed adjustment).
- A "Production-merge constraints" section listing things production must do that the spike could shortcut.
- A go/no-go recommendation: GREEN, YELLOW (with conditions), or RED (with diagnosis).

### Step 4: STATUS.md

Mirror D12 spike STATUS.md structure:

- "Where we are" — running summary of tier completion.
- "Tiers remaining / done" — checklist.
- "Findings by tier" — quick-reference list of decisions, links into FINDINGS.md.
- "How to resume this session" — quick-start commands + harness reference + resume prompt.
- "State of git / repo" — commits made on the spike.

### Step 5: Decision + handoff

Present results to CD. If GREEN, draft the production triad (`d13_cell_edit_overlay_plan.md` + `d13_cell_edit_overlay_prompt.md`) using spike findings as inputs. If YELLOW, escalate with specific conditions; CD ratifies before production planning. If RED, STOP and discuss alternatives.

---

## Verification checklist

- [ ] `spikes/d13_overlay/` exists and `./run.sh` opens a working overlay-equipped app.
- [ ] Tiers 1–7 each have an entry in FINDINGS.md.
- [ ] Tier 2 §2.1 (click-to-caret math) all cases GREEN or YELLOW-with-CD-accept.
- [ ] FINDINGS.md ends with a clear go/no-go recommendation.
- [ ] STATUS.md shows tier checkmarks + resume prompt.
- [ ] Harness commands work: `dump_state`, `snapshot`, `cell_screen_rects`, `set_selection`, `commit_overlay`, `cancel_overlay`.
- [ ] No modifications to production `Sources/`.
- [ ] Spike commits on `main` checkpoint each major tier.

---

## Risks

1. **Click-to-caret math RED on wrapped cells** — primary spike risk. If `CTLineGetStringIndexForPosition` doesn't return correct indices for the cell's wrapped layout, the overlay approach as designed is unviable. Diagnostic: print `CTLineGetTypographicBounds` for each line and compare to where NSTextView is actually drawing the line; if there's drift, font metric or attribute mismatch is the cause. Mitigation: ensure same NSAttributedString construction path for cell render and overlay's CTFramesetter.

2. **Visual continuity asymptotic but not exact** — `textContainerInset` + line-fragment-padding interactions in NSTextView produce subtle 1–2 px y-jitter that breaks the "indistinguishable" test. Mitigation: explicitly set `lineFragmentPadding = 0` on the overlay's `textContainer`, mirror the cell's `cellInset` exactly. If still off, document the residual offset as a known constraint.

3. **First-responder thrash** — Showing the overlay calls `makeFirstResponder` on the overlay; commit calls it on the main view. Each transition fires `selectionDidChange` notifications that may trigger re-renders, which may invalidate the overlay's frame mid-show. Mitigation: gate any selection-change re-render path on "overlay not active."

4. **Scroll-during-edit edge cases** — User clicks cell, types one char, scrolls; commit fires, but the source change + re-render may itself trigger scroll-position adjustments → infinite loop. Mitigation: snapshot `scrollView.contentView.bounds` before commit; restore after re-render.

5. **Spike harness drift from D12 harness** — Two harnesses living side-by-side risks divergence. Mitigation: copy verbatim from D12, only retarget paths. Once D13 production is merged, the production harness at `Sources/Debug/` is the canonical version; both spikes can be deleted (or frozen).

6. **Timebox slip** — D12 spike grew from 1 day to multi-session; D13 is similar shape. Mitigation: STATUS.md tier discipline. If tier 2 isn't GREEN by end of day 2, escalate before continuing.

---

## Out of scope (production-only concerns)

- Replacing D12's `snapCaretToCellContent` in `LiveRenderTextView` (production merge).
- Integrating with `NSUndoManager` for cell-edit undo grouping (production merge).
- Markdown rendering inside overlay (V1: no; future deliverable).
- Multi-cell drag-select (V1: no; future polish).
- Header-cell-specific overlay styling beyond font (production merge).
- Removing D8.1 single-click trigger artifacts (already done in D12; verify only).
