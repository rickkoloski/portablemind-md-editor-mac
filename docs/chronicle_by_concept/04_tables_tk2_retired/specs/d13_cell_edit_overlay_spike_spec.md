## D13 Spike: Cell-Edit Overlay — Specification

**Status:** Draft
**Created:** 2026-04-25
**Author:** Rick (CD) + Claude (CC)
**Parent deliverable spec:** `d13_cell_edit_overlay_spec.md`
**Spike location:** `spikes/d13_overlay/`
**Timebox:** 1–2 days; extendable iteratively if a tier surfaces follow-up unknowns (D12 spike pattern).

---

## 1. Why a spike

The D13 production spec posits a Numbers/Excel-style cell-edit overlay as the resolution to D12's wrapped-cell limitation. Before merging the approach into production, the spike must validate the **load-bearing technical bets** in isolation:

1. **Click-to-caret math (production spec §3.5)** can produce a visually-correct caret in a wrapped overlay from a single click anywhere in the cell — including visual-line-2+ of a wrapped cell.
2. **Visual continuity** — the overlay positioned over a cell is indistinguishable from that cell's rendering except for the active caret.
3. **Show / commit / cancel lifecycle** is robust under the realistic event flow (click, type, Tab, Enter, Escape, focus loss, scroll).
4. **Source-splice on commit** correctly handles pipe-escape, newline normalization, and re-render without re-entry bugs.

A Red on (1) or (2) means the overlay approach is unviable as designed and we need to escalate; the spike must surface that within the timebox rather than after a production merge.

---

## 2. In scope

The spike must validate the following in a sandboxed SwiftPM app at `spikes/d13_overlay/`:

### 2.1 Click-to-caret math (primary unknown)

- Click on visual-line-1 of a single-line cell → caret at clicked x on line 1.
- Click on visual-line-1 of a wrapped cell → caret at clicked x on line 1.
- Click on visual-line-2 of a wrapped cell → caret at clicked x on line 2. **(THE primary D13 case.)**
- Click on visual-line-3+ of a triple-wrapped cell → caret on the correct line.
- Click below all lines → caret at end of cell content.
- Click in `cellInset.top` region (above first line) → caret at offset 0.
- Click on rightmost-cell-content-edge → caret at end-of-line on that visual line.

Math must use the algorithm from production spec §3.5: CTFramesetter at `columnWidth × ∞`, stack CTLines with per-line `ascent + descent + leading`, locate `relY` within accumulated y, then `CTLineGetStringIndexForPosition(line, CGPoint(relX, 0))`.

### 2.2 Show / commit / cancel lifecycle

- Show on single-click in a cell: overlay appears at the cell's view-coord rect with content + caret pre-positioned.
- Commit on Enter, Tab, click-outside, focus-loss, scroll: overlay's text replaces the cell's source range; overlay hides; grid re-renders.
- Cancel on Escape: discards overlay edits; overlay hides; main view regains focus.
- Re-show in a different cell after commit: clean state, no leaked overlay residue.

### 2.3 Visual continuity

