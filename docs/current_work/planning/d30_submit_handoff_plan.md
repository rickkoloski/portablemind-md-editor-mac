# D30 — Implementation plan

**Spec:** `docs/current_work/specs/d30_submit_handoff_spec.md`
**Prompt:** `docs/current_work/prompts/d30_submit_handoff_prompt.md`
**Design thread:** `docs/current_work/planning/d30_submit_handoff_design_thread.md`
**Branch:** `feature/d30-submit-handoff` (cut from `main` at start of Phase 1).
**Estimate:** ~2 days end-to-end.

Seven phases. Phases 1-3 build the data/wire substrate (no user-visible surface yet). Phase 4 adds heartbeat lifecycle. Phase 5 is the UI surface (toolbar Submit). Phase 6 is the agent convention snippet. Phase 7 is close-out.

Each phase ends with a build-clean + at-least-one harness smoke + a commit. Phase ordering minimizes "broken on main" windows: the first user-visible surface (Phase 5) only lights up after the substrate underneath it is verified.

---

## Phase 0 — Branch + skeleton

**Goal:** prepare the working space.

```bash
git checkout -b feature/d30-submit-handoff main
mkdir -p UnitTests          # already exists
# Sources/Handoff/ already exists (README-only stub from D2)
```

**DOD:**
- Branch cut from main.
- `xcodebuild build` clean (sanity check on a fresh branch).

No commit on this phase.

---

## Phase 1 — Data model + sidecar substrate

**Goal:** the in-memory model + the on-disk format. No CLI, no UI, no lifecycle yet — just the types and the write/read primitives.

### Touchpoints

| File | Change |
|---|---|
| `Sources/Handoff/SessionInterest.swift` | **NEW.** `SessionInterest` struct: `sessionID: String`, `registeredAt: Date`, `label: String?`, `color: NSColor`. Static factory `make(sessionID:label:)` that hash-derives `color` deterministically (HSL with hue from a stable hash of `sessionID`; saturation/lightness fixed). |
| `Sources/Handoff/SubmitSidecar.swift` | **NEW.** Two surfaces: (1) `SubmitPayload` Codable struct mirroring spec §3.1 payload, (2) `SubmitSidecarWriter` with `static func write(_:to:) throws` doing atomic write-to-tmp + rename into the per-session dir. Sidecar dir path computed from `Bundle.main.bundleIdentifier` + `Application Support` resolved via `FileManager.urls(for:.applicationSupportDirectory)`. |
| `Sources/Workspace/EditorDocument.swift` | Add `@Published private(set) var interestedSessions: [SessionInterest] = []`. v1 cap enforced by `setInterestedSession(_:)` mutator (replaces array contents). Add `clearInterestedSessions()`. |
| `UnitTests/SessionInterestTests.swift` | **NEW.** (1) color hash stability — same input → same output across instantiations. (2) color hue distinct for two arbitrary session IDs (regression guard against everyone-gets-gray bug). |
| `UnitTests/SubmitSidecarTests.swift` | **NEW.** (1) Payload round-trips through `JSONEncoder`/`Decoder`. (2) `write` produces a file at the expected per-session path. (3) Concurrent writes (10× to the same session dir) all land as distinct files (different `<unix-ms>` prefix). (4) Atomic write semantics — no reader sees a partial file (probe with a tight read loop). |
| `project.yml` | Add `Sources/Handoff/` to the `MdEditor` target if not already auto-globbed. (Check: D2 may have already added the path.) |

### DOD

- `SubmitPayload` round-trips through Codable.
- `SubmitSidecarWriter.write` produces a file under `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/<unix-ms>-<doc-hash>.json` with mode 0644.
- Atomic-write invariant: a reader doing a tight loop never observes a partial JSON file. Test verifies via `try Data(contentsOf:)` + `try JSONDecoder().decode()` — every read either fails with `noSuchFile` or succeeds with the full payload, never decodes a truncated structure.
- `SessionInterest.make` produces deterministic colors.
- `EditorDocument.interestedSessions` is `@Published`; mutator enforces 1:1 cap.
- `MdEditorUnitTests` passes 25/25 (existing 23 + 2 new test files).
- Build clean.

**Commit:** `D30 phase 1 — Handoff substrate (sidecar writer + SessionInterest)`.

---

