# D30: Submit / Handoff (standalone-mode v1) — Complete

**Spec:** `docs/current_work/specs/d30_submit_handoff_spec.md`
**Plan:** `docs/current_work/planning/d30_submit_handoff_plan.md`
**Prompt:** `docs/current_work/prompts/d30_submit_handoff_prompt.md`
**Design thread:** `docs/current_work/planning/d30_submit_handoff_design_thread.md`
**Manual test plan:** `docs/current_work/testing/d30_submit_handoff_manual_test_plan.md`
**Asset:** `docs/integration/claude_md_addition.md`
**Branch:** `feature/d30-submit-handoff`
**Tag:** `v0.8` (first deliverable in the D3x agent-loop series)
**Completed:** 2026-05-11

---

## Summary

Ships **Submit** — `vision.md` Principle 1's named "durable differentiator" — in its standalone-mode realization. A Claude Code session opens a markdown doc with `--session=<id>` (auto-defaulted from `${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}`); the editor registers the session's interest on the tab; the user clicks **Submit** (or `⌘⏎`) to signal "your turn." md-editor saves the buffer first if dirty, then atomic-writes a JSON sidecar under `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/`. The waiting CC session's `fs.watch` on that dir fires, the agent re-reads the doc, and the loop continues.

v1 design constraints folded in over the design-thread + blocker pass:

- **Session-aware from v1** — multi-session is current dogfood reality (parallel CC sessions, each with disjoint doc sets). Session-blind was off the table.
- **1:1 cardinality** — the v1 UX caps interest at one session per tab; the data model carries an array as forward-compat insurance for a possible n:m UX, not as a near-term commitment.
- **Save-then-Submit** on dirty buffers (D14). Save failures (incl. D19 PM conflict-detection modal) block the sidecar.
- **NSAlert on sidecar write failure** (D16). User must know the sidecar didn't land.
- **Heartbeat with disable knobs** on both sides (D9). Default 60s CC-side cadence + 300s editor-side threshold; setting either to 0 or negative disables.
- **No persistence of interest across editor relaunch** (D15). Clean extension seam documented in plan §Phase 3 if dogfood ever needs reversal.
- **CLAUDE.md convention as a standalone asset** (D19) — `docs/integration/claude_md_addition.md` is copy-paste-shaped for any consumer's CLAUDE.md and ready for future distro-package inclusion.

---

## What was built

### New modules

| File | Purpose |
|---|---|
| `Sources/Handoff/SessionInterest.swift` | Struct + factory + FNV-1a deterministic color hash. |
| `Sources/Handoff/SubmitSidecar.swift` | `SubmitPayload` Codable (snake_case keys; explicit `encode(to:)` emits `"message": null` rather than omitting); `SubmitSidecar` enum (sidecar dir resolution, atomic write, `docID(forLocal:)`, `isStale(forSession:thresholdSec:)`). |
| `Sources/Handoff/SubmitDispatcher.swift` | `@MainActor` async-throws entry point. Save-then-Submit (D14); origin routing (D7); throws `DispatchError` on noInterest / saveBeforeSubmitFailed / sidecarWriteFailed. |
| `Sources/Handoff/HeartbeatPruner.swift` | `@MainActor` singleton; 300s Timer; UserDefaults `submitStalenessTimeoutSec` disable knob. |
| `Sources/Toolbar/SubmitToolbarButton.swift` | SwiftUI Menu (button-with-dropdown); reads focused doc + interest from `WorkspaceStore.shared`; ⌘⏎ shortcut on dropdown item; NSAlert on submit error. |
| `Sources/CommandSurface/ReleaseSessionInterestCommand.swift` | URL-scheme handler for `md-editor://release?session=X&path=...|&all=true`. |
| `UnitTests/SessionInterestTests.swift` | 6 tests (color stability + identity). |
| `UnitTests/SubmitSidecarTests.swift` | 16 tests (Codable round-trip; explicit-null emission; atomic-write invariant; docID stability + canonicalization; isStale across 4 scenarios). |
| `scripts/md-editor-heartbeat` | Bash helper; `MD_EDITOR_SESSION_ID` required, `MD_EDITOR_HEARTBEAT_INTERVAL_SEC` tunable, 0 disables. SIGINT/SIGTERM trap. |
| `docs/integration/claude_md_addition.md` | Self-contained asset — agent-side convention + operational setup + watch recipe + constants table. |
| `docs/current_work/specs/d30_submit_handoff_spec.md` | Spec. |
| `docs/current_work/planning/d30_submit_handoff_plan.md` | Plan. |
| `docs/current_work/planning/d30_submit_handoff_design_thread.md` | Design thread (resolved). |
| `docs/current_work/prompts/d30_submit_handoff_prompt.md` | CC briefing. |
| `docs/current_work/testing/d30_submit_handoff_manual_test_plan.md` | Manual test plan (18 TCs + cross-cutting harness recipe). |