- Overlay font matches cell rendering (Menlo 14pt or whatever the spike picks; same for header vs body).
- Overlay color matches `NSColor.labelColor`.
- Overlay's `textContainerInset` produces the same content origin as the cell's `cellInset`.
- Background is clear or matches cell fill (none).
- No border on overlay (cell's grid divider remains the visual frame).
- Caret is the standard NSTextView insertion-point.
- Snapshot test: overlay shown over a non-active cell looks ≈ identical to the same cell un-active (modulo blinking caret).

### 2.4 Wrapping behavior inside overlay

- Up/Down arrow within a wrapped overlay traverses visual lines naturally (since overlay is a stock NSTextView).
- Selection across wrapped lines paints natively.
- Typing past column-width-1 reflows; caret tracks.
- This is mostly free since NSTextView handles wrapping — but verify there's no surprise from the overlay's `textContainerSize` or wrapping config.

### 2.5 Source-splice on commit

- `|` typed in the overlay → `\|` in the source after commit (so the row's structural pipes are not disrupted).
- `\|` in the source → `|` in the overlay on show (user sees a literal pipe).
- Newline in the overlay (if Q2 lands on "insert newline" instead of "commit + advance") → single space on commit. (V1 default per spec §3.3 is commit-on-Enter, so newline-in-overlay is unlikely; but if a paste introduces one, normalize.)
- Cell with surrounding cells in the same row is left intact.
- Multi-row table re-renders correctly after commit.

### 2.6 Scroll behavior

- Scroll while overlay active → commit + hide (V1 default per spec §3.6).
- Re-click after scroll lands in the new cell location correctly.

### 2.7 Tab / Shift+Tab semantics (validate spec Q1)

- Tab in overlay commits the current cell and re-shows the overlay on the next cell at offset 0.
- Shift+Tab → previous cell, end-of-content.
- At last cell of last row, Tab commits and dismisses overlay (caret returns to main view at the line below the table).
- At first cell of first row, Shift+Tab commits and dismisses.

### 2.8 Empty-cell handling (validate spec Q3)

- Click on an empty cell → overlay shows with empty content, caret at offset 0.
- Type → content appears.
- Commit with no edits → no source change.
- Commit with content → cell's zero-length range becomes a length-N range; row re-renders with the new cell text.

---

## 3. Out of scope (defer to production merge)

- Inline markdown rendering inside the overlay (Q8 V1 = no; cell content stays plain text).
- Multi-cell drag-select (spec §3.8 V1 = N/A).
- Undo grouping integration with `NSUndoManager` (verify after production merge; spike uses overlay-local undo only).
- Header-cell vs body-cell font differentiation (validate visually but don't proliferate cases).
- D12 single-click `snapCaretToCellContent` removal in production code (Q7; merge concern, not a spike concern).
- Harness `dump_state` schema for overlay state (Q6; nice-to-have, do if time permits).
- D8.1 reveal mode interaction (overlay should not show in revealed rows — verify with a single test, not a tier).
- Multi-line cell content via `<br>` (spec §3.3 V1 = out of scope).

---

## 4. Success criteria

The spike is **GREEN** when all of the following are observably true via the harness or CD-driven manual test:

- [ ] Click on any visual line of a wrapped cell places caret on the correct line at correct x. (§2.1)
- [ ] Type in overlay → content appears at caret; arrow keys traverse visual lines naturally; commit splices cleanly back to source. (§2.2, §2.4, §2.5)
- [ ] Visual continuity: overlay over a cell is screenshot-indistinguishable from the cell un-active. (§2.3)
- [ ] Tab cycles cells with overlay re-mounting per cell. (§2.7)
- [ ] Empty cell shows clean overlay; first character typed becomes the cell's content. (§2.8)
- [ ] Pipe-escape round-trip works (`|` ⇌ `\|`). (§2.5)
- [ ] Scroll-while-active commits cleanly. (§2.6)
- [ ] All findings recorded in `spikes/d13_overlay/FINDINGS.md` with implications-for-production notes (D12-spike pattern).

The spike is **YELLOW** if §2.1 produces correct math but click handling has a bounded oddness CD accepts (e.g., clicks within 1–2 px of a line boundary route to the wrong line — fixable with a snap rule). Document in FINDINGS, escalate to CD for accept/reject.

The spike is **RED** if §2.1 (click-to-caret math) produces visually wrong caret placement that can't be reconciled within the timebox. STOP, do not proceed to production merge, escalate. Possible alternatives: per-cell sub-views (massive refactor), modal dialog (parked break-glass), or abandon D13 as designed.

---

## 5. Deliverables

| Artifact | Location | Required? |
|---|---|---|
| Spike SwiftPM app | `spikes/d13_overlay/` (Package.swift + Sources/ + run.sh) | Yes |
| FINDINGS.md | `spikes/d13_overlay/FINDINGS.md` | Yes |
| STATUS.md | `spikes/d13_overlay/STATUS.md` (running tier completion + resume prompt) | Yes |
| Snapshots | `/tmp/d13-shot.png` snapshots of key visual continuity checks | Yes |
| Harness reuse | Adapt D12's `/tmp/d12-command.json` poller pattern → `/tmp/d13-command.json` | Yes |
| Production-ready code | Out of scope. Spike code is throwaway. | No |

---

## 6. Constraints

- **No production `Sources/` modifications during the spike.** Spike must be self-contained at `spikes/d13_overlay/`.
- **Reuse the D12 harness pattern** — file-based JSON poller + cliclick + osascript. Don't reinvent.
- **Source-as-truth principle** — the cell's source range in the markdown buffer is the only ground truth. Overlay holds derived state only.
- **No `.layoutManager` references in production-style code.** (Engineering-standards §2.2; spike is exempt but good to honor for code that may merge.)
- **Pre-users principle** — build the right thing. No shortcuts to make a tier "pass" if the underlying behavior is wrong.

---

## 7. Risks

1. **CTLine line breaks in overlay differ from cell rendering's** — Both use the same string + same width, but font/locale/attribute mismatches could cause divergence. Mitigation: same NSAttributedString construction path for both.
2. **First-responder ping-pong** — Overlay first-responder transitions could trigger unwanted main-editor selection changes. Mitigation: explicit window.makeFirstResponder(overlay) on show; observe for re-entry in commit flow.
3. **Scroll observation timing** — `willStartLiveScrollNotification` fires before the actual scroll; commit must complete before viewport moves. Mitigation: commit synchronously; if scroll re-fires post-commit, ignore.
4. **Click-routing collision with D12's CellSelectionDataSource** — In production the spike's click handling will be folded INTO LiveRenderTextView's mouseDown, not run alongside CellSelectionDataSource. Spike can use a simpler click path; production merge separately validates the integration.
5. **Empty-cell click coords map to negative or out-of-range offsets** — `CTLineGetStringIndexForPosition` may return `kCFNotFound` (`-1`) for out-of-line clicks. Mitigation: clamp to `[0, contentLength]`.
6. **Overlay leaks across re-renders** — When grid re-renders mid-edit, fragment frames reset. Mitigation: hide overlay on any pre-edit signal; show fresh on next click.

---

## 8. Trace

- **Production D13 spec §3.5** (click-to-caret math) — primary subject of validation.
- **Production D13 spec §6 Q1, Q3** — Tab semantics + empty-cell handling — validated by §2.7, §2.8.
- **D12 architectural finding** (NSTextLineFragment contiguous-range constraint) — context for why the overlay approach exists.
- **D12 spike STATUS.md** — pattern reference for spike structure (tiers, harness, FINDINGS doc, resume prompt).
- **`docs/vision.md` Principle 1** (Word/Docs-familiar authoring) — the user-feel target the spike is ultimately defending.
