# D17 Spec — Migrate Editor to TextKit 1

**Type:** Foundational migration (architectural)
**Created:** 2026-04-26
**Predicate:** D16 spike GREEN. See `spikes/d16_textkit1_tables/STATUS.md`.
**Outcome:** Production main editor renders, edits, and lays out text using `NSLayoutManager` (TextKit 1). All TextKit 2-specific code (custom `NSTextLayoutFragment`, `NSTextLayoutManagerDelegate`, scroll-suppression workarounds) is removed.

---

## 1. Why this exists

D8 → D15.1 attempted to ship table rendering and per-cell editing on TextKit 2's custom-fragment system. Each round of bug-fixing surfaced another way TK2's lazy layout and custom-fragment-frame model interact badly with scroll. D15.1 closed every harness-reproducible scenario, but real-user dogfooding still produced visual bugs (post-scroll table corruption, blank surroundings, click-to-stale-position).

D16 spike validated the alternative: TextKit 1 with native `NSTextTable` / `NSTextTableBlock` handles all four canonical scenarios that defeated TK2 — render below initial viewport, click-to-caret, type-without-jump, wrapped-cell click — using stock `NSLayoutManager` APIs and zero custom-layout code.

CD direction (2026-04-26): "it's a poor choice to fight a technology 99% of the time." The decision is to switch the main editor to TK1.

---

## 2. The "why not mix?" question — closed

Apple at WWDC22 ("What's new in TextKit and text views", session 10090):

> "There can be only one layout manager per text view. A text view can't have both an `NSTextLayoutManager` and an `NSLayoutManager` at the same time."
>
> "Once a text view switches to TextKit 1, there's no automatic way of going back. It's a one-way operation."

Implications:
- **Within a single NSTextView**: mixing is impossible.
- **Across views in an app**: technically possible — each NSTextView is independently configured — but no public production precedent for deliberate mix and no value for our use case.
- **TextEdit's "switch on table insert"**: an automatic per-document compatibility-mode fallback Apple acknowledges at WWDC22. Not a designed pattern; relies on TK2 silently demoting itself when it encounters unsupported attributes. Not something we copy.

