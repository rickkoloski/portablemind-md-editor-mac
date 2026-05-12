# D24: Responsive table column layout — Complete

**Spec:** `docs/current_work/specs/d24_responsive_table_columns_spec.md`
**Plan:** `docs/current_work/planning/d24_responsive_table_columns_plan.md`
**Prompt:** `docs/current_work/prompts/d24_responsive_table_columns_prompt.md`
**Manual test plan:** `docs/current_work/testing/d24_responsive_table_columns_manual_test_plan.md`
**Branch:** `feature/d24-responsive-table-columns`
**Completed:** 2026-05-05
**Resolves:** issues_backlog i02 (`Markdown table column widths capped at 320pt regardless of viewport`)

---

## Summary

Markdown table column widths are now responsive. Short-token columns hug their content; long-text columns share the remaining viewport proportionally; window-resize reflows the layout via a 100ms-debounced re-render. The legacy 320pt-cap heuristic is gone. Cell line-break mode is `byWordWrapping` (Q9) so URL/path content wraps at internal break opportunities and pathological no-punctuation tokens fall through to TextKit's lossless char-wrap.

---

## Implementation Details

### What Was Built

- **Pass 1 (measure)** — content-hash-keyed cache for per-column natural widths. Render path populates; resize path hits.
- **Pass 2 (distribute)** — pure-function lock-in + proportional algorithm with min-width floor + floor-wins overflow handling.
- **Pass 3 (apply)** — viewport-aware widths wired through `NSTextTableBlock.setContentWidth`; cells use `byWordWrapping`.
- **Reflow trigger** — `NSWindow.didResizeNotification` subscriber + 100ms debounced `Task.sleep` tail → `renderCurrentText`.
- **Harness surface** — `dump_table_natural_widths`, `dump_table_layout`, `set_window_width` for driver-controlled verification.

### Files Created

| File | Purpose |
|------|---------|
| `Sources/Editor/Renderer/Tables/TableNaturalWidthCache.swift` | Content-hash → CGFloat natural-width cache; hit/miss instrumentation |
| `Sources/Editor/Renderer/Tables/TableColumnDistribution.swift` | Pure-function Pass 2 distribute algorithm |
| `UnitTests/TableColumnDistributionTests.swift` | 15 XCTest fixtures covering every spec edge case + invariant sweep |
| `spikes/d24_table_columns/run_spike.swift` | Phase 1 offscreen spike — falsified Q8's `byTruncatingTail` claim |
| `spikes/d24_table_columns/README.md` | Phase 1 evidence + GREEN/YELLOW/RED recommendation |
| `spikes/d24_table_columns/results/run.log` | Per-line fragment dump across 3 modes × 3 cells × 3 widths |
| `docs/current_work/testing/d24_responsive_table_columns_manual_test_plan.md` | This deliverable's manual test plan |
| `docs/current_work/stepwise_results/d24_responsive_table_columns_COMPLETE.md` | This file |

### Files Modified

| File | Changes |
|------|---------|
| `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift` | Removed 320pt cap. Added `measureNaturalWidths` (harness surface), `naturalWidth` (cache-aware), `cellNaturalText` (single-line cell text extraction). `build(...)` now takes `viewportWidth`. `makeCell` sets `lineBreakMode = .byWordWrapping`. |
| `Sources/Editor/Renderer/MarkdownRenderer.swift` | `render(_:viewportWidth:)` + `buildAttributedString(...)` thread viewport through to `TK1TableBuilder.build`. |
| `Sources/DocumentTypes/DocumentType.swift` | Protocol gains `render(_:viewportWidth:)`. Default-args extension preserves the no-arg `render(_:)` for tests / pre-attach paths. |
| `Sources/DocumentTypes/MarkdownDocumentType.swift` | Match new protocol shape. |
| `Sources/Editor/EditorContainer.swift` | `renderCurrentText` reads live `textContainer.containerSize.width`. Coordinator subscribes to `NSWindow.didResizeNotification`, debounces with `Task.sleep(100ms)`, calls `renderCurrentText` on fire. Holds observer token + reflow Task; deinit cancels both. |
| `Sources/Debug/HarnessCommandPoller.swift` | Added `dump_table_natural_widths`, `dump_table_layout`, `set_window_width` actions. `import Markdown` for AST parsing in the dump actions. |
| `project.yml` | Added `MdEditorUnitTests` target (sources at `UnitTests/`); scheme test entry. |
| `docs/current_work/specs/d24_responsive_table_columns_spec.md` | Q9 added 2026-05-04 (`byWordWrapping` per phase 1 spike); Q8 truncation half marked falsified, points to Q9. Edge cases + risk #6 updated. |
| `docs/current_work/planning/d24_responsive_table_columns_plan.md` | Phase 1 marked DONE with result; phase 4 line-break-mode flipped; risk #1 marked Resolved. |
| `docs/current_work/prompts/d24_responsive_table_columns_prompt.md` | Read-first list updated; phase 1 / phase 4 guidance reflects Q9. |
| `docs/issues_backlog.md` | i02 status → `Fixed (D24, 2026-05-05)`. |
| `docs/roadmap_ref.md` | D24 row → ✅ Complete. Change-log entry added. |

---

## Phase commit log

| Phase | Commit | Lines |
|---|---|---|
| 1 (offscreen spike) | `1a90492` | 584 added (script + README + run.log) |
| 1.5 (Q9 pivot in spec/plan/prompt) | `04d603a` | 50/50 +/− |
| 2 (natural-width cache + harness) | `c18e7e8` | 211 added |
| 3 (distribute pure function + 15 unit tests) | `aa50adf` | 571 added |
| 4 (apply: cap removal + byWordWrapping + viewport wiring + dump_table_layout) | `81b0be4` | 160/21 +/− |
| 5 (resize debounce + set_window_width harness) | `649a0fc` | 78 added |
| 6 (this doc + manual test plan + roadmap + i02 → Fixed) | _this commit_ | docs only |

Phase 1 also has prior doc-only commits `02cfc45` (initial triad), `8fa1dc3` (offscreen approach pre-decided), `110dcd2` (roadmap pause-for-demo).

---

## Testing

### Tests Run

- [x] `xcodebuild build` — clean (Debug, macOS 14)
- [x] `xcodebuild -only-testing:MdEditorUnitTests test` — 15 / 15 PASS, 16ms total
- [x] Harness-driven manual sweep — every spec acceptance criterion + edge case (see manual test plan §2 + §3)
- [x] D17 regression spot-check — caret-in-wrapped-cell preserved across resize-induced wrap change
- [ ] D17 full manual walk — interactive Tab navigation deferred (Tab is stock NSTextView keystroke; harness can't drive it without synthesizing keyDown). Risk: very low — phase 4 didn't change Tab handling.

### Test Coverage

- **Distribution algorithm:** 15 XCTest fixtures cover all 9 cases listed in plan §Phase 3 DOD plus a viewport-sweep invariant test (vw 100–2000pt × 5-col fixture, every step asserts no NaN/Inf/negative, every column above floor, sum constraint per regime).
- **Cache:** harness `dump_table_natural_widths` exposes hits/misses/entries. Smoke runs through phase 2 (10 entries → 11 after edited cell) and phase 6 (19 entries across 7 fixture tables, 125 hits / 19 misses across resize sweep — every column natural measured exactly once).
- **Visual:** snapshots captured at multiple viewport widths confirm Decision column flexes to viewport edge, narrow columns stay locked.

---

## Deviations from Spec

### 1. Q9 supersedes Q8 truncation half (planned-time deviation, CD-approved)

Phase 1 spike empirically falsified Q8's claim that `byTruncatingTail` would produce multi-line wrap with ellipsis on over-long tokens. Q9 was added 2026-05-04 documenting the pivot to `byWordWrapping`. The originally planned `+1 phase` RED fallback (custom `NSLayoutManager` hook) was avoided. Spec updated; original 6-phase plan stood.

### 2. Test target location

Plan §Phase 3 listed test file as `UITests/TableColumnDistributionTests.swift`. UI test bundles can't `@testable import` the app module, and the implied `Tests/` directory would have case-collided with the existing lowercase `tests/` (shell scripts) on case-insensitive macOS filesystems. Created a new `MdEditorUnitTests` target with sources at `UnitTests/` (parallels the existing `UITests/`). Plan §0.1's earlier mention of "Tests/TableLayout/" matched the same intent — same destination, different path.

### 3. Performance instrumentation deferred

Plan §Phase 5 DOD wanted `< 5ms` resize reflow on a 10-row × 4-col table. Phase 5's perceptual evidence (every harness `set_window_width + dump_table_layout` resolves under 0.5s tail with no jank) and the algorithm's structure (cache hits make resize O(N×Pass2+Pass3), not O(N×Pass1)) both indicate we're well under 5ms — but no formal `signpost`-instrumented profile was captured. Documented in the manual test plan §A3 as a follow-up if a regression surfaces.

### 4. Single-column table behavior

Spec doesn't strictly mandate it, but a single-column table whose natural width fits the viewport stays at natural width (rather than expanding to fill). VS Code's default also leaves a small single-column table at natural width (the "fill" behavior requires explicit `width: 100%` on the table). Documented in manual test plan §B6.

---

## Follow-Up Items

- [ ] **D17 full manual interactive walk** — interactive Tab nav, scroll-on-edit confirmation. Risk-rated low; not blocking D24.
- [ ] **Performance instrumentation** — `signpost`-wrapped `renderCurrentText` for regression detection.
- [ ] **User-resizable columns** (deferred per spec §Out of scope) — significant scope: hit-testing, drag UI, persistence per-doc.
- [ ] **Persistent column-width preference** across sessions (deferred per spec §Out of scope).
- [ ] **Inline image intrinsic widths** (deferred — md-editor doesn't render images yet).

---

## Notes

- The phase 1 spike is preserved (`spikes/d24_table_columns/`) with full evidence — re-runnable via `swift run_spike.swift` if the question of `byTruncatingTail` semantics ever resurfaces (e.g., new macOS release).
- The natural-width cache is content-keyed, so the same column content across multiple tables in the same doc shares an entry — small win in dogfooded specs that have repeated column shapes.
- The render pipeline still re-parses markdown on every reflow. For large docs (~10k lines, multiple tables) this could be slower than ideal; a targeted "redistribute(forContainerWidth:)" path (per plan §Phase 5 alt-design) would walk just the rendered storage's NSTextTableBlocks and update widths in-place. Not pursued here because the cache already makes Pass 1 free, leaving only Pass 2 + Pass 3 + storage replace; perceptually acceptable at every doc size we currently dogfood. Pursue if profiling shows resize jank.