### Modified

| File | Change |
|---|---|
| `Sources/Workspace/EditorDocument.swift` | `@Published private(set) var interestedSessions: [SessionInterest]` + 3 mutators (`setInterestedSession`, `removeInterestedSession`, `clearInterestedSessions`). |
| `Sources/Workspace/WorkspaceStore.swift` | `ReleaseScope` nested enum; `registerInterest(sessionID:on:label:)`, `releaseInterest(sessionID:scope:)`. |
| `Sources/CommandSurface/ExternalCommand.swift` | `.releaseSessionInterest = "release"` case. |
| `Sources/CommandSurface/OpenFileCommand.swift` | Parses `session` query param; calls `workspace.registerInterest(...)`. |
| `Sources/CommandSurface/CommandSurface.swift` | Registers `ReleaseSessionInterestCommand`. |
| `Sources/App/MdEditorApp.swift` | Starts `HeartbeatPruner.shared` in onAppear; places `SubmitToolbarButton()` in the toolbar group. |
| `Sources/WorkspaceUI/TabBarView.swift` | Informational session badge (8pt colored dot) before the dirty/read-only/saving group. |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | `toolbarSubmit`, `toolbarSubmitDropdownSubmit`, `tabSessionBadge(documentID:)`. |
| `Sources/Debug/HarnessCommandPoller.swift` | 5 new actions: `register_session_interest`, `release_session_interest`, `dump_session_interest`, `force_staleness_sweep`, `submit_focused`. |
| `scripts/md-editor` | `--session=`, `--release [<file>|--all]`, env-var defaulting chain. |
| `~/src/apps/md-editor-mac/CLAUDE.md` | Brief "Submit / Handoff agent convention" section pointing to the asset. |

---

## Phase commit log

| Phase | Commit | Notes |
|---|---|---|
| Triad | `a66f671` | spec + plan + prompt + design thread. |
| 1 (substrate) | `ba8fb86` | SessionInterest + SubmitSidecar + EditorDocument field; 18 unit tests. |
| 2 (CLI + URL) | `644c832` | Shim flags, URL scheme verbs, OpenFileCommand session-param parsing, WorkspaceStore stubs. |
| 3 (lifecycle + harness) | `7d7d453` | EditorDocument mutators, WorkspaceStore real lifecycle, 3 harness actions. |
| 4 (heartbeat) | `9e2b571` | HeartbeatPruner + helper script + force_staleness_sweep harness action; 4 more unit tests. |
| 5 (UI + dispatcher) | `cb39b63` | SubmitDispatcher (save-then-submit + NSAlert path), SubmitToolbarButton, tab badge, submit_focused harness action. |
| 6 (asset) | `12dd294` | claude_md_addition.md asset + CLAUDE.md pointer. |
| 7 (close-out) | _this commit_ | manual test plan + COMPLETE + roadmap update + tag v0.8. |

---

## Smoke evidence

**Scenario A end-to-end via harness, verified 2026-05-11:**

1. `./scripts/md-editor /tmp/d30-smoke.md --session=d30smoke` → tab opened; `d30smoke` registered; ISO8601 `registered_at` with millisecond precision.
2. `submit_focused` on a clean buffer → sidecar `1778551814889-77adeeea.json` at `~/Library/.../submits/d30smoke/`. Payload: `doc_origin=local`, `doc_id` = SHA-256 hex (matches short hash in filename), `submitter=Richard Koloski` (NSFullUserName), `message=null` (correctly emitted, not absent).
3. `insert_text "EDITED-PREFIX "` → buffer `dirty=true` → `submit_focused` → on-disk file gained the prefix BEFORE the sidecar landed; buffer transitioned to `dirty=false`. Save-then-Submit verified.
4. `--release` CLI removed the interest (count 1 → 0).
5. `register_session_interest` harness with label added it back.
6. Re-registering with a different session id replaced the prior interest (1:1 cap held; count stayed at 1).
7. `force_staleness_sweep` with no heartbeat writing → `interestCountBefore=1, interestCountAfter=0` (default 300s threshold honored).

Three sidecars accumulated from the three submits; all decoded cleanly. Cleanup removed the smoke session dir; PM-tab path verified by code review (deferred to Phase 7 manual-test TC-18 for a real PM tab on dogfood).

---

## Testing