## Phase 2 — CLI + CommandSurface plumbing

**Goal:** plumb `--session=X` end-to-end from the CLI shim to `EditorDocument.interestedSessions`. Opening a file with `--session=X` should populate the tab's interest set; no UI surface for it yet (Phase 5).

### Touchpoints

| File | Change |
|---|---|
| `scripts/md-editor` | Parse `--session=…` flag. Default: `session="${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}"` if not supplied. Pass through to URL scheme as `&session=…`. New top-level action `--release` that builds a different URL (or fires a separate URL scheme verb — see `URLSchemeHandler` change below). |
| `Sources/CommandSurface/OpenFileCommand.swift` | Add `let sessionID: String?` stored property. Initializer parses from URL query. |
| `Sources/CommandSurface/URLSchemeHandler.swift` | (1) Extract `session` query param when handling `open` URLs. (2) Add new verb `release` with query params `session=X` + (optional) `path=...` or `all=true`. Routes to `ExternalCommand.releaseSessionInterest`. |
| `Sources/CommandSurface/ExternalCommand.swift` | New enum case `.releaseSessionInterest(sessionID: String, scope: ReleaseScope)` where `ReleaseScope = .file(URL) | .all`. |
| `Sources/CommandSurface/CommandSurface.swift` | `handle(_:)` dispatches `.releaseSessionInterest` to `WorkspaceStore.releaseInterest(sessionID:scope:)` (added in Phase 3). For `.openFile`, pass `sessionID` through to the open-tab pipeline (also wired up in Phase 3). |

### DOD

- `./scripts/md-editor file.md --session=cc1` → URL is `md-editor://open?path=…&session=cc1`.
- `./scripts/md-editor file.md` with `MD_EDITOR_SESSION_ID=cc1` in env → same URL.
- `./scripts/md-editor file.md` with no env vars → URL has no `&session=` param.
- `./scripts/md-editor --session=cc1 --release file.md` → URL is `md-editor://release?session=cc1&path=…`.
- `./scripts/md-editor --session=cc1 --release --all` → URL is `md-editor://release?session=cc1&all=true`.
- `URLSchemeHandler` correctly parses both verbs.
- `OpenFileCommand.sessionID` populates from the URL query.
- Build clean (the lifecycle wiring lands in Phase 3 — Phase 2 just makes the shim + parsing right; `WorkspaceStore.releaseInterest` is a stub for this phase).
- Manual verification via the `commands` harness action: dump the recent commands seen and confirm `sessionID` is non-nil for `--session=…` invocations.

**Commit:** `D30 phase 2 — CLI + URL scheme session plumbing`.

---

## Phase 3 — Interest lifecycle + harness actions

**Goal:** registration on open, release on tab close, the four harness actions. No heartbeat yet (Phase 4); no Submit UI yet (Phase 5).

### Touchpoints

| File | Change |
|---|---|
| `Sources/Workspace/WorkspaceStore.swift` | (1) On open-tab from `OpenFileCommand`, if `sessionID` is non-nil, call `EditorDocument.setInterestedSession(SessionInterest.make(sessionID:label:nil))` after the document is constructed. (2) Add `releaseInterest(sessionID:scope:)` — iterates `openTabs`, removes matching `SessionInterest`. (3) Add `registerInterest(sessionID:on:label:)` for harness use. (4) Add `interestSetForFocusedDoc() -> [SessionInterest]?` — derived from the focused tab. |
| `Sources/Workspace/EditorDocument.swift` | Tab close path (existing `closeTab` in `WorkspaceStore`) — `EditorDocument` deallocates; no special handling beyond what Swift's reference counting gives us. Verify the published change propagates so toolbar button state updates immediately (Phase 5 cares). |
| `Sources/Debug/HarnessCommandPoller.swift` | Four new actions: `register_session_interest`, `release_session_interest`, `dump_session_interest`, `submit_focused` (stub for now — full Submit lands in Phase 5; this phase wires only register/release/dump). |

### DOD

