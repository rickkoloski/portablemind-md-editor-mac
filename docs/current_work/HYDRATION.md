# Session Hydration — md-editor-mac (post-D12)

**Last updated:** 2026-04-25 end of D12 session
**Purpose:** Get a fresh Claude Code session productive in this codebase fast. Read this in full before doing anything substantive. Combine with `~/.claude/projects/.../memory/MEMORY.md` (auto-loaded) for the full picture.

---

## TL;DR — what just shipped

**D12: Per-cell table editing.** GFM tables now support Word/Docs-style single-click cell editing in the production app. Spike validated the architecture across 7 tiers; production merge applied the findings to `Sources/Editor/Renderer/Tables/`. D8.1's auto-reveal-on-caret-in-table is retired; reveal is now an explicit double-click trigger.

**Commits on `main` (most recent first):**
- `ecdeee1` — D12 step 7: docs + roadmap + Harmoniq close
- `a220cd7` — D12 step 6: CT-glyph-advance per-character x mapping
- `1fdcf47` — D12 step 4: per-cell selection highlights
- `01294bd` — D12 steps 3+5: cell-nav + double-click reveal; D8.1 auto-reveal retired
- `f565f9a` — D12 step 2: install CellSelectionDataSource
- `e27bb0a` — D12 step 1: TableLayout.cellRanges
- `2af00c5` — production test harness (`#if DEBUG`)

D8.1's reveal **mechanism** (delegate's `revealedTables`, paragraph-style adjustments) is retained — D12 only changed the **trigger** (single-click → double-click).

---

## Project at a glance

**md-editor-mac** is a native macOS markdown editor — desktop surface for the PortableMind ecosystem. SwiftUI primary, AppKit (`NSTextView` + TextKit 2) for the editor surface, Swift Markdown + cmark-gfm for parsing.

Read these foundation docs before anything substantive:
- `CLAUDE.md` — project guidance, tech stack, conventions, SDLC commands.
- `docs/vision.md` — three principles. Word/Docs-familiar authoring, native-per-OS, markdown-now-structured-formats-later.
- `docs/engineering-standards_ref.md` — cross-deliverable rules. Note **§2.2: never access `.layoutManager` on `NSTextView`** (lazy-creates a TextKit 1 manager).
- `docs/roadmap_ref.md` — informal ordering, change log; D1–D12 complete, D3 deferred (Apple Developer Program), D7+ next.

SDLC framework lives at `~/src/ops/sdlc/`. md-editor uses the Native lifecycle. Each deliverable produces a triad — `specs/dNN_*_spec.md`, `planning/dNN_*_plan.md`, `prompts/dNN_*_prompt.md` — plus `stepwise_results/dNN_*_COMPLETE.md` and `testing/dNN_*_manual_test_plan.md`.

---

## How to build + run

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh                        # sets DEVELOPER_DIR
xcodegen generate                            # regenerates MdEditor.xcodeproj
xcodebuild -project MdEditor.xcodeproj \
           -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode \
           build
open .build-xcode/Build/Products/Debug/MdEditor.app
```

Open a markdown doc:
```bash
open "md-editor://open?path=$HOME/src/apps/md-editor-mac/docs/roadmap_ref.md"
```

Workflow notes:
- Always run `xcodegen generate` after adding/removing source files (`Sources/...`). The `.xcodeproj` is committed but rebuilt from `project.yml`.
- Logs: `/usr/bin/log show --predicate 'process == "MdEditor"' --last 30s`
- D6 dogfood CLI: `./scripts/md-editor <path>:<line>` (with optional `--line-numbers=on/off`).

---

## Production test harness — KEY for autonomous work

`Sources/Debug/HarnessCommandPoller.swift` and `Sources/Debug/HarnessActiveSink.swift` (both `#if DEBUG`-only) implement a file-based command poller that lets an external driver (you, the next CC session, a test script) inspect and drive the running app without depending on simulated input or the app being frontmost.

### What it can do

```bash
# Get screen coords of the focused window
echo '{"action":"window_info"}' > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.5
cat /tmp/mdeditor-window.json

# Dump editor state (source, selection, parsed tables)
echo '{"action":"dump_state"}' > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.5
jq . /tmp/mdeditor-state.json

# Snapshot the focused window
echo '{"action":"snapshot"}' > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.5
# read /tmp/mdeditor-shot.png via the Read tool

# Set selection
echo '{"action":"set_selection","location":540,"length":0}' > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.5

# Replace doc text (use python json.dumps for embedded newlines)
python3 -c 'import json; print(json.dumps({"action":"set_text","text":"new content\n"}))' > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.5
```

**Always `mv`-from-`.tmp`** — direct `>` writes race with the poller (it reads partial files and silently drops on JSON parse fail).

Synthetic input:
- `cliclick c:X,Y` — click at screen coords (top-left origin)
- `cliclick t:abc` — type chars
- `osascript -e 'tell application "System Events" to key code N'` — key events (123 left, 124 right, 125 down, 126 up, 48 tab, 51 backspace, 117 delete, 53 escape)

