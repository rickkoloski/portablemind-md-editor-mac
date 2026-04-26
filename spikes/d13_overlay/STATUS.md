# D13 Spike — Status

**Last updated:** 2026-04-26
**Spec:** `docs/current_work/specs/d13_cell_edit_overlay_spike_spec.md`
**Plan:** `docs/current_work/planning/d13_cell_edit_overlay_spike_plan.md`
**Findings:** `FINDINGS.md`

---

## Where we are

Phase 1 sandbox bring-up complete. Three seed tables (single-line, wrapped 2–3 visual lines, empty cells) render with cell borders, header tinting, and proper wrap behavior. Harness mirrors D12 spike (commands at `/tmp/d13-command.json`, snapshots at `/tmp/d13-shot.png`, state dumps at `/tmp/d13-state.json`).

Tier 1 (overlay show/hide/commit lifecycle) GREEN — show, type, commit, cancel, re-show all verified via harness.

---

## Tier progress

- [x] Phase 1 sandbox + harness
- [x] Tier 1 — overlay show/hide/commit lifecycle
- [ ] **Tier 2 — click-to-caret math (PRIMARY UNKNOWN)**
- [ ] Tier 3 — visual continuity
- [ ] Tier 4 — wrapping in overlay
- [ ] Tier 5 — Tab/Enter/Escape + scroll
- [ ] Tier 6 — source-splice round-trip
- [ ] Tier 7 — empty cell + edge cases

---

## How to resume this session

### Quick start

```bash
cd ~/src/apps/md-editor-mac/spikes/d13_overlay
./run.sh
```

Window opens on the screen with the largest visibleFrame at logical (100, +50) from top-left. Logs go to `/tmp/d13-spike-app.log`.

### CC-driven harness

Write JSON to `/tmp/d13-command.json`. Read results from:
- `/tmp/d13-state.json` (after `dump_state`)
- `/tmp/d13-shot.png` (after `snapshot`)
- `/tmp/d13-window.json` (after `window_info`)
- `/tmp/d13-cells.json` (after `cell_screen_rects` — stub for Tier 1)

Actions:
| Action | Effect |
|---|---|
| `dump_state` | Writes source, selection, windowFrame, overlay info |
| `snapshot` | App-side `cacheDisplay` PNG — sidesteps multi-display screencapture issues |
| `window_info` | Window + screen frames |
| `set_text` / `reset_text` / `set_selection` | Drive editor state |
| `show_overlay_at_table_cell` (table, row, col) | Mount overlay programmatically (skips screen coords) |
| `type_in_overlay` (text) | Insert chars into active overlay |
| `commit_overlay` / `cancel_overlay` | Programmatic equivalents of Enter / Escape |

### Resume prompt

> Continue the D13 cell-edit overlay spike at `spikes/d13_overlay/`. Read `FINDINGS.md` and `STATUS.md`. Phase 1 + Tier 1 are GREEN. Pick up at Tier 2 — click-to-caret math (THE primary unknown). Implement spec §3.5 algorithm: CTFramesetter on cell content at columnWidth × ∞, stack CTLines, find line containing relY, then CTLineGetStringIndexForPosition. Drive every test case via harness. Record findings in FINDINGS.md.

---

## State of git / repo

| Commit | Summary |
|---|---|
| `7ecb072` | D13 spike triad + Phase 1 sandbox bring-up |
| (next) | D13 spike Tier 1 — overlay show/hide/commit lifecycle GREEN |