- [x] **Build clean** through every phase. Only pre-existing Swift 6 strict-concurrency warnings (in `PortableMindConnector.swift` and `EditorContainer.swift` — unrelated to D30) remain.
- [x] **MdEditorUnitTests:** 45/45 GREEN. New surface: 18 tests in Phase 1 + 4 staleness tests in Phase 4 = 22 D30 unit tests on top of the pre-existing 23.
- [x] **Harness-driven Scenario A** end-to-end: open with session → submit (clean) → submit (dirty, save-then-submit) → release → re-register → 1:1 cap → force sweep. Recipe in manual test plan §"Cross-cutting harness recipe".
- [x] **D17 + D19 + D23 manual test plans:** unaffected (D30 is additive only; no existing-surface refactor).
- [ ] **PM-tab origin routing (TC-18):** code-review-only in this commit. Confirm on next PM dogfood session.
- [ ] **Sidecar write failure NSAlert (TC-9):** code-review-only — requires forcing a write failure that's awkward to provoke organically. Documented in manual test plan as low-priority follow-up.

---

## Deviations from spec / plan

### 1. `JSONEncoder` omits nil optionals by default — required explicit `encode(to:)`

`SubmitPayload`'s default Codable conformance would have omitted the `message` key entirely when nil. The spec wire-format wants `"message": null` so v1.1's Submit-with-message UI doesn't break the contract for consumers. Caught by `testMessageNullEncodesCorrectly` in Phase 1; fixed with an explicit `encode(to:)` that calls `encodeNil(forKey: .message)` when the value is nil.

### 2. `insert_text` over `set_text` for harness-driven dirty buffer

The plan's testing strategy implied `set_text` could dirty a buffer. In practice the harness's `set_text` mutates `NSTextView.string` directly, bypassing the text-edited delegate chain that propagates to `EditorDocument.source` / `lastSavedSource`. The fix in the manual test plan: use `insert_text` (which calls `tv.insertText(_:replacementRange:)` — the proper input path). Phase 5 smoke verified this works.

### 3. SwiftUI inline-closure `.help({...}())` triggered SourceKit type-check timeout

First draft of the tab badge passed the help text via an inline `({...}())` IIFE. SourceKit's slow type-checker bailed with "compiler is unable to type-check this expression." Production swiftc compiled fine, but refactored to a local `let badgeHelp` for compiler ergonomics.

### 4. PM-tab smoke deferred to next PM dogfood session

The plan's Scenario A walk-through was Local-only; the PM origin-routing path (TC-18) was code-reviewed only in this commit because the smoke was driven in a Local-only scratch directory. Risk-rated low: `SubmitDispatcher.makePayload` reads `EditorDocument.origin` deterministically.

---

## Follow-up items

Tracked from the spec's "Out of scope (deferred)" list:

| Item | Sequencing |
|---|---|
| **Submit-with-message UI** | v1.1; wire format already reserves `message: String?`. |
| **Multi-session per tab (n:m)** | Far future; data model accommodates. Trigger: dogfood surfaces a real shared-doc-cross-sessions case. |
| **Manual-open "Wait for session…" affordance** | v1.1; slot reserved in toolbar dropdown. |
| **Connected-mode Submit** (PM `StatusApplication` transition) | Pairs with D20 connection-management. Per `portablemind-positioning.md` Q3, the standalone→connected upgrade path is itself an open design question. |
| **"Send prompt back…"** affordance | v1.1+ toolbar-dropdown slot. |
| **Submit history UI** in the editor | Deferred; sidecars are the durable record. |
| **Settings UI** for `heartbeatIntervalSec` / `submitStalenessTimeoutSec` | UserDefaults-only in v1. |
| **Interest persistence across editor relaunch** (D15) | Don't-persist locked for v1; extension seam documented in plan §Phase 3 if revisited. |
| **TC-18 PM-tab smoke** | Run on next PM dogfood session. |
| **TC-9 forced-failure NSAlert smoke** | Optional; cost > value unless a real failure mode surfaces. |
| **`signpost`-instrumented Submit latency profile** | Same backlog item as D24's perf instrumentation. |

---

## Notes

- **Submit is the durable differentiator.** v1 surface is conservative on purpose; the toolbar dropdown's chevron is always present (even with only "Submit" inside) so v1.1+ extension slots ("Submit with message…", "Send prompt back…", "Release session…", "Wait for session…") land discoverable.
- **The CLAUDE.md asset is a deliverable.** Without it, receiving agents don't know to re-read on Submit. `docs/integration/claude_md_addition.md` is structured for copy-paste into any consumer's CLAUDE.md; a future distro package will bundle it as a help/startup-hint surface.
- **Heartbeat is opt-out, not opt-in.** Default-on with a knob respects the realized-usage constraint (multi-session ⇒ cleanup matters) without forcing it on lightweight single-session usage.
- **No backend changes.** v1 is on-disk only; PM API connected-mode is deferred to the D20-era follow-up.
- **Recurring memory-store correction:** parallel CC sessions hold **disjoint** doc sets (each session ↔ its own files), NOT shared docs. `memory/feedback_parallel_sessions_disjoint_docs.md` captures this for future reference. The 1:1 cap reflects current usage, not a stopgap.
