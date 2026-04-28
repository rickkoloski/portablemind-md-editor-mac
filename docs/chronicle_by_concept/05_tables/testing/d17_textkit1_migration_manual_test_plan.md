# D17: TextKit 1 Migration — Manual Test Plan

**Spec:** `docs/current_work/specs/d17_textkit1_migration_spec.md`
**Plan:** `docs/current_work/planning/d17_textkit1_migration_plan.md`
**Created:** 2026-04-26

---

## Setup

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Test docs:
- `docs/vision.md` — no tables, used to confirm baseline rendering.
- `docs/roadmap_ref.md` — one table (~13k chars), used for table cases.
- (optional) `~/src/apps/harmoniq/harmoniq-frontend/docs/00_CURRENT_WORK/planning/d09_task_conversations_files_plan.md` — multi-table doc (~24k chars) for stress.

---

## A. Doc lifecycle

| Test | Action | Expected |
|---|---|---|
| A1 | Open `docs/vision.md`. | Headings, bold/italic, lists, blockquotes render correctly. Line numbers gutter aligned with paragraphs (toggle on with ⌘⌥L if needed). |
| A2 | Open `docs/roadmap_ref.md`. | Tables render as a native grid with column borders, header bolding, wrapped descriptions stack visual lines inside cells. |
| A3 | (If d09 available) Open it. Multiple tables present. | Each table renders correctly. |
| A4 | Switch tabs between docs multiple times. | Each tab shows correct rendering immediately on focus; no flicker or blank state. |

---

## B. Click + caret