Community consensus (2024–2025) is consistent with this: third-party text view authors (STTextView, AltStore's editor, etc.) commit to one engine. Marcin Krzyżanowski (STTextView author) wrote in *TextKit 2: The Promised Land* (Aug 2025): "TextKit 2 is not yet ready for editing documents," calling out NSTextTable specifically as unsupported.

**Decision**: switch the main editor view entirely to TK1. No per-view split, no per-document fallback. Single editor surface, single engine.

---

## 3. Scope

### 3.1 What changes

The main editor's text view is constructed with an explicit TK1 chain:

```swift
let storage = NSTextStorage()
let layoutManager = NSLayoutManager()
storage.addLayoutManager(layoutManager)
let container = NSTextContainer(size: ...)
container.widthTracksTextView = true
layoutManager.addTextContainer(container)
let textView = NSTextView(frame: ..., textContainer: container)
```

Or equivalently `NSTextView(usesTextLayoutManager: false)` (macOS 13+ initializer that opts out of TK2). The two are equivalent for our purposes; the explicit chain is preferred because it documents intent in the code path.

The markdown renderer's output for tables changes from "TK2 fragment metadata via TableRowAttachment" to "an attributed string with per-cell `NSParagraphStyle.textBlocks` containing `NSTextTableBlock` instances pointing at a shared `NSTextTable`."

### 3.2 What's retired

Source code that goes:

| File | Reason |
|---|---|
| `Sources/Editor/Renderer/Tables/TableRowFragment.swift` | Custom NSTextLayoutFragment subclass — only existed because TK2 doesn't render tables natively. |
| `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift` | Returned the custom fragment for table paragraphs. TK1 doesn't need a delegate to render tables. |
| `Sources/Editor/Renderer/Tables/TableLayout.swift` | Cell width / height / column-leading-X computation moves into the TK1 attributed-string builder; the standalone class disappears. |
| `Sources/Editor/Renderer/Tables/CellEditOverlay.swift` | Overlay existed because TK2 couldn't edit wrapped cells in place. TK1 can. Retire. |
| `Sources/Editor/Renderer/Tables/CellEditController.swift` | Controller for the overlay above. Retires with it. |
| `Sources/Editor/Renderer/Tables/CellEditModalController.swift` | Modal popout was a workaround for cells the overlay couldn't handle. With TK1, cell editing is in-place; the modal becomes a separate question (revisit per § 5). |
| `Sources/Editor/Renderer/Tables/CellSelectionDataSource.swift` (if present) | Custom hit-testing replaced by `lm.glyphIndex(for:)`. |
| `LiveRenderTextView.scrollSuppressionDepth` and `scrollRangeToVisible` override | Workaround for TK2's auto-scroll-on-edit. TK1 doesn't need it. |
| `LiveRenderTextView.mouseDown`'s `tlm.ensureLayout(for: tcm.documentRange)` call | TK2-only fix for stale lazy-layout fragments. TK1's layout is consistent without it. |
| `EditorContainer.renderCurrentText`'s post-render `tlm.ensureLayout(...)` | Same. |
| `EditorContainer.renderCurrentText`'s scrollY save+restore (D15 origin) | Same. |
| `Sources/Editor/LiveRenderTextView`'s `cellEditController` / `cellEditModalController` weak properties | Wires to retired controllers. |

### 3.3 What's preserved

| Subsystem | Why it survives |
|---|---|
| Workspace shell — `Sources/Workspace/*`, `Sources/WorkspaceUI/*` | Folder tree, tabs, document model: independent of text engine. |
| Save / Save As — `Sources/Workspace/EditorDocument.swift` | D14 atomic write + watcher pause. Independent of text engine. |
| Scroll-to-line — D9 reveal pathway | `textView.scrollRangeToVisible(_:)` works in TK1; the API is the same. |
| Line numbers — `Sources/Editor/LineNumberRulerView.swift` | NSRulerView attaches to NSScrollView regardless of which layout manager the doc view uses. The fragment-iteration call (`enumerateTextLayoutFragments`) does need to change to TK1's `NSLayoutManager.enumerateLineFragments(forGlyphRange:using:)`. **Touch lightly.** |
| CLI flags — `Sources/CommandSurface/*`, view-state plumbing | Independent. |
| Command dispatcher — `Sources/Keyboard/*` | Independent. |
| File watcher — `Sources/Files/ExternalEditWatcher.swift` | Independent. |
| Toolbar, formatting buttons | Independent. |
| Debug HUD (`Sources/Debug/DebugProbe.swift`) | Mostly independent. The fragment-class field needs to learn TK1's `NSTextLineFragment` type names; the rest is identical. |
| Harness — `Sources/Debug/HarnessCommandPoller.swift` | Most actions survive as-is. Fragment-shaped actions (`inspect_table_layout`, `inspect_overlay`, `simulate_click_at_table_cell`) need to be re-implemented against TK1 (cell ranges, glyph-index hit testing) — roughly the same shape, different internal calls. |
| Tests — `tests/harness/` | Same spec, refactored implementation. |

### 3.4 What gets re-evaluated

| Subsystem | Question |
|---|---|
| D8.1 source-reveal mode | Was a TK2 affordance for showing table source via fragment-swapping. TK1 doesn't have the same fragment system. Decide: re-implement (toggle the table's paragraph-style.textBlocks to nil and back?), drop entirely (cell edit is in-place now, less need to fall back to source), or rebuild differently. **Default: drop unless CD asks otherwise.** |
| D12 cell-Tab navigation | TK2 implementation read fragment metadata to find next-cell ranges. TK1 has no fragment metadata for tables, but cell ranges are knowable from the attributed string's paragraph-style/textBlocks. Probably 30 lines of code; revisit during phase 6. |
| D13 active-cell border affordance (Numbers-style) | Was draw-only on top of D13's overlay. Now no overlay. Could redraw a border on top of the focused cell using ruler-like custom drawing. **Defer to a separate follow-up deliverable** — not migration-blocking. |
| D13 modal popout | Was an escape hatch when the overlay couldn't handle the cell content. With in-place editing, primary motivation is gone. Could keep as a "long-form edit" affordance, e.g., for cells holding pasted long-form prose. **Defer** until we know whether users miss it. |
| Column-width auto-sizing | TK1's `NSTextTableBlock.setContentWidth(_, type: .absoluteValueType, for: .padding)` configures fixed widths. Markdown tables don't carry width hints, so the renderer has to choose widths (probably "max content width per column up to a cap"). Already implemented in our TableLayout class; port the logic. |

