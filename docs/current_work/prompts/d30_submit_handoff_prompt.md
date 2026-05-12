# D30 Prompt — Submit / Handoff (standalone-mode v1)

You are working on `~/src/apps/md-editor-mac` on branch `feature/d30-submit-handoff` (cut from `main` at the start of Phase 1). Your job is to ship the **Submit** verb — `vision.md` Principle 1's named "durable differentiator" — in its standalone-mode realization: a session-aware, sidecar-on-disk handoff signal that closes the human↔agent feedback loop without requiring PortableMind connectivity.

This is the first deliverable in the **D3x "agent loop"** series. The D2x series stays the file-management branch.

---

## Read first (in this order)

1. **`docs/current_work/specs/d30_submit_handoff_spec.md`** — the contract. Decision log (D1–D13) is up front; acceptance criteria are the v1 DOD.
2. **`docs/current_work/planning/d30_submit_handoff_plan.md`** — the seven-phase plan with file-by-file touchpoints, DOD per phase, commit messages.
3. **`docs/current_work/planning/d30_submit_handoff_design_thread.md`** — Rick's annotated design thread; the resolutions that became D1–D13.
4. **`docs/vision.md` Principle 1** — the "Submit is an explicit verb that says 'your turn'" language that motivates the whole deliverable.
5. **`docs/portablemind-positioning.md`** — the standalone↔connected mapping; v1 ships standalone-only, but understanding the connected-mode upgrade path informs the wire format.
6. **`Sources/Handoff/README.md`** — the D2-reserved stub directory you're populating.
7. **`Sources/Workspace/EditorDocument.swift`** — the origin abstraction (.local | .portableMind) that Submit's dispatcher mirrors. Read D19's save-routing pattern as the template.
8. **`Sources/CommandSurface/*.swift`** — the URL-scheme + CLI plumbing chain. `OpenFileCommand`, `URLSchemeHandler`, `CommandSurface`, `ExternalCommand` are all touched.
9. **`scripts/md-editor`** — the CLI shim you'll extend with `--session=` and `--release`.
10. **`Sources/Toolbar/`** — the existing toolbar pattern (`ToolbarAction`, `ToolbarButton`, `HeadingToolbarMenu`). Your `SubmitToolbarButton` follows the same SwiftUI/Menu shape but reads tab state from `WorkspaceStore` rather than the `EditorDispatcherRegistry`.
11. **`docs/engineering-standards_ref.md`** — `accessibilityIdentifier` on every new view (§2.1); branch discipline (§3.1).
12. **`memory/feedback_design_against_realized_usage.md`** — the constraint that locked v1 as session-aware (not session-blind).
13. **`memory/feedback_terminal_colors.md`** — the convention that motivates short-slug session IDs.
14. **`memory/feedback_no_shortcuts_pre_users.md`** — md-editor is pre-users; build the hard thing right; no compat fallbacks.

---

## Conventions to follow

- **Triad before code.** Spec/plan/prompt are already written. Don't re-derive design decisions; if you find the spec ambiguous on something operational, ask before coding.
- **Branch per deliverable.** `feature/d30-submit-handoff` off `main`. All commits land on the branch; ff-merge to main after DOD is green (matches D23/D25 precedent).
- **Phase commit discipline.** One commit per phase, message format `D30 phase N — <short title>`. The plan specifies the message verbatim.
- **Build clean per phase.** `xcodebuild build` clean before each commit. If the build breaks mid-phase, fix before committing.
- **Harness smoke per phase.** Every phase has a DOD that includes at least one harness recipe. Run it; don't trust the build alone.
- **`accessibilityIdentifier` on every new view.** Per engineering-standards §2.1. New ids go in `Sources/Accessibility/AccessibilityIdentifiers.swift`.
- **`// TEST-HARNESS:` markers** on production code that exists for testability (per `docs/current_work/HYDRATION.md` § Production test harness).
- **No emojis** in code or comments (matches project convention).
- **No trailing summaries** in commit messages or COMPLETE doc unless they add information. Match D23/D25 voice.
- **Default to no comments.** Code should be self-explanatory; comments only when WHY is non-obvious (per global CLAUDE.md guidance).

---

## Phase guidance (compressed; full detail in the plan)

### Phase 0 — Branch + skeleton