| Test | Action | Expected |
|---|---|---|
| B1 | Click in a cell mid-table (e.g., D6's Description cell). | Caret lands inside cell text. Cursor blinks normally. |
| B2 | Type a few characters. | Characters appear at the click point. Scroll position holds. No overlay/popup mounts. |
| B3 | Click in a wrapped cell on visual line 2 (e.g., D6's full description wraps). | Caret lands at the right offset within the cell — somewhere in the second visual line. |
| B4 | Click in a paragraph outside any table. | Caret behaves normally. Type — characters insert. |
| B5 | Drag-select across cell boundary or paragraph boundary. | Selection is contiguous in the displayed text (which differs from selection in markdown source for tables — that's expected). |

---

## C. Tab navigation

| Test | Action | Expected |
|---|---|---|
| C1 | Click any cell. Press Tab. | Caret moves to start of the NEXT cell of the same table, in the same row (or first cell of next row if at end). |
| C2 | Press Shift+Tab. | Caret moves to start of the PREVIOUS cell. |
| C3 | Tab past last cell of the table. | Tab inserts a literal tab character at the current cell's end (stock NSTextView default). Subsequent Tab continues to insert tabs. (Multi-table cycling not in D17 scope.) |
| C4 | Click in a non-cell paragraph. Press Tab. | Tab inserts a literal tab character (stock NSTextView default outside cells). |

---

## D. Save / Save As (D14 regression)

| Test | Action | Expected |
|---|---|---|
| D1 | Edit a cell ("D1" → "D1x"). ⌘S. | Save completes silently. `cat docs/roadmap_ref.md` shows the edit reflected in markdown form (`\| D1x \|` instead of `\| D1 \|`). Pipes intact. |
| D2 | Open a fresh markdown file via Open (⌘O). Edit. ⌘S. | Save round-trip clean. |
| D3 | ⌘⇧S → save copy to a new path. | New file at chosen path. Tab title updates. |
| D4 | After Save As, ⌘S. | Saves to the NEW path (doc.url updated). |

---

## E. Scroll behavior

| Test | Action | Expected |
|---|---|---|
| E1 | Open roadmap_ref.md. Scroll deep using mouse wheel. | Tables continue rendering correctly past the initial viewport. No blank gaps, no missing rows. |
| E2 | Type a character mid-cell, then scroll up/down. | Scroll position behaves normally. No jumps related to typing. |
| E3 | Click at end of doc, type Return. | Scroll follows the new caret if it would otherwise be offscreen (stock NSTextView behavior). |
| E4 | `./scripts/md-editor docs/roadmap_ref.md:42`. | Editor opens scrolled to line 42. |

---

## F. Line numbers / view-state flags

| Test | Action | Expected |
|---|---|---|
| F1 | Toggle line numbers via View → Show Line Numbers (⌘⌥L). | Gutter appears. Line numbers align with paragraphs. |
| F2 | Toggle off. | Gutter disappears. |
| F3 | `./scripts/md-editor docs/vision.md --line-numbers=on`. | Doc opens with line numbers visible. |
| F4 | Same with `--line-numbers=off`. | Doc opens with no line numbers. |

---

## G. External edit watcher

| Test | Action | Expected |
|---|---|---|
| G1 | With doc open in editor, in another shell: `echo "external" >> /path/to/file.md`. | Buffer reflects new content within ~1s (NSFilePresenter). |
| G2 | Save → external edit → save again. | No corruption. No infinite loop. |
| G3 | Edit in editor → external `echo > file.md`. | External edit wins (replaces buffer with file content). |

---

## H. Debug HUD

| Test | Action | Expected |
|---|---|---|
| H1 | Toggle View → Show Debug HUD (⌥⌘D). | Toolbar trailing shows `scrollY=N click=(X,Y) line=N frag=… fragY=N`. |
| H2 | Click a cell. | HUD's `frag` field reads `tbl(r=N,c=N)` with row/col matching the cell you clicked. |
| H3 | Click outside any table. | HUD's `frag` reads `para`. |
| H4 | Scroll. | `scrollY` updates live. |

---

## I. No-table content (regression — TK1 should NOT have changed anything here)

| Test | Action | Expected |
|---|---|---|
| I1 | Headings (H1–H6). | Render with appropriate font sizes. |
| I2 | Bold (`**`), italic (`*`). | Render bold / italic. |
| I3 | Inline code (`` ` ``). | Render in code font with background tint. |
| I4 | Code blocks (triple-backtick). | Render in code font with background tint, fence delimiters tagged. |
| I5 | Links (`[label](url)`). | Render with link color + underline. |
| I6 | Bullet / numbered lists. | Render with appropriate indentation and markers. |
| I7 | Cursor-on-line collapse/reveal of delimiters. | Type `**foo**` — delimiters collapse when caret leaves the line, reveal when caret returns. (Existing live-render behavior.) |

---

## J. Edge cases

| Test | Action | Expected |
|---|---|---|
| J1 | Open an empty file. | Renders empty. Type — characters appear. |
| J2 | Open a file with only a table (no preamble). | Table renders. |
| J3 | Open a file with a table at the very end (no postamble). | Table renders. |
| J4 | Edit a cell to be empty. ⌘S. | Saves with empty cell content (`| \|`). |
| J5 | Edit a cell to contain a `\|` literal. | Cell displays `\|`; save round-trips with `\\\|` escaping. |
| J6 | Two adjacent tables. | Both render correctly. |

---

## K. Build hygiene

| Test | Action | Expected |
|---|---|---|
| K1 | `grep -rn 'NSTextLayoutFragment\|NSTextLayoutManager' Sources/` | Only doc-comment references explaining what was retired. No live code. |
| K2 | `grep -rn 'TableRowFragment\|TableLayoutManagerDelegate\|TableRowAttachment\|CellEditOverlay\|CellEditController\|CellEditModalController\|CellSelectionDataSource\|TableLayout\b' Sources/` | Same — only doc comments. |
| K3 | `xcodebuild` clean build. | `BUILD SUCCEEDED` with no errors. Warnings about TK1 enum names (`absoluteValueType`, etc.) are acceptable. |

---

## Failure pointers

- **A1/A2 visual layout broken** — check that `LiveRenderTextView`'s init sets `isVerticallyResizable=true` and the maxSize. Without those, the documentView has zero height and the scroll view shows nothing.
- **B1 click doesn't land caret** — confirm `NSTextView` is editable (`isEditable=true` set in `EditorContainer.makeNSView`). Confirm the textView's textContainerInset matches what the renderer assumes.
- **C1/C2 Tab doesn't move** — confirm `LiveRenderTextView.advanceCellOnTab` is detecting cell paragraphs; check `paragraphStyle.textBlocks` is set on cell paragraphs (it should come from `TK1TableBuilder.makeCell`).
- **D1 save loses pipes** — bug in `TK1Serializer.serialize`. Verify it groups cell paragraphs by `NSTextTable` instance and emits `| ... |` row syntax.
- **E1 scroll into table renders blank** — should NOT happen on TK1. If it does, check `MarkdownRenderer.buildAttributedString`'s table replacement logic; check the `cellSourceRangeKey` attribute is being applied.
- **F1 line numbers misaligned** — `LineNumberRulerView.drawHashMarksAndLabels` uses `cachedLineStarts` (logical source lines) and `lineFragmentRect(forGlyphAt:)` for y-anchor. Source-line-N mapping won't match storage-line-N for tables (each cell is a separate paragraph in storage). Acceptable for D17; future work could anchor line numbers to source paragraphs not storage paragraphs.
- **H2 cell detection fails** — `recordClickForDebugProbe` reads `paragraphStyle.textBlocks` at the resolved char index. If the click falls on a paragraph terminator or just outside a cell, it correctly reports `para`.

---

## What's deferred (NOT in this test plan)

- Active-cell visual border (Numbers/Excel-style focus indicator).
- Modal popout for long-form cell editing.
- Source-reveal mode (D8.1).
- Performance benchmarking (large docs).
- Multi-table Tab cycling (Tab past end of one table → first cell of next).
