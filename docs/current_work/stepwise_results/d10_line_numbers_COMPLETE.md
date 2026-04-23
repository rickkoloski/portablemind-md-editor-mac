# D10: Toggleable Line Numbers — COMPLETE

**Shipped:** 2026-04-23
**Spec:** `docs/current_work/specs/d10_line_numbers_spec.md`
**Promoted from:** Harmoniq task #1379 (now marked completed, StatusApplication #2350)

---

## What shipped

Line-number gutter attached to the editor's NSScrollView via a custom `NSRulerView` subclass. Default off. Toggled via **View → Show Line Numbers** and `Cmd+Option+L`. State persists across relaunch via `@AppStorage("lineNumbersVisible")`.

Gutter draws monospaced digits aligned to each text line fragment, using TextKit 2's `NSTextLayoutManager.enumerateTextLayoutFragments` for geometry. Line numbers are mapped from fragment start offsets via a source-string-keyed cache of line-start positions (binary search per draw). Cache invalidates on text change so add/remove-line updates numbers live.

Standards §2.2 preserved — no `.layoutManager` access; all layout reads go through `textLayoutManager`.

---

## Files created / modified

| File | Action |
|---|---|
| `Sources/Editor/LineNumberRulerView.swift` | Create |
| `Sources/Settings/AppSettings.swift` | Modify — add `lineNumbersVisible` |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | Modify — add `viewMenuToggleLineNumbers` |
| `Sources/Editor/EditorContainer.swift` | Modify — observe settings, install/remove ruler, invalidate on text change |
| `Sources/App/MdEditorApp.swift` | Modify — View menu entry + `Cmd+Option+L` |
| `docs/roadmap_ref.md` | Modify — D10 entry ✅ |

---

## Findings

**#1 — NSRulerView + TextKit 2 on macOS 14+: ruler obscures NSTextView content.** First impl attached the ruler correctly (gutter drew with correct line numbers) but the NSTextView rendered blank. Four rounds of speculative fixes failed:
- Flipping init order (`hasVerticalRuler = true` before `verticalRulerView = ruler`).
- `scroll.tile()` after attach.
- `textLayoutManager.textViewportLayoutController.layoutViewport()`.
- Explicit `textView.frame = scroll.contentView.bounds`.

Root cause (via web search, Apple Dev Forums thread 767825): **macOS 14 Sonoma changed `NSView.clipsToBounds` default to `false`**. The ruler's background fill in `drawHashMarksAndLabels(in:)` extends beyond its bounds and covers the text view. The AppKit Release Notes for macOS 14 document the clipsToBounds default change but do not flag the downstream NSRulerView impact.

**Fix:** one line — `self.clipsToBounds = true` in the LineNumberRulerView initializer. Content returns; four previous speculative fixes became unnecessary and were removed.

**Lesson captured:** for any custom NSView that fills its own background in `drawRect` or similar, explicitly set `clipsToBounds = true` on macOS 14+. This is a candidate for an addition to `engineering-standards_ref.md` alongside §2.2 (no `.layoutManager`) — consider §2.5 "AppKit view chrome on macOS 14+: custom views that fill their own background must set `clipsToBounds = true` to avoid obscuring siblings."

**#2 — Process observation: this was the first deliverable where a web search was load-bearing.** Four speculative fixes burned ~15 minutes before the search; the search + fix took ~3 minutes. Pattern to remember: when a speculative fix "feels wrong" after 1-2 attempts on a platform API surface, search before continuing to speculate. The Apple Dev Forums thread was the second result for a natural-language query.

---

## Deviations from spec

None. Step 1-8 executed as planned. The only surprise was Finding #1 — a platform gotcha, not a scope or design change.

---

## Verification

- Build green.
- `grep -r '\.layoutManager' Sources/` returns no new hits (pre-D10 references unchanged).
- Dogfooded: line numbers toggle via `Cmd+Option+L`; numbers align with text; persist across relaunch; update as text is edited (confirmed by adding/removing lines and seeing numbers shift).
- Scroll-to-line (D9) confirmed visually — `./scripts/md-editor docs/roadmap_ref.md:30` with line numbers on landed in the vicinity of line 30 as expected (exact-line targeting observable for the first time).
- D1–D9 unchanged.

---

## Related Harmoniq task

- **#1379** (portablemind project #53) — marked **completed** via `apply_status_tool` / StatusApplication #2350.
- **#1380** (CLI control of line numbers) — now unblocked (this was its prerequisite). Stays in backlog awaiting CD prioritization.

---

## Backlogged from this deliverable

- **§2.5 candidate standard:** "custom NSView subclasses that fill their own background must set `clipsToBounds = true` on macOS 14+." Capture when the next §2.x candidate bundles up.