`git checkout -b feature/d30-submit-handoff main`. `xcodebuild build` clean. No commit.

### Phase 1 — Substrate

Three new files in `Sources/Handoff/`: `SessionInterest.swift`, `SubmitSidecar.swift`. Add `interestedSessions: [SessionInterest]` to `EditorDocument`. Two new unit-test files. Build the atomic-write invariant tests; don't skip — concurrent fs.watch consumers are the v1 dogfood pattern.

Commit: `D30 phase 1 — Handoff substrate (sidecar writer + SessionInterest)`.

### Phase 2 — CLI + URL plumbing

Extend the shim. Add `--session=…`, the env-var default chain `${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}`, and the new `--release` action. URL scheme gets a `release` verb. `OpenFileCommand` gets `sessionID: String?`. `WorkspaceStore.releaseInterest(...)` is a stub in this phase; full lifecycle lands in Phase 3.

Commit: `D30 phase 2 — CLI + URL scheme session plumbing`.

### Phase 3 — Lifecycle + harness

Wire `OpenFileCommand.sessionID` → `EditorDocument.setInterestedSession(...)`. `WorkspaceStore.releaseInterest(...)` becomes real. Three harness actions: `register_session_interest`, `release_session_interest`, `dump_session_interest`. `submit_focused` is a stub returning "not implemented" until Phase 5.

Verify 1:1 cap: opening a file twice with different `--session=X` values replaces the prior interest.

Commit: `D30 phase 3 — interest lifecycle + harness register/release/dump`.

### Phase 4 — Heartbeat

`HeartbeatPruner` runs on a 5-minute Timer (`@MainActor`). `force_staleness_sweep` harness action drives it on demand. `scripts/md-editor-heartbeat` is a small bash loop; honors `MD_EDITOR_HEARTBEAT_INTERVAL_SEC` (≤0 disables). `submitStalenessTimeoutSec` in UserDefaults; default 300, ≤0 disables editor-side sweep.

Verify the disable knob both ways — CC-side and editor-side — works.

Commit: `D30 phase 4 — heartbeat writer + editor-side staleness pruning`.

### Phase 5 — Toolbar Submit + dispatcher + tab badge

This is the big phase. `SubmitDispatcher` is `@MainActor`, `async throws`, reads `EditorDocument.origin` for routing, writes the sidecar. `SubmitToolbarButton` is a `Menu` (button-with-dropdown shape), reads focused doc + interest set from `WorkspaceStore`, `.disabled(focusedInterestSet.isEmpty)`, `.keyboardShortcut(.return, modifiers: .command)`.

**Save-then-Submit (D14).** Dispatcher's first step: if `document.isDirty`, `try await document.save()` first. If save fails (incl. D19's PM conflict-detection modal returning cancel/error), rethrow without writing the sidecar. The user resolves and re-clicks. Don't write a sidecar with stale on-disk content under a dirty buffer.

**`doc_id` for Local (D17):** SHA-256 hex of `URL.standardizedFileURL.path` at submit time. `submitter` (D18): `NSFullUserName()`.

**Write-failure surface (D16):** dispatcher throws on sidecar write failure; `SubmitToolbarButton`'s submit handler catches and presents `NSAlert(messageText: "Could not record submission", informativeText: error.localizedDescription, style: .warning)`. Matches D14/D23.1 destructive-confirmation pattern.

**SwiftUI gotcha from D25:** when placing tooltips (`.help(...)`) on custom-content Buttons, put `.help()` *inside* the Button label, not on the outer Button. Same convention here for the tab badge tooltip.

Tab badge: small colored dot beside the dirty-dot, color from `interestedSessions.first?.color`. Hover tooltip via `.help` inside the Button label.

Wire `submit_focused` harness action to the dispatcher.

Verify Scenario A end-to-end: open file with `--session=cc1`, click Submit (or `⌘⏎` or `submit_focused` harness action), check the sidecar lands at the expected path with the right payload. Also verify the dirty-buffer path: edit-then-submit produces a saved+submitted state in one click.

Commit: `D30 phase 5 — toolbar Submit button + dispatcher + tab badge`.

### Phase 6 — Agent convention asset (D19)

**Per Rick's design-thread annotation on §8:** the convention is **a standalone asset file**, not a CLAUDE.md inline addition.