macOS Accessibility permission for osascript / cliclick is granted once per machine — persists.

### Discoverability

Every test-accommodation in production is marked with `// TEST-HARNESS:` for grep-discoverability:

```bash
grep -rn 'TEST-HARNESS:' Sources/
```

Strip the harness later by deleting the marked blocks if no longer wanted.

---

## D12 architectural findings (must-know for any table work)

These were validated in the spike (`spikes/d12_cell_caret/STATUS.md`) and apply to all future work touching the table renderer:

1. **`NSTextLineFragment.typographicBounds` is readonly.** You cannot synthesize a line fragment with arbitrary geometry. Customize caret routing via `NSTextSelectionDataSource`, not via line-fragment bounds.

2. **`lineFragmentRangeForPoint`'s `location` arg is the container anchor (offset 0), not the click position.** Use `tlm.textLayoutFragment(for: point)` to find the fragment hit by the click; read `rangeInElement.location` for the row.

3. **`enumerateCaretOffsetsInLineFragment` must yield offsets in strict left-to-right visual order.** Non-monotonic confuses NSTextView's hit-test.

4. **NSRange→NSTextRange off-by-one.** A cell content range `(loc, len)` represents N chars but N+1 caret positions. The NSTextRange returned must extend by `+1` on length so the caret can land at content-end.

5. **Empty cells need both zero-length ranges + caret snap.** `parseCellRanges` records empty cells; `LiveRenderTextView.snapCaretToCellContent` corrects clicks that the click-routing pushed past the empty cell.

6. **`storage.edited(.editedAttributes, range:, changeInLength: 0)` inside `beginEditing/endEditing` is required to evict cached fragments.** `invalidateLayout(for:)` alone keeps the cache. (D8.1 finding — D12 reuses.)

7. **Cell content has CT-driven character widths** for proportional fonts. Use `CTLineGetOffsetForStringIndex` (`TableLayout.charXOffset(rowIdx:colIdx:localOffset:)`) for accurate caret + highlight x positions.

---

## Production code layout (post-D12)

```
Sources/
├── App/MdEditorApp.swift                    Entry point. Hooks harness poller in onAppear.
├── Debug/                                   #if DEBUG-only test harness.
│   ├── HarnessActiveSink.swift              Singleton tracking active NSTextView.
│   └── HarnessCommandPoller.swift           File-based command poller (200ms tick).
├── Editor/
│   ├── EditorContainer.swift                NSViewRepresentable hosting NSTextView.
│   │                                        Installs TableLayoutManagerDelegate +
│   │                                        CellSelectionDataSource. Coordinator
│   │                                        retains both. revealRow() called by
│   │                                        text view's onDoubleClickRevealRequest.
│   ├── LiveRenderTextView.swift             NSTextView subclass.
│   │                                        Cell-aware mouseDown / keyDown /
│   │                                        deleteBackward / deleteForward.
│   │                                        snapCaretToCellContent post-click.
│   ├── LineNumberRulerView.swift            D10/D11.
│   └── Renderer/
│       ├── MarkdownRenderer.swift           swift-markdown walker → attributes.
│       │                                    visitTable populates cellRanges.
│       └── Tables/
│           ├── TableAttributeKeys.swift     rowAttachmentKey constant.
│           ├── TableLayout.swift            Per-table layout data. Has cellRanges,
│           │                                charXOffset, parseCellRanges helpers.
│           ├── TableLayoutManagerDelegate.swift  Returns TableRowFragment for tagged
│           │                                paragraphs. Has revealedTables set.
│           ├── TableRowFragment.swift       Custom NSTextLayoutFragment. Draws
│           │                                grid + per-cell selection highlights.
│           └── CellSelectionDataSource.swift  NEW. NSTextSelectionDataSource override
│                                            for cell-aware click + caret routing.
├── CommandSurface/                          D6.
├── Workspace/, WorkspaceUI/                 D6.
├── Mutations/                               D4 source-mutation primitives.
├── Toolbar/                                 D5.
├── Keyboard/                                D4.
├── Files/, Handoff/, Settings/, etc.
└── Support/                                 Typography, etc.
```

When adding source files, run `xcodegen generate` so the build picks them up.

---

## Spike — when in doubt, look here

`spikes/d12_cell_caret/` is a fully-validated reproducer of the D12 architecture. If you're working on table-related production changes and need to verify a behavior in isolation:

```bash
cd ~/src/apps/md-editor-mac/spikes/d12_cell_caret
./run.sh                        # builds + wraps as .app + launches
```