### 3.5 What's out of scope

- Switching ANY non-table content rendering. Headings, lists, blockquotes, inline formatting all stay on whatever paragraph-style attributes they already use. The migration is at the layout-manager level; per-paragraph attributes don't change.
- Changes to file format, save format, or markdown round-trip semantics. The serializer (attributed string → markdown source on save) is regenerated from the same parser AST; this migration changes the rendering pipeline, not the data model.
- New table features (resize columns, sort, etc.).
- Performance benchmarking. We accept TK1 as "fast enough" because Apple's own apps still use it.

---

## 4. Definition of done

1. `Sources/Editor/EditorContainer.swift` and `Sources/Editor/LiveRenderTextView.swift` build the text view with explicit TK1 init. Runtime assertion: `textView.textLayoutManager == nil` (we are NOT on TK2 by accident).
2. The markdown renderer emits attributed strings whose tables are real `NSTextTable` / `NSTextTableBlock` configurations. No `TableRowAttachment` references remain in production code.
3. Files in § 3.2 are deleted from `Sources/`. Project regenerates cleanly via `xcodegen`. App builds with no warnings about missing references.
4. Manual test plan executes GREEN (per § 6 below).
5. Existing harness tests (`tests/harness/test_d15_1_lazy_layout.sh`) are either re-implemented against TK1 OR explicitly retired with a note in `FINDINGS.md` explaining why their assertions don't translate.
6. `docs/stack-alternatives.md` updated: the "Text-editing engine" row now reads "TextKit 1 with `NSTextTable` for tables; deliberate switch from initial TK2 commitment after D16 spike." with a link to D16 STATUS.md.
7. `docs/engineering-standards_ref.md` § 2.2 updated: the prohibition on "never touch `NSTextView.layoutManager`" is replaced with the new TK1-explicit standard. Add: "we are now ON TK1; reach for `layoutManager` directly. Do not opt back into TK2 (`NSTextView(usesTextLayoutManager: true)` or `NSTextLayoutManager`-typed access) without raising a deliberate architecture decision."
8. `docs/current_work/stepwise_results/d17_textkit1_migration_COMPLETE.md` documents what shipped, what was deferred, and known gaps.

---

## 5. Open questions for CD before implementation — RESOLVED 2026-04-26

CD agreed with the recommendations on all four. Each becomes the decision; the implementer's behavior should match.

1. **D8.1 reveal mode** — keep, drop, or rebuild? My recommendation: drop. With in-place editing the original motivation is largely gone; re-implementing it is real work (toggle textBlocks to nil and back is conceptually easy but has selection-handling and undo-handling implications). The mechanism survives in `git log` if a future user asks for it.

rak: agreed

2. **D13 modal popout** — keep as a long-form-edit escape hatch, or drop? My recommendation: drop. Adds a code path that's now unused; brings back if dogfooding asks for it.

rak: agreed

3. **Active-cell border** — defer to a follow-up post-migration deliverable, OR include in D17 scope? My recommendation: defer. Visual polish; not migration-blocking.

rak: agreed

4. **Cell-aware Tab nav** — include in D17 scope, or follow-up? My recommendation: include — it's a small port and cell editing without Tab nav feels broken to anyone who's used Numbers/Excel.

rak: agreed

Net behaviors for the implementer:
- D8.1 source-reveal mode: **DROP**.
- D13 modal popout: **DROP**.
- Active-cell border: **DEFER** to D18+.
- Cell-aware Tab nav: **INCLUDE** in D17 (phase 6 of the plan).

---

## 6. Manual test plan (executed by CD post-merge)

A. **Doc lifecycle**
- A1. Open `docs/roadmap_ref.md`. Tables render correctly. Scroll up/down — no blank gaps, no stale rendering, no overlay artifacts.
- A2. Open `harmoniq-frontend/docs/00_CURRENT_WORK/planning/d09_task_conversations_files_plan.md` (multi-table, ~24k chars). Same expectations.
- A3. Switch tabs between roadmap and d09 multiple times. Each tab shows correct rendering immediately on focus.

B. **Click + caret**
- B1. Click in a cell mid-table. Caret lands inside cell text. Type — characters insert at the click point, no scroll jump.
- B2. Click in a wrapped cell on visual line 2+. Caret lands at the right offset within the cell.
- B3. Click outside the table (in a paragraph). Caret behaves normally.