- Opening `./scripts/md-editor file.md --session=cc1` populates `EditorDocument.interestedSessions` for that tab.
- `dump_session_interest` harness action emits `{tabID: [{session_id: "cc1", label: nil, registered_at: "...", color_hex: "..."}]}`.
- `register_session_interest` adds an interest to an already-open tab.
- `release_session_interest` removes a specific session from a specific tab.
- `./scripts/md-editor --session=cc1 --release file.md` removes `cc1`'s interest from the tab for `file.md`.
- `./scripts/md-editor --session=cc1 --release --all` removes `cc1` from every tab.
- Closing a tab (via tab-strip close button or `⌘W`) deallocates its `EditorDocument` and the interest set goes with it — verified by `dump_session_interest` before/after.
- Re-opening a previously-closed file (without `--session=…`) opens as manual-open (no interest).
- 1:1 cap: opening the same file with `--session=cc2` while a tab is already open replaces the existing interest.
- Build clean; MdEditorUnitTests 25/25 GREEN.

### Extension strategy — interest persistence across relaunch (D15 / B2)

D15 commits to **not** persisting session interest across editor relaunches. Rick's constraint: "so long as we don't make a reconsideration of this choice a nightmare to revisit." This phase keeps the seam clean:

- **Trigger to revisit:** dogfood surfaces a "I relaunched the editor and lost my Submit affordance" complaint.
- **Expansion path:** add a parallel write site alongside the existing `persistTabs()` (which already persists `[path]` + focusedIndex to UserDefaults under `openTabsKey`). Persist `[{path, sessionID, label}]` under a new key (e.g., `tabInterestsKey`). Add a parallel restore call inside `restorePersistedTabs()` after the file open succeeds.
- **Refactor risk:** ~25 lines additive; no structural change. The `[SessionInterest]` array on `EditorDocument` is already shaped for this.
- **Open questions parked:** how to handle a persisted interest whose session no longer has a heartbeating sidecar dir on restoration. Easiest: the staleness sweep handles it organically within 5 minutes; cleaner: prune at restoration time before populating the tab.

Keep this section in sync with Plan §Phase 5 / Sources changes — if `interestedSessions`'s shape changes, update the extension-strategy note here.

**Commit:** `D30 phase 3 — interest lifecycle + harness register/release/dump`.

---

## Phase 4 — Heartbeat + staleness pruning

**Goal:** the cleanup mechanism for sessions that crash or vanish.

### Touchpoints

| File | Change |
|---|---|
| `Sources/Handoff/HeartbeatPruner.swift` | **NEW.** `@MainActor` class. On `start()` schedules a `Timer.scheduledTimer(withTimeInterval: 300, repeats: true)`. On tick: iterate every interest in `WorkspaceStore.openTabs`, check `<sidecarBase>/<sessionID>/heartbeat.json` mtime; if missing OR older than `stalenessTimeoutSec`, schedule that interest for removal via `WorkspaceStore.releaseInterest(sessionID:scope:)`. Reads `stalenessTimeoutSec` from `UserDefaults.standard` key `submitStalenessTimeoutSec` (default 300; ≤0 disables sweep entirely). |
| `Sources/App/MdEditorApp.swift` | Instantiate `HeartbeatPruner` on app startup; tear down on app shutdown. |
| `scripts/md-editor-heartbeat` | **NEW** helper script. Loops `touch <sidecar-dir>/heartbeat.json` every `${MD_EDITOR_HEARTBEAT_INTERVAL_SEC:-60}` seconds. Exits cleanly on SIGINT/SIGTERM. Intended to be backgrounded by a CC session at startup: `./scripts/md-editor-heartbeat --session=cc1 &`. If `MD_EDITOR_HEARTBEAT_INTERVAL_SEC` ≤ 0, exits immediately (heartbeat disabled). |
| `Sources/Debug/HarnessCommandPoller.swift` | New harness action `force_staleness_sweep` — runs the prune sweep immediately rather than waiting 5 minutes. For tests. |
| `UnitTests/SubmitSidecarTests.swift` | Add tests: (1) `heartbeatPath(forSession:)` resolves to `<base>/<session>/heartbeat.json`. (2) `isStale(_:thresholdSec:)` returns true for missing file, true for old mtime, false for fresh mtime. |

### DOD

- Editor at startup begins the prune sweep (every 5min).
- `force_staleness_sweep` harness action triggers a sweep on demand.
- Sweep removes interests for sessions whose `heartbeat.json` is older than 300s (default) OR missing OR whose session dir is missing.
- Setting `UserDefaults.standard.set(0, forKey: "submitStalenessTimeoutSec")` disables the sweep entirely (no removals).
- `scripts/md-editor-heartbeat --session=cc1` running in background → `heartbeat.json` mtime refreshes every 60s.
- `MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0 ./scripts/md-editor-heartbeat --session=cc1` exits immediately.
- Build clean; unit tests 27/27 GREEN.