Create `docs/integration/claude_md_addition.md` as a self-contained asset. It must be readable in isolation (no required cross-reads) and copy-pasteable verbatim into a downstream consumer's CLAUDE.md. Contains: (1) what Submit means in this codebase; (2) the agent convention — re-read on Submit, alert on substantial conflict; (3) literal sidecar path constant `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/`; (4) the heartbeat one-liner (`MD_EDITOR_SESSION_ID=cc1 ./scripts/md-editor-heartbeat &` startup; `kill %1` exit; `MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0` disables); (5) a one-line note that the asset is structured for future distro-package inclusion (help file / startup hint).

The project's `~/src/apps/md-editor-mac/CLAUDE.md` gets only a brief pointer section (≤5 lines) referencing the asset — no duplication.

Phrase the asset's convention in the agent's voice ("When you receive a Submit event for a doc you authored…") so it works dropped into any CC session's CLAUDE.md.

Commit: `D30 phase 6 — agent convention asset + CLAUDE.md pointer`.

### Phase 7 — Close-out

Manual test plan walks every spec acceptance criterion. COMPLETE doc matches the D23/D25 shape. Roadmap row + change-log entry. ff-merge to main. Tag `v0.8`.

Commit: `D30 phase 7 — close-out: manual test plan, COMPLETE, roadmap, tag v0.8`.

---

## Things to ASK before deciding

- **CC-side heartbeat helper location.** The plan puts it at `scripts/md-editor-heartbeat`. If you discover a reason to land it elsewhere (e.g., as a hook in the global `~/src/ops/` substrate), ask first — it's project-boundary-crossing.
- **Tab badge size + position.** The spec says "small colored dot beside the dirty-dot." Pixel-perfect placement is a judgment call — if your first attempt looks crowded in the live editor, take a screenshot, ask Rick.
- **`paperplane.fill` SF Symbol for Submit.** The plan suggests it. If `paperplane` (unfilled) looks better in the toolbar context, ask. Default to `paperplane.fill`.
- **`v0.8` tag.** Per the plan, but if any in-flight finding shifts the version semantics, surface it.

## Things to DECIDE without asking

- Variable names, function names, file structure inside `Sources/Handoff/`.
- Specific UserDefaults key names (`submitStalenessTimeoutSec` is the plan's suggestion; rename if a clearer one fits the existing UserDefaults naming convention you observe in `Sources/Settings/`).
- Internal-only Swift access levels.
- Where to put new `accessibilityIdentifier`s in the registry.
- Specific error-type shapes inside `Sources/Handoff/`.
- Whether to add a new `_index.md` entry to `Sources/Handoff/` (you're allowed to write a brief one if helpful for the next reader).

## Things to AVOID

- **Don't add a per-message dialog UI.** Submit-with-message is v1.1; the payload field is null in v1.
- **Don't add multi-session-per-doc UX.** Today's dogfood pattern is N parallel sessions × N disjoint doc sets, so session↔doc is naturally 1:1. The data model carries an array as forward-compat insurance only — don't surface it.
- **Don't write content hashes onto sidecars.** Per D10, agent re-reads on Submit.
- **Don't touch the existing toolbar's command-dispatch path** (`EditorDispatcherRegistry`). Submit reads from `WorkspaceStore.focusedDocument` directly — different routing, intentionally.
- **Don't ship the connected-mode Submit** (PM status transition). Even if you discover it's easy, defer.
- **Don't add adjacent-to-doc sidecars** (`<doc>.submit.json` next to the .md). Per D5, sidecars are central-only.

---

## When in doubt

Re-read the spec's decision log (D1-D13). Each decision has a rationale; if your situation calls one into question, that's a signal to ask — not to second-guess.

The design thread (`docs/current_work/planning/d30_submit_handoff_design_thread.md`) preserves the conversation that produced the decisions. If a decision feels arbitrary, the thread will probably show why it isn't.

---

## What "done" looks like

- Branch `feature/d30-submit-handoff` ff-merged to main.
- Tag `v0.8` at the merge commit.
- All 7 phases committed with the plan-specified commit messages.
- Roadmap updated, change-log appended.
- Manual test plan covers every acceptance criterion.
- COMPLETE doc cross-references spec + plan + design thread + the 7 phase commits.
- Live editor smoke run of Scenario A end-to-end: open with `--session=cc1`, Submit, sidecar lands.

Ship it.