C. **Scroll + click interleave** (the D15.1 bug class)
- C1. Open d09. Scroll to bottom. Click in a cell of a table that's now in view. Overlay/caret lands in that cell — not at a stale pre-scroll position.
- C2. Scroll back up. Click in a different cell of a different table. Same.
- C3. Repeat sequence: scroll, click, type, scroll, click. No drift.

D. **Save / load (D14 regression)**
- D1. Edit a cell. ⌘S. File on disk reflects the edit.
- D2. ⌘⇧S → save to a new path. New file at that path.
- D3. External `echo > file.md` → buffer reflects new content via NSFilePresenter.

E. **Line numbers / scroll-to-line / CLI flags (D9–D11 regressions)**
- E1. Toggle line numbers via View menu and ⌘⌥L.
- E2. `./scripts/md-editor file.md:42` opens with line 42 scrolled into view.
- E3. `./scripts/md-editor file.md --line-numbers=on` matches.

F. **Debug HUD (D15.1 instrument)**
- F1. ⌥⌘D toggles HUD. Readout shows TK1-shaped values: scrollY, click coords, fragment kind ("para" or table cell coords), char index. No NSTextLayoutFragment references in the readout.

G. **External edit watcher**
- G1. While the editor has the file open, `echo "external" > file.md`. Buffer reflects.

H. **No regressions in basic markdown rendering**
- H1. Headings, bold/italic, inline code, links, lists, blockquotes all render correctly. (These never depended on the table fragment system.)

---

## 7. Risk register

| Risk | Mitigation |
|---|---|
| `NSLayoutManager.enumerateLineFragments(...)` API differs enough from TK2's `enumerateTextLayoutFragments(...)` to break the line-number ruler | Phase 1 includes ruler porting before any table work. Validate via existing manual test plan E1. |
| Markdown serializer (attributed string → markdown source) needs to recognize TK1 table attributes when round-tripping | Out of scope per § 3.5 only IF we don't yet round-trip tables on save. Verify: current save path writes the raw markdown source string from the document model, not from the attributed string. (Confirm during phase 1.) |
| Some markdown content embeds `\n` inside cell content via escaped form. TK1's per-cell paragraph terminator is `\n`, so the renderer must escape user-facing newlines (or convert to `<br>`-equivalent in cell content) | D13's commit() already pipe-escapes; same logic applies. Document and re-use. |
| TK1 `NSTextTableBlock.ValueType.absoluteValueType` and similar enum names are deprecated-style but still work | Note in `engineering-standards_ref.md` as a known constraint; don't preemptively port to "modernized" alternatives that don't exist for TK1. |
| Switching causes a round of build-warning noise from TK1's "older-style" APIs | Accept; document warnings in `engineering-standards_ref.md` if they're widespread. Don't suppress wholesale. |
| Some TK2 code path is referenced from non-table places we forgot to grep | Phase 7 (regression sweep) does a `grep -r 'NSTextLayoutFragment\|NSTextLayoutManager\|TableRowAttachment'` across the codebase and confirms zero hits in `Sources/`. |

---

## 8. Trace to foundation docs

- `docs/vision.md` Principle 3 (markdown today, structured formats tomorrow): tables are a structured-content concern. Switching to a layout engine that natively handles them is on-mission.
- `docs/stack-alternatives.md`: the "Text-editing engine" row updates as part of D17's DOD. The "Architecture lessons to capture for Windows and Linux" section gets an entry: "macOS table rendering is best handled by the platform's tables-aware text layout engine; Windows/Linux equivalents need similar evaluation rather than reimplementing custom layout."
- `docs/engineering-standards_ref.md` § 2.2: the prohibition flips meaning (no longer "never touch layoutManager because it demotes you"; now "we are deliberately on TK1, layoutManager IS the path"). Update text accordingly.
- `docs/portablemind-positioning.md`: not affected.
- `docs/competitive-analysis.md`: not affected — the comparison was about UX, not framework choice.

---

## 9. Spike → production traceability

The D16 spike at `spikes/d16_textkit1_tables/` is the reference implementation for the table rendering pattern. The migration ports the same `NSTextTable` + `NSTextTableBlock` + `NSParagraphStyle` shape into the production renderer. Don't import code from the spike; the spike is illustrative, not a library. The spike stays in-tree as a regression artifact and a teaching example.
