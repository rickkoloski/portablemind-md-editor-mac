# D30 — Submit / Handoff (standalone-mode v1)

**Status:** DRAFT — design questions resolved in the design thread; this spec is the contract.
**Branch:** `feature/d30-submit-handoff` (cut from `main` at start of Phase 1).
**Trace:**
- `docs/vision.md` Principle 1 — "Level 2 agent-aware. Bidirectional change detection plus an explicit **Submit** signal for handoff." This is the deliverable that lands Submit.
- `docs/stack-alternatives.md` §"Architecture lessons" #4 — "Submit / Handoff protocol… worth writing early."
- `docs/portablemind-positioning.md` — standalone-mode vs. connected-mode mapping; v1 ships standalone-mode only.
- `Sources/Handoff/README.md` — module-boundary stub reserved at D2.
- Design thread: `docs/current_work/planning/d30_submit_handoff_design_thread.md`.

**Position in roadmap:** D30 — first deliverable in the **D3x "agent loop"** series. D26-D29 reserved for the file-operations series.

---

## Why now

The editor has become Rick's daily-driver authoring surface and Claude Code's primary review-feedback surface. **Multiple parallel CC sessions** run concurrently, each driving its own distinct workflow loop against its own distinct set of docs. Today every "your turn" handoff inside any one of those loops goes through chat ("I've updated the doc, ready when you are"). Submit is the verb that replaces that ad-hoc handshake with an explicit, scriptable signal — the **durable differentiator** named in `vision.md` Principle 1. The session-aware design is what makes Submit work across N concurrent loops without crosstalk — not because sessions share docs (they don't), but because each session needs Submit events to land in its own watch path.

Standalone-mode (sidecar-on-disk) is the v1 realization. Connected-mode (PortableMind `StatusApplication` transitions) is deferred to a follow-up paired with D20-era connection-management work — per `portablemind-positioning.md` Q3, the standalone→connected upgrade path is itself an open design question.

---

## Scope

In scope (v1, standalone-mode):

| Surface | Behavior |
|---|---|
| **Session registration** | CLI flag `--session=X` (auto-defaulted from `MD_EDITOR_SESSION_ID` then `TERM_SESSION_ID`); URL scheme `&session=…`. Opening a doc registers an *interest* by the supplying session. v1 caps interest at 1 session per tab. |
| **Tab badge** | Small colored dot on tabs with a registered interest. Hover shows session id/label. Informational only — not clickable for Submit. |
| **Toolbar Submit button** | Button-with-dropdown on the editor toolbar. Acts on the currently focused tab. Enabled when the focused tab has a registered interest; disabled otherwise. Default keyboard shortcut `⌘⏎`. v1 dropdown content is just "Submit" (extension slots reserved for v1.1+). |
| **Sidecar emission** | On Submit, atomic-write a JSON file to `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/<unix-ms>-<doc-hash>.json` (per §3.1 payload). Origin-routed dispatch (Local + PM both write sidecars in v1). **Save-then-Submit** on a dirty tab — save runs first; sidecar emits only on save success (D14). Write failures surface as NSAlert (D16). |
| **Heartbeat** | CC-side `heartbeat.json` write convention; editor-side periodic prune sweep. Both ends have a disable knob (0 or negative). |
| **Interest release** | Explicit (`--release` CLI action; harness action; CC session-end hook) + implicit (tab close releases the doc's interest; staleness prune removes ghost interests). |
| **Harness actions** | `submit_focused`, `register_session_interest`, `release_session_interest`, `dump_session_interest` — DEBUG-only, for autonomous testing. |
| **Agent convention** | Standalone asset file at `docs/integration/claude_md_addition.md` instructing receiving agents to re-read the doc on Submit + alert on substantial conflict. The project's `~/src/apps/md-editor-mac/CLAUDE.md` references the asset by path. Asset is structured so a future distro package can ship it as a help file / startup hint (D19). |

Out of scope (v1; deferred to v1.1 or later):

- **Submit-with-message** — wire format reserves `message: String?` from v1 (always null in v1). UI lands in v1.1 via the toolbar dropdown.
- **Multi-session per tab (n:m)** — data model accommodates it (`[SessionInterest]`), but UX and CLI enforce 1:1 in v1.
- **Manual-open "Wait for session…" affordance** — toolbar dropdown reserves a slot; not implemented in v1.
- **Connected-mode Submit** (PM `StatusApplication` transition) — deferred to a follow-up paired with D20.
- **"Send prompt back…" affordance** (the toolbar dropdown's reserved free-text-to-agent slot) — v1.1+.
- **Submit history / log viewer** in the editor — sidecars are the durable record; no in-editor surface in v1.
- **Per-tab session label customization UI** — labels can be set via harness in v1; user-editable surface is v1.1+.
- **Cross-session visibility** — moot in practice (sessions hold disjoint doc sets; two sessions don't share a doc) and moot under the v1 1:1 cap besides.

---

## User scenarios

### Scenario A — Canonical dogfood loop (the common case)

1. CC session `cc1` writes a draft markdown doc to disk.
2. CC opens it in md-editor with `./scripts/md-editor draft.md` (the shim auto-injects `--session=cc1` from `MD_EDITOR_SESSION_ID`).
3. Editor opens the doc in a new tab and registers `cc1`'s interest. Tab shows a colored badge; toolbar Submit button is enabled (the focused tab is the just-opened draft).
4. Rick annotates the doc inline.
5. Rick clicks the toolbar Submit button (or hits `⌘⏎`).
6. Editor writes a sidecar to `~/Library/Application Support/ai.portablemind.md-editor/submits/cc1/<ts>-<hash>.json`.
7. CC's fs.watch on its sidecar dir fires; CC reads the sidecar, re-reads the doc from disk, and proceeds.

### Scenario B — Parallel sessions, same overall pattern

`cc1` and `cc2` each have their own doc open (different files, different tabs). Each tab shows its respective colored badge. Rick can submit either one independently; sidecars route to the correct session dir. No cross-session interference.

### Scenario C — Manual open

Rick double-clicks `notes.md` in Finder. Tab opens with no session_id, no badge, Submit button disabled. Rick edits and saves normally; the file watcher / save semantics from D14 apply. No Submit affordance.

### Scenario D — Tab close releases interest

CC's `cc1` registered interest in `draft.md`. Rick closes the tab without submitting. `cc1`'s interest is released (the tab's `EditorDocument` deallocates). Re-opening the same file later (without re-passing `--session=cc1`) opens it as a manual-open with no badge. The session's sidecar dir continues to exist (no implicit cleanup of the dir itself on tab close).

### Scenario E — Stale interest cleanup

CC's `cc1` crashes mid-session without releasing. Its sidecar dir is no longer being heartbeat'd. After `stalenessTimeoutSec` elapses (default 300s), the editor's periodic prune sweep removes `cc1`'s interest from any tab that still carries it. Submit affordance disappears on affected tabs.

### Scenario F — Heartbeat disabled

A user testing locally without the heartbeat overhead sets `heartbeatIntervalSec = 0` and `stalenessTimeoutSec = 0` (both disabled). Interest persists indefinitely; only explicit release or tab close removes it.

---

## Decision log

Cross-references to design thread sections (`docs/current_work/planning/d30_submit_handoff_design_thread.md`).

| # | Decision | Rationale | Source |
|---|---|---|---|
| D1 | **Session-aware from v1, no session-blind option.** | Multi-session is current dogfood reality; session-blind would underbuild against realized usage. | Design thread §0 + `memory/feedback_design_against_realized_usage.md` |
| D2 | **v1 UX cardinality = 1:1.** Data model carries `[SessionInterest]` so n:m doesn't change the wire/model. | Reflects current dogfood reality: parallel CC sessions hold disjoint doc sets, so the session↔doc relationship is naturally 1:1. n:m is far-future (and may never be a real pattern); the array is forward-compat insurance only, not a near-term roadmap commitment. | DT §2.1 + §2.9 |
| D3 | **Toolbar Submit button-with-dropdown.** Tab badge is informational only. | Toolbar buttons already act on focused tab; matches the user's mental model. Dropdown reserves extension slots. | DT §2.2 |
| D4 | **`⌘⏎` keyboard shortcut for Submit.** | Per `vision.md` Principle 1 language. No conflict with existing chords. | DT §2.2 |
| D5 | **Central per-session sidecar dir**, no adjacent-to-doc sidecars. | Stable known location for the agent's `fs.watch`; user shouldn't be hunting `.submit.json` files in their tree. | DT §2.3 + Q6 |
| D6 | **Submit payload includes `message: String?` from v1**, always null until v1.1. | Wire-format stability across the v1→v1.1 boundary. | DT §2.10 |
| D7 | **Origin-routed dispatch.** Both `.local` and `.portableMind` write sidecars in v1; PM connected-mode (status transition) deferred. | Pairs naturally with D20 connection-management; PM standalone-→connected upgrade is itself an open question. | DT §2.8 |
| D8 | **Tab close releases interest.** | Intuitive lifecycle — closing the doc means the session has nowhere to deliver to. | DT §2.7 |
| D9 | **Heartbeat with disable knob.** `heartbeatIntervalSec` (CC-side) and `stalenessTimeoutSec` (editor-side) both default to non-zero positive; 0 or negative disables. | Cleanup against stale interests without forcing all setups to pay the heartbeat cost. | DT §2.7 + Q3 |
| D10 | **Editor stays dumb on content-version conflicts.** No content hash on sidecars; agent re-reads on Submit and uses a CLAUDE.md convention to alert on substantial conflict. | Keeps the editor surface minimal; agent owns reasoning about content state. | DT §2.11 + Q7 |
| D11 | **Session ID is opaque to the editor**, shape determined by CLI shim. Default chain: `${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}`. Recommended convention: short slugs `cc1`/`cc2`/… set in shell init. | CC doesn't expose a canonical per-session env var; short slugs match the terminal-color mental model. | DT §2.12 + Q1 |
| D12 | **Manual-open "Wait for session…" affordance deferred to v1.1.** Slot reserved in toolbar dropdown. | Canonical dogfood pattern is CC-initiated (the open *is* the request); the manual-open path is rare. | DT §2.6 + Q5 |
| D13 | **D30 numbering.** D26-D29 reserved for file-operations follow-ups. | D2x stays the file-management branch; D3x opens the agent-loop branch. | DT §3 + Q8 |
| D14 | **Save-then-Submit** on a dirty tab. Submit triggers save first; sidecar emits only on save success. PM conflict-detection on save propagates via D19's existing modal. | "Your turn, look at the latest" — the latest must be on disk. Independent-Submit guarantees stale-content alerts on every dirty submit, training the user to ignore them; block-when-dirty adds a UX step. | DT §B1 |
| D15 | **Don't persist session interest across editor relaunch.** Tabs restore via `restorePersistedTabs`; their interest sets come back empty. CC re-registers via re-open or harness. | Editor relaunches are rare; persistence creates a stale-cleanup problem on the restoration side. Constraint: keep the persistence path a clean extension seam so v1.1+ can revisit cheaply (see Plan §Phase 3 extension-strategy callout). | DT §B2 |
| D16 | **NSAlert on sidecar write failure** with the underlying error message. Matches D14/D23.1 destructive-confirmation pattern. Condition-specific advanced functionality (retry UI, queue-and-retry, etc.) deferred. | User must know Submit didn't fire — otherwise they wait for an agent response that never arrives. Edge case in practice (Local writes to `Application Support` rarely fail); more likely with future remote backends. | DT §B3 |
| D17 | **`doc_id` for Local files = SHA-256 of `URL.standardizedFileURL.path`** at Submit time. Stable across runs; invalidated by rename (correct — rename = different identity). PM uses existing `<connector-id>:file:<llm-id>`. | Canonical-path normalization handles symlink and case-folding edge cases. Rename-invalidation is a feature: a renamed file is a different correlation target. | DT §8 |
| D18 | **`submitter` = `NSFullUserName()`** for v1. PM-tenant identity deferred. | Single-user dev context resolves both the same way. Richer identity belongs with connected-mode Submit. | DT §8 |
| D19 | **CLAUDE.md convention lives in a standalone asset file** at `docs/integration/claude_md_addition.md`; the project's `~/src/apps/md-editor-mac/CLAUDE.md` references it via a brief pointer. The asset is intended for future distro-package inclusion as a help file / startup hint. | Asset-shape from v1 makes it readable, embeddable, and ship-able with a future installer; avoids re-extraction work later. | DT §8 + Rick's annotation on §8 |

---

## Acceptance criteria (v1 DOD)

Each item is independently verifiable via the harness + a Local-tab smoke run.

### Session registration

- [ ] `./scripts/md-editor file.md --session=X` opens the file in a new tab and registers `X` as the tab's interest.
- [ ] `./scripts/md-editor file.md` (no `--session` flag) with `MD_EDITOR_SESSION_ID=cc1` in env: `cc1` is registered.
- [ ] Same, no `MD_EDITOR_SESSION_ID` but `TERM_SESSION_ID` present (macOS Terminal default): the terminal id is registered.
- [ ] Same, both env vars unset: no interest is registered; tab opens as manual-open.
- [ ] Re-running `./scripts/md-editor file.md --session=Y` on a tab that already has interest from `X`: `Y` replaces `X` (1:1 cap).

### Tab badge

- [ ] Tab with no interest: no badge (just the dirty-dot if dirty).
- [ ] Tab with one interest: colored dot beside the dirty-dot. Hover shows the session id (or label if set).
- [ ] Badge color is stable across runs for the same session_id (hash-derived).

### Toolbar Submit button

- [ ] Button is visible in the toolbar (after the existing 7 toolbar buttons + Heading dropdown).
- [ ] Button is **enabled** iff the focused tab has a non-empty interest set.
- [ ] Click button → Submit fires for the focused tab's single interested session.
- [ ] `⌘⏎` triggers Submit when button is enabled.
- [ ] Dropdown chevron shows a menu with one item ("Submit"); no extension items in v1.
- [ ] `accessibilityIdentifier`s on button and dropdown items per `AccessibilityIdentifiers`.

### Sidecar emission

- [ ] Submit on a Local-origin tab writes `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/<unix-ms>-<doc-hash>.json` with the full §3.1 payload.
- [ ] Submit on a PM-origin tab writes the same sidecar shape with `doc_origin = "portableMind"` and `doc_id = "<connector-id>:file:<llm-file-id>"`.
- [ ] `doc_id` for Local origin = SHA-256 (hex) of `URL.standardizedFileURL.path`.
- [ ] `submitter` field = `NSFullUserName()`.
- [ ] Sidecar write is atomic (write-to-tmp then rename). Partial-read by a watching consumer is impossible.
- [ ] Multiple Submits on the same doc append new sidecar files (different `<unix-ms>` prefix); never overwrite.
- [ ] **Dirty buffer: save-then-submit.** Submit on a dirty tab triggers `EditorDocument.save()` first; sidecar emits only on save success. Save failure (incl. D19 PM conflict-detection modal) blocks the sidecar write; user resolves and re-clicks Submit.
- [ ] **Sidecar write failure surfaces NSAlert** ("Could not record submission") with the underlying error as informativeText. No sidecar half-written; no silent failure.

### Heartbeat

- [ ] CC-side helper (script or CLAUDE.md-documented one-liner) writes `heartbeat.json` to the session's sidecar dir on a configurable interval; default 60s.
- [ ] `MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0` (or negative) disables the writer.
- [ ] Editor-side prune sweep runs every ~5min; removes any registered interest whose session sidecar dir is missing OR whose `heartbeat.json` mtime is older than `stalenessTimeoutSec` (default 300s).
- [ ] `stalenessTimeoutSec ≤ 0` (configured via UserDefaults / settings) disables the prune sweep.

### Interest release

- [ ] `./scripts/md-editor --session=X --release file.md` removes `X`'s interest from the tab for `file.md`.
- [ ] `./scripts/md-editor --session=X --release --all` removes `X`'s interest from every tab.
- [ ] Closing a tab removes the tab's interest set (and emits no sidecar — closes are not implicit submits).
- [ ] Staleness sweep removes interests for sessions that haven't heartbeat'd recently (unless prune is disabled).

### Harness

- [ ] `submit_focused {session_id, message?}` synthesizes Submit; sidecar appears as expected.
- [ ] `register_session_interest {tabID, session_id}` adds an interest to an already-open tab.
- [ ] `release_session_interest {tabID, session_id}` removes it.
- [ ] `dump_session_interest {path}` emits a JSON dump of `{tabID: [{session_id, label, registered_at}, ...]}`.

### Agent convention

- [ ] Standalone asset file at `docs/integration/claude_md_addition.md` containing the agent-side convention: *"On receiving a Submit event for a doc you authored, re-read the doc first. If its content has diverged substantially from what you wrote, surface the divergence to the user before acting."* Asset includes the sidecar path constant and the heartbeat one-liner.
- [ ] Asset is self-contained — readable in isolation, copy-pasteable into a downstream consumer's CLAUDE.md, ready to be bundled by a future distro package as a help file / startup hint.
- [ ] `~/src/apps/md-editor-mac/CLAUDE.md` references the asset by path (no content duplication).

### Build + test hygiene

- [ ] `xcodebuild build` clean.
- [ ] `MdEditorUnitTests` adds coverage for `SubmitSidecar` (payload serialization + atomic write semantics) and `SessionInterest` color-derivation (hash-stability invariant).
- [ ] Manual test plan covers all 6 user scenarios (A-F).

---

## Open questions

All design-thread questions are resolved (Q1-Q8 above + §§2.x in the design thread). Implementation-time questions surface in the **Plan**.

Note: `docs/portablemind-positioning.md` Q3 ("How does a standalone-mode Submit upgrade to a connected-mode Submit?") remains open but is **out of scope for D30** — it's the question for the future connected-mode follow-up, not for v1.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Heartbeat noise.** CC-side heartbeat at 60s × N parallel sessions = filesystem chatter. Probably fine at small N; could matter at scale. | Default cadence is conservative. Disable knob lets dogfooders turn it off if it's a problem. Revisit at v1.1 if dogfood surfaces churn. |
| R2 | **Sidecar dir hygiene.** A session that registers interest and never cleans up grows its sidecar dir over time (one file per Submit, plus heartbeat.json). | Add a `--clear-history` admin CLI for session-dir reset in v1; full retention policy is a v1.1+ concern. |
| R3 | **Race between Submit emission and CC's fs.watch.** Atomic write (write-to-tmp + rename) eliminates partial-read; fs.watch on most platforms fires reliably on rename-to-existing-dir. | macOS-specific: NSFilePresenter / FSEvents both handle rename-into-watched-dir cleanly. Verify in the harness path. |
| R4 | **Origin routing edge case.** PM tab whose `connectorNode` is no longer reachable (token cleared, connector disconnected) — what does Submit do? | v1: still write the sidecar (the local realization is sufficient; PM connectivity matters only when connected-mode Submit ships). Tag the sidecar with `connector_available: false` for the agent's awareness. |
| R5 | **Sidecar dir location on shared / sandboxed setups.** `~/Library/Application Support/` is the app's container path. | Editor and CC must agree on the path. v1: bake the path into the editor; CC reads it from a documented constant in the CLAUDE.md convention. |
| R6 | **Tab close mid-Submit.** User closes the tab between toolbar-click and sidecar write. | Submit is synchronous on the main actor — sidecar write completes before `EditorDocument` deallocates. Test scenario: `submit_focused` followed immediately by `close_tab`; verify sidecar lands. |
| R7 | **`TERM_SESSION_ID` collision** when two CC sessions share a terminal pane sequentially. | Documented in the CLAUDE.md convention: prefer `MD_EDITOR_SESSION_ID` for CC sessions; `TERM_SESSION_ID` is the fallback. The 1:1 cap means a sequential-CC collision just causes the second session to replace the first's interest — annoying but not corrupting. |

---

## Dependencies

- **Predecessor concept:** `06_persistence_and_connectors` — D18 (`Connector` + origin abstraction), D19 (save-routing pattern Submit's dispatcher mirrors), D23 (`PMFileOperations`-style shared service substrate).
- **Predecessor:** `03_workspace` — D6 CommandSurface (where `OpenFileCommand` is extended), D25's `WorkspaceStore` patterns (`@Published` state, focused-doc resolution).
- **Module:** `Sources/Handoff/` — promoted from D2 stub to populated module in this deliverable.
- **CLAUDE.md** — additions for the stale-version-reconciliation convention.
- **No backend changes.** v1 is on-disk only; PM API integration deferred.

---

## Files (high-level)

### Created

| File | Purpose |
|---|---|
| `Sources/Handoff/SessionInterest.swift` | `SessionInterest` struct (sessionID, registeredAt, label, color). |
| `Sources/Handoff/SubmitSidecar.swift` | Sidecar dir layout; atomic write of submit payload; heartbeat read. |
| `Sources/Handoff/SubmitDispatcher.swift` | Origin-routed Submit action; called by the toolbar button + harness. |
| `Sources/Handoff/HeartbeatPruner.swift` | Editor-side periodic sweep; reads `heartbeat.json` mtimes; mutates interest sets. |
| `Sources/Toolbar/SubmitToolbarButton.swift` | Button-with-dropdown SwiftUI view; reads focused tab from `WorkspaceStore`. |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` (extend) | New ids for toolbar Submit button, dropdown items, tab badge. |
| `docs/current_work/specs/d30_submit_handoff_spec.md` | This file. |
| `docs/current_work/planning/d30_submit_handoff_plan.md` | Phase plan. |
| `docs/current_work/prompts/d30_submit_handoff_prompt.md` | CC briefing. |
| `docs/current_work/testing/d30_submit_handoff_manual_test_plan.md` | Manual test plan. |
| `docs/current_work/stepwise_results/d30_submit_handoff_COMPLETE.md` | Close-out doc. |
| `docs/integration/claude_md_addition.md` | **Asset file** — agent-side Submit convention; future distro-package help/startup-hint asset. |
| `UnitTests/SubmitSidecarTests.swift` | Payload serialization + atomic-write invariants. |
| `UnitTests/SessionInterestTests.swift` | Color hash-stability invariant. |

### Modified

| File | Change |
|---|---|
| `Sources/Workspace/EditorDocument.swift` | Add `interestedSessions: [SessionInterest]` (@Published, v1 cap = 1); init parameter; mutators. |
| `Sources/Workspace/WorkspaceStore.swift` | Resolve interest set for focused doc; submit handler routes to `SubmitDispatcher`; release API. |
| `Sources/CommandSurface/OpenFileCommand.swift` | Add `sessionID: String?` field; parse from URL query `&session=…`. |
| `Sources/CommandSurface/CommandSurface.swift` | Propagate `sessionID` from `OpenFileCommand` into the open-tab pipeline. |
| `Sources/CommandSurface/URLSchemeHandler.swift` | Parse `&session=…` query param. |
| `Sources/CommandSurface/ExternalCommand.swift` | New `releaseSessionInterest` command variant (for the `--release` CLI flow). |
| `Sources/App/MdEditorApp.swift` | Toolbar item placement for the new Submit button; `⌘⏎` keyboard shortcut wiring. |
| `Sources/WorkspaceUI/TabBarView.swift` | Tab badge (informational dot beside dirty-dot); reads `document.interestedSessions`. |
| `Sources/Debug/HarnessCommandPoller.swift` | Four new harness actions. |
| `scripts/md-editor` | `--session=…` flag, `--release` action; default chain `${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}`. |
| `~/src/apps/md-editor-mac/CLAUDE.md` | Short "Submit / Handoff agent convention" section that **points to** `docs/integration/claude_md_addition.md` (no content duplication). |

---

## Notes / context to preserve

- **Submit is the durable differentiator** — keep the v1 surface conservative so the v1.1+ extension slots (message, prompt-back, release, wait-for-session) all land cleanly without re-architecting the v1 substrate.
- **The toolbar button's dropdown chevron is intentionally always present in v1** even though there's only one item underneath. The visual affordance signals "this is the surface where future Submit-related commands will live"; ships discoverable from day 1.
- **The CLAUDE.md convention is a deliverable** — without it, agents receiving Submits won't know to re-read the doc. Easy to forget; treat as first-class.
- **Heartbeat is opt-out, not opt-in.** Default-on with a knob respects the realized-usage constraint (multi-session implies cleanup matters) without forcing it on single-session usage.
- **No backend changes** is a feature — D30 is testable end-to-end on a laptop without any server, dev or prod.