**Commit:** `D30 phase 4 — heartbeat writer + editor-side staleness pruning`.

---

## Phase 5 — Toolbar Submit button + dispatcher + tab badge

**Goal:** the user-facing surface. After this phase, the dogfood loop runs end-to-end.

### Touchpoints

| File | Change |
|---|---|
| `Sources/Handoff/SubmitDispatcher.swift` | **NEW.** `@MainActor` class. `static func submit(_ document: EditorDocument, message: String? = nil, store: WorkspaceStore) async throws`. **Save-then-submit (D14):** if `document.isDirty`, `try await document.save()` first; if save fails (incl. D19 PM conflict-detection cancel/error), rethrow without writing the sidecar. On save success (or already-clean), resolves the single interested session (v1 1:1 cap means `interestedSessions.first`). Builds `SubmitPayload` with `doc_origin` from `document.origin`, `doc_id` (SHA-256 hex of `URL.standardizedFileURL.path` for Local per D17; `<connector-id>:file:<llm-id>` for PM), `submitted_at` = now, `submitter` = `NSFullUserName()` (D18), `message` from param. Calls `SubmitSidecarWriter.write`. Throws on write failure (caller surfaces NSAlert per D16). |
| `Sources/Toolbar/SubmitToolbarButton.swift` | **NEW.** SwiftUI `View`. Observes `WorkspaceStore` for focused doc + its interest set. Renders a `Menu { Button("Submit", action: submit) } label: { Label("Submit", systemImage: "paperplane.fill") }`. `.disabled(focusedInterestSet.isEmpty)`. `.keyboardShortcut(.return, modifiers: .command)`. Tooltip `.help(…)` showing either "Submit to <session_label>" or "No session waiting on this doc." On submit failure (caught from `SubmitDispatcher.submit`), surfaces `NSAlert` with `messageText = "Could not record submission"` and `informativeText = error.localizedDescription` (D16). |
| `Sources/App/MdEditorApp.swift` | Place `SubmitToolbarButton()` in the `ToolbarItemGroup` after the existing buttons. Re-verify `windowToolbarStyle(.expanded)` accommodates the new button (the dropdown chevron needs space). |
| `Sources/WorkspaceUI/TabBarView.swift` | Add a small colored dot beside the dirty-dot when `document.interestedSessions.isEmpty == false`. Color is `interestedSessions.first?.color`. Hover tooltip via `.help(...)` (inside the Button label per the D25 SwiftUI placement gotcha) showing the session id/label. |
| `Sources/Debug/HarnessCommandPoller.swift` | Wire `submit_focused {session_id?, message?}` to `SubmitDispatcher.submit(...)`. If `session_id` is supplied, register it first (or assert it matches the focused tab's existing interest). Writes a result file with `{ok: true, sidecar_path: "..."}` or `{ok: false, error: "..."}`. |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | New ids: `toolbarSubmit`, `toolbarSubmitDropdownSubmit`, `tabBadgeSessionDot(documentID:)`. |

### DOD

- Toolbar Submit button visible in the toolbar.
- Button enabled when focused tab has an interest; disabled otherwise (visible greying confirmed).
- `⌘⏎` triggers Submit when button is enabled.
- Click → sidecar appears at the expected path with the §3.1 payload (`message = null` since v1).
- Dropdown chevron opens a single-item menu with "Submit"; clicking the item is equivalent to clicking the main button.
- Tab badge appears when the doc has an interest; disappears on release/staleness.
- PM-origin tab: Submit writes the sidecar with `doc_origin = "portableMind"` and `doc_id` correctly formed.
- `doc_id` for Local = SHA-256 hex of `URL.standardizedFileURL.path` (verifiable: hash the same path manually, compare to sidecar value).
- `submitter` field = `NSFullUserName()` value (verifiable: compare to `id -F` output).
- **Dirty tab save-then-submit (D14):** Submit on a tab with `isDirty == true` saves first; sidecar appears with the saved content reflected on disk. Test: edit a doc, observe dirty-dot, click Submit, verify (a) doc is no longer dirty, (b) on-disk file reflects the edit, (c) sidecar landed.
- **PM-conflict save failure path (D14):** Submit on a PM tab where the server has a newer version triggers D19's existing conflict modal. If user cancels, NO sidecar is written. If user resolves (overwrite), sidecar lands after save succeeds.
- **Sidecar write failure NSAlert (D16):** simulate via a harness action that forces a write to a non-writable path; verify NSAlert appears with the error message; verify no partial sidecar on disk.
- `submit_focused` harness action drives Submit programmatically; sidecar lands.
- Tab-close-mid-Submit safety: even with rapid `submit_focused` + `close_tab` calls, the sidecar always lands before the doc deallocates (Submit awaits save then write, both on the main actor; close happens between SwiftUI render passes).
- Build clean; live smoke run end-to-end (Scenario A from the spec).

**Commit:** `D30 phase 5 — toolbar Submit button + dispatcher + tab badge`.

---

## Phase 6 — Agent convention asset file

**Goal:** ship the agent-side convention as a **standalone asset** that can also be consumed by a future distro package as a help file / startup hint. Per Rick's annotation on §8 of the design thread.

### Touchpoints

| File | Change |
|---|---|
| `docs/integration/claude_md_addition.md` | **NEW.** Self-contained markdown intended for copy-paste into a downstream consumer's CLAUDE.md or rendering by a future distro-package help surface. Contains: (1) what Submit means in this codebase; (2) the agent-side convention — re-read the doc on Submit; alert on substantial conflict; (3) the canonical sidecar path constant; (4) the heartbeat one-liner pattern (`MD_EDITOR_SESSION_ID=cc1 ./scripts/md-editor-heartbeat &` on session startup, `kill %1` on session exit; CLI flag `MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0` disables); (5) a one-line note that this is asset-shaped on purpose (future distro will bundle as help/startup hint). |
| `docs/integration/` | **NEW directory.** First file in it; carves the integration-asset boundary for future deliverables to grow into. |
| `~/src/apps/md-editor-mac/CLAUDE.md` | Short pointer section: "**Submit / Handoff agent convention** — see `docs/integration/claude_md_addition.md` (intended to be copy-pasted into agent-side CLAUDE.md files; future distro-package help surface)." Single paragraph; no content duplication. |

### DOD

- `docs/integration/claude_md_addition.md` is self-contained — readable on its own without needing to also read the spec.
- Asset references the heartbeat helper path and the sidecar path constant as literal strings — no symbolic substitution needed at distro time.
- `~/src/apps/md-editor-mac/CLAUDE.md` has a brief pointer (≤5 lines) but no duplicated content.
- Asset survives copy-paste into another CLAUDE.md verbatim without breaking the destination's markdown structure (no leading-heading conflicts; relative links resolve clearly enough to be edited at copy-paste time).
- Build clean (no code changes; doc-only commit).

### Notes for the writer

- The asset is intended to be **copy-pasted into the CLAUDE.md of any project where a CC session uses md-editor for review handoffs.** Phrase the convention in the agent's voice: "When you receive a Submit event for a doc you authored, re-read the doc first…"
- Don't make the asset assume the project is md-editor itself — it'll be read by agents running in arbitrary CC sessions.
- One paragraph at the top of the asset says "this is asset-shaped on purpose; future distro-package will bundle it as a help surface." That metadata travels with the asset.

**Commit:** `D30 phase 6 — agent convention asset + CLAUDE.md pointer`.

---

## Phase 7 — Manual test plan + COMPLETE doc + close-out

**Goal:** the artifacts that close the deliverable.

### Touchpoints

| File | Change |
|---|---|
| `docs/current_work/testing/d30_submit_handoff_manual_test_plan.md` | **NEW.** Walk through all 6 spec scenarios (A-F) + every Acceptance Criteria item. Each step has expected result + failure pointers (specific code locations to check on regression). Includes a one-paste harness recipe for the canonical Scenario A end-to-end run. |
| `docs/current_work/stepwise_results/d30_submit_handoff_COMPLETE.md` | **NEW.** Follow the D23/D25 COMPLETE shape: summary, implementation details (what was built + files created + files modified + phase commit log), smoke evidence, testing checklist, deviations from spec, follow-up items, notes. |
| `docs/roadmap_ref.md` | Add D30 row with status `✅ Complete — 2026-MM-DD (feature/d30-submit-handoff)`. Add change-log entry. Reserve a "Candidates (unscheduled)" line for v1.1 (Submit-with-message + Wait-for-session + Send-prompt-back). |
| `docs/issues_backlog.md` | If any in-flight findings surfaced during D30, log them with `i07`/etc. IDs. |

### DOD

- Manual test plan covers every spec acceptance criterion with a runnable step.
- COMPLETE doc cross-references this plan, the spec, the design thread, and the seven phase commits.
- Roadmap row + change-log entry land.
- Build clean; MdEditorUnitTests 27/27 GREEN.
- Branch merged to main (ff or squash per Rick's choice; D23/D25 precedent is ff-merge).
- Tag `v0.8` (the first deliverable in the D3x agent-loop series).

**Commit:** `D30 phase 7 — close-out: manual test plan, COMPLETE, roadmap, tag v0.8`.

---

## Cross-phase risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| RP1 | **`Application Support` directory writeability under sandbox.** v1 is ad-hoc signed; sandbox isn't enforced. But future Developer-ID-signed builds may have entitlement issues. | v1: just write. Document the assumption in the spec; revisit when D3 (packaging) lands. |
| RP2 | **`@MainActor` boundaries.** SubmitDispatcher + HeartbeatPruner both touch UI state (interest sets are @Published, observed by SwiftUI) — must be on the main actor. | Mark classes `@MainActor`. Sidecar writes can dispatch off the main actor via `Task.detached` if perceptible latency surfaces, but v1 default is synchronous on main (atomic write is fast). |
| RP3 | **Multiple windows.** The current scene is single-window. If multi-window lands later, `interestedSessions` is per-document so it scales; the toolbar dispatch needs to switch from `EditorDispatcherRegistry` (single-window) to `@FocusedValue` (multi-window). | Submit dispatch reads from `WorkspaceStore.focusedDocument` rather than going through the editor's text view — already decoupled from the EditorDispatcherRegistry pattern. Multi-window will need a refresh; flagged for the D-future multi-window deliverable. |
| RP4 | **Color collisions** for two sessions whose IDs hash to nearby hues. | Hash function is good but not perfect; if dogfood surfaces collisions, fall back to a palette of N stable colors selected by `hash mod N`. Defer until reported. |
| RP5 | **CC convention drift.** The CLAUDE.md heartbeat one-liner depends on CC sessions remembering to run it. | Phase 6 ships the convention as a project-level CLAUDE.md addition; the heartbeat is opt-in but well-documented. Default cadence (60s) and disable knob keep the cost predictable. |

---

## Test coverage map

| Concern | Unit | Harness | Manual smoke |
|---|---|---|---|
| Payload serialization | SubmitSidecarTests | — | — |
| Atomic write | SubmitSidecarTests | — | — |
| Color hash stability | SessionInterestTests | — | — |
| Open + register | — | dump_session_interest after open | Scenario A |
| Tab close releases interest | — | dump_session_interest before/after | Scenario D |
| `--release` CLI | — | dump_session_interest after release | Scenario D-variant |
| Heartbeat read | SubmitSidecarTests (mtime probe) | force_staleness_sweep | Scenario E |
| Staleness disable | — | force_staleness_sweep with `submitStalenessTimeoutSec=0` | Scenario F |
| Toolbar button state | — | dump_state focused doc | Scenarios A + C |
| `⌘⏎` shortcut | — | (cannot drive — see D19 finding F2) | Manual |
| Submit emission | — | submit_focused → sidecar appears | Scenario A |
| 1:1 cap | — | register_session_interest twice | Scenario A-variant |
| Color stability across runs | SessionInterestTests | — | — |

---

## Out-of-plan / explicitly NOT in D30

- Connected-mode Submit (PM status transition).
- Submit history UI in the editor.
- Multi-session per tab UX.
- Submit-with-message UI.
- "Send prompt back" UI.
- "Wait for session…" affordance for manual-opens.
- v1.1+ wire-format extensions (e.g., content hash, signed sidecars).
- Settings UI for `heartbeatIntervalSec` / `stalenessTimeoutSec` (UserDefaults-only in v1).

All of these are accommodated by the v1 model and wire format — they're feature work on top of the substrate D30 lands.