The spike has its own command poller at `/tmp/d12-command.json` (separate from production's `/tmp/mdeditor-command.json`). It supports more actions than production (e.g., `cell_screen_rects`).

`spikes/d12_cell_caret/STATUS.md` documents every tier validated, every finding made, and every implementation decision with rationale. Read this before re-deriving any table behavior — odds are the spike already answered the question.

---

## Manual test plans

`docs/current_work/testing/dNN_*_manual_test_plan.md` is a first-class SDLC artifact, one per deliverable. Pattern: setup, sections, numbered steps with expected results, failure pointers (specific code locations to check on regression), graduation-to-XCUITest section.

D12's plan: `docs/current_work/testing/d12_per_cell_table_editing_manual_test_plan.md`.

When you ship a new deliverable that touches user-visible behavior, add a manual test plan. Memory note: `feedback_manual_test_plans.md`.

---

## Conventions and feedback memories worth re-reading

These shape how I (CC) work in this codebase. All under `~/.claude/projects/-Users-richardkoloski-src/memory/`:

- `feedback_no_shortcuts_pre_users.md` — md-editor has no users yet; build the hard thing right, no compat shims.
- `feedback_manual_test_plans.md` — every deliverable gets a manual test plan, offered proactively.
- `md_editor_triad_vocabulary.md` — "triad" = spec + plan + prompt.
- `md_editor_d12_break_glass_fallback.md` — modal cell editor parked; do not surface unless CD opens it.
- `md_editor_d12_spike_session_2026-04-24.md` — full spike session context (extended).

CD direction history (Rick = CD):
- Single-click → cell editing was the **right** UX; D8.1's whole-table reveal on single-click was wrong (corrected mid-D8.1 review).
- "I'd prefer to do that work on something other than click tracking" — automation-first when iteration cost is high.
- "Markdown is truth" — typing pipes legitimately splits cells (do not block / auto-escape; let the source dictate the rendering).

---

## Where to go next

D12 is shipped. Remaining priorities from the roadmap:

1. **D7+ — PortableMind integration.** Now unblocked by D6's CommandSurface + workspace primitives. This is the next major front. Likely scope:
   - Connected mode (vs. standalone).
   - Submit / handoff primitive (commit author = human or agent).
   - Document ↔ entity association.
   - Tenant sign-in.
   - MCP adapter as a second caller of CommandSurface.
   - This is large; will likely need its own spec breakdown into D7.0, D7.1, etc.

2. **D3 — Packaging.** Deferred on Apple Developer Program enrollment (`memory/md_editor_apple_developer_state.md`). Not gated by code; gated by ID renewal.

3. **Polish for D12** (deferred during the merge, not blockers):
   - **Inline markdown formatting inside cells** (bold/italic/code/link). Currently cell content is plain text from GFM source substring. Needs cell-content rendering to walk the AST inside each cell.
   - **`CellRenderer` protocol** for pluggable cell renderers (per spec §4).
   - **Default selection-highlight bleed** across pipe characters — cosmetic; suppress NSTextView's default highlight in inter-row source.
   - **Pipe-typing UX policy** — currently allows pipe input → row gains a structural cell. Spec offered three options (allow / auto-escape / block); revisit if dogfood surfaces a use case.

4. **Other roadmap candidates** in `docs/roadmap_ref.md` "Candidates (unscheduled)" — outline panel, second document type (JSON/YAML), search, accessibility polish, Windows/Linux ports.

---

## What broke in this session and how it was fixed

For pattern-matching on similar problems:

- **Spike's CommandFilePoller race condition** — direct `> /tmp/d12-command.json` writes were read mid-flight by the 200ms poller, JSON parse fail, silent delete. Fix: atomic `mv` from `.tmp`. Production harness has the same constraint.

- **Multi-row click landed on row 0** — `lineFragmentRangeForPoint`'s `location` arg is container anchor, not click position. Fix: `tlm.textLayoutFragment(for: point)`.

- **Empty cell click escaped past content** — NSRange (loc, 0) → NSTextRange extended by +1 to (loc, loc+1). NSTextView picks offset loc+1 (outside the cell). Fix: `snapCaretToCellContent` post-click correction.

- **Production cells misaligned visually after the spike's tuning** — spike used hardcoded `cellYOffset=-7.5` etc. Production uses TableLayout's column geometry which is already correct (no hand-tuned offsets needed). The spike values DON'T transfer directly.

- **SourceKit "Cannot find type" false positives** — Swift errors in the editor often appear out-of-build-context. Trust `xcodebuild` output, not SourceKit live-checking, for real errors.

---

## Quick orientation for the next session

If you're a fresh CC, do this in order:

1. Read `~/.claude/projects/-Users-richardkoloski-src/memory/MEMORY.md` (loaded automatically).
2. Read this file (`docs/current_work/HYDRATION.md`) end to end.
3. Skim `docs/roadmap_ref.md` change log entries for the last 3 days.
4. If user mentions table or cell or D12 — read `docs/current_work/stepwise_results/d12_per_cell_table_editing_COMPLETE.md` + `spikes/d12_cell_caret/STATUS.md`.
5. If user mentions automation or testing — read this section's "Production test harness" above.
6. Build the app once to confirm your environment works (`xcodegen generate && xcodebuild ... build && open ...`).

Don't start substantive work until step 6 succeeds. The xcodegen step is required for any `Sources/` additions to be picked up by the build.
