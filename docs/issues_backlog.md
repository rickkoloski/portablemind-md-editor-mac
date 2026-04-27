# Issues backlog

Non-blocking issues discovered during work. Append as found; promote to a `docs/current_work/issues/dNN_*_BLOCKED.md` if an issue starts blocking an active deliverable.

This file exists so we can capture noise without losing focus. Each entry is its own H2 section — short and self-contained, greppable by ID (`grep -n '^## i' docs/issues_backlog.md`).

**Conventions:**
- IDs are `i01`, `i02`, … assigned in order of discovery (never reused).
- Status: `Open` | `Investigating` | `Workaround` | `Fixed` | `WontFix` | `Filed-Upstream`.
- Once `Fixed` or `WontFix`, leave the entry in place as a record; don't delete.

---

## i01 — Read tool reports "File unchanged" after editor saves user edits

**Date:** 2026-04-27
**Area:** tooling (Claude Code)
**Status:** Workaround

Claude Code's `Read` tool returned `"File unchanged since last read. The content from the earlier Read tool_result in this conversation is still current"` immediately after the user typed and saved edits in PM Markdown to the file CC had previously written. CC was misled into thinking the user's edits hadn't persisted; `grep` and `stat` via `Bash` confirmed the writes had landed on disk.

The Read cache is keyed on CC's prior reads in the conversation, not on the file's actual mtime — so external modifications between Reads aren't surfaced.

**Workaround:** when verifying a save round-trip from the editor (or any external writer), use `Bash` (`grep`, `stat`, `cat` via the appropriate tool) instead of `Read`. The cache is per-conversation; once CC reads the file fresh in a new context, the issue doesn't recur.

**Discovered during:** D18 spec authoring — first save-roundtrip from user-typed edits in PM Markdown.

**Possible upstream filing:** worth a Claude Code issue once we have a minimal repro. The behavior is also flagged by a `system-reminder` *before* the Read returns "unchanged," so the cache hint is contradicting the system signal.

---

## i02 — Markdown table column widths capped at 320pt regardless of viewport

**Date:** 2026-04-27
**Area:** editor (table rendering)
**Status:** Open

Tables with text-heavy columns (e.g. the Decision log table in `d18_pm_connector_directory_tree_spec.md`) wrap aggressively even when there's plenty of horizontal room in the editor window. CD noticed this on the D18 spec's Decision log: the "Decision" column reads narrow despite the window being wide.

**Root cause:** `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift` (lines 274–298) computes each column's content width as `max(natural-text-width across all cells, 60pt)` capped at a hard-coded `columnCap: CGFloat = 320`. The cap predates the D17 TK1 migration (carried forward from the D8 TK2 renderer's column-cap heuristic). It does not account for viewport width, total table width, or the relative information-density of the columns.

For the D18 Decision log, the "Decision" column's natural text width is many thousands of points, so it pins to 320pt and wraps. Two short columns (Date, Decided by) sit fully unfurled. Net: most of the window is whitespace while the meaty column is the cramped one.

**Possible fixes (in roughly increasing order of effort):**
1. Raise the cap (480pt, 640pt) — quick, but doesn't solve the underlying mismatch.
2. Viewport-aware cap — `min(columnCap, viewport.width - other-columns-natural-width - chrome)`.
3. Proportional layout — give each column its natural width when it fits; when total > viewport, distribute the deficit proportionally to each column's slack (max(0, naturalWidth - minWidth)). Mirrors what browsers do with `table-layout: auto`.
4. User-resizable columns — drag column boundaries; persist per-doc. Significant scope.

**Discovered during:** D18 spec authoring; CD reading the Decision log table in PM Markdown.

**Not blocking D18.** D18 is the PM connector + sidebar tree; no table rendering changes. File for later — likely a focused deliverable in the post-D19 window.

---

## i03 — UITest suite has 3 failures from before D18 work began

**Date:** 2026-04-27
**Area:** testing (XCUITest)
**Status:** Open

`xcodebuild test` reports 3 failing test cases on `main` (and on `feature/d18-pm-connector` — the failures predate the branch):

- `LaunchSmokeTests.testAppLaunchesAndMainEditorIsAccessible` — "main editor view not found by accessibility identifier"
- `MutationKeyboardTests.testBoldMutationWrapsSelection` — "main editor not reachable by identifier"
- `MutationToolbarTests.testBoldButtonWrapsSelection` — "main editor not reachable by identifier"

All three are looking for `md-editor.main-editor` accessibility identifier on launch, but the app at launch shows the empty-editor placeholder (no document open) — there's no main editor view to find. The tests likely worked when the launch UX always mounted an editor; the D6 workspace introduction added the empty-editor placeholder, which routes around the editor view.

**Verified pre-existing:** stashing the Phase 1 refactor and running tests on `main` reproduces the same three failures. Phase 1 does not introduce new regressions in this suite.

**Fix path (sketch):** the tests need a setup step that opens a folder and a file before asserting on the main editor view, OR a shadow accessibility identifier on the empty-editor placeholder so the test can assert the launch-state directly.

**Discovered during:** D18 phase 1 manual smoke (running the existing UITests as a regression sweep).

**Not blocking D18.** Phase 1 doesn't make these worse. Address as a focused testing deliverable separate from D18.