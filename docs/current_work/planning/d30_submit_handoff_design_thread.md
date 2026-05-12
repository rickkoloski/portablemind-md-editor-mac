# D30 — Submit / Handoff: design thread (resolved, pre-triad)

**Status:** Pre-triad design exploration with Rick's annotations folded in. All v1 questions resolved; ready for spec/plan/prompt drafting.
**Trigger:** 2026-05-11 chat — Rick asked about an editor↔CC link with a "Submit" verb for round-trip review loops.
**Constraints:** session-aware **from v1** (multi-session is current dogfood reality); v1 UX cardinality is **1:1** (one interested session per tab); data model leaves room for n:m later.
**Renumber:** Started as D26; renumbered to D30 to reserve D26-D29 for the file-operations series (continuation of D23/D23.1/D25).

---

## 1. What's already in place

**At the design level — strong, deliberate accommodation:**

- `docs/vision.md` Principle 1, "Level 2 agent-aware": Submit is named as **the** durable differentiator. *"Submit is an explicit verb that says 'your turn.' It can start minimal: a sidecar file, a git commit, or a trailing marker the agent watches for."*
- `docs/stack-alternatives.md` §"Architecture lessons" #4: "Submit / Handoff protocol… a wire-format-and-semantics spec, OS-independent. It's also the spec that has to exist for agents to participate, so it's worth writing early."
- `docs/portablemind-positioning.md`: full standalone-mode → connected-mode mapping table (sidecar/git-commit → PortableMind `StatusApplication` transition).
- `docs/stack-alternatives.md` §"File-system access": NSFilePresenter picked partly because *"it handles coordinated reads and writes correctly (which we'll need for Level 2 agent-aware handoffs)."*

**At the code level — module-boundary-only:**

- `Sources/Handoff/README.md` — reserved stub directory. *"Status: Stub only… The module directory exists so a later feature deliverable plugs in at a stable boundary."*
- `EditorDocument.origin: .local | .portableMind` + `connectorNode` — substrate for "Submit dispatches based on origin" (same pattern as D19's save-routing).
- Harness `HarnessCommandPoller` is **request-response only**. There is no bidirectional event channel today — CC cannot receive an unsolicited "Submit happened" event without polling.
- **No session concept anywhere.** No `originatingSessionID` on `EditorDocument`. CLI shim (`scripts/md-editor`) carries file/line/column/`--line-numbers` only — no metadata for who-asked.

Bones are good; muscle isn't there yet.

---

## 2. Design model (resolved)

### 2.1 Tabs carry an interest set — v1 cardinality 1:1

A doc isn't "owned" by a session. Opening with `--session=X` *registers interest*. **v1 caps the interest set at one session per tab.** The data model carries an array (`[SessionInterest]`) so the wire/model doesn't change when n:m lands; the UX and CLI enforce 1:1 in v1 (re-registering with a different session replaces the prior interest).

> **Rick (§2.9 annotation):** "I would be OK with simply: 'the session that opens the doc is interested in it', as a v1." Cross-session visibility and multi-session-per-doc deferred until the n:m UX is designed.

```
EditorDocument.interestedSessions: [SessionInterest]   // @Published, default []; v1 cap = 1

struct SessionInterest {
  let sessionID: String         // opaque string ≤64 chars; see §2.12
  let registeredAt: Date
  let label: String?            // optional short tag the session can declare
  let color: NSColor            // hash-derived from sessionID; future visual identity
}
```

### 2.2 UI surface — toolbar Submit button, tab badge informational

> **Rick (§2.2 annotation):** *"I was actually thinking that there would be a button/dropdown in the toolbar that would act on the currently-open tab… a toolbar button would look cleaner. Given that the rest of the toolbar buttons operate on the open tab, is this really that confusing? It also allows for extensions like a dropdown that homes other commands beside the initial submit, including a text input where a prompt could be sent back."*

**Decision:** toolbar Submit button-with-dropdown, acting on the currently focused tab. Matches the activation model of the existing toolbar buttons (bold, italic, heading dropdown, etc.).

- **Toolbar button:** primary "Submit" action. Default keyboard shortcut `⌘⏎` (per `vision.md` Principle 1 language).
- **Enabled state:** focused tab has an interested session.
- **Disabled state:** focused tab has no interested session (greyed). Hover tooltip: *"No session waiting on this doc."*
- **Dropdown chevron:** v1 = just "Submit." Extension slots reserved for v1.1+:
  - "Submit with message…" (see §2.10)
  - "Send prompt back…" (free-text prompt to the waiting session — Rick's noted future extension)
  - "Release session…" (manual cleanup)
  - "Wait for session…" (the deferred manual-open affordance — see §2.6)
- **Tab badge (informational only):** small colored dot next to the dirty-dot on tabs with non-empty interest set. Hover shows session id/label. **Not clickable** for Submit — submit happens via the toolbar.

### 2.3 Wire format

Per-session sidecar directory, append-only:

```
~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/
  ├── <unix-ms>-<doc-hash>.json     (one file per Submit event)
  ├── heartbeat.json                 (CC-side: refreshed each tick; see §2.7)
  └── ...
```

Per-session path means each CC session `fs.watch`es **exactly one directory**. No cross-session noise.

> **Rick (Q6 annotation):** "right call" — central per-session sidecar; do not also drop adjacent-to-doc sidecars.

Submit payload (v1 always submits with empty `message`; field is present so v1.1's "Submit with message…" doesn't change the wire format):

```json
{
  "doc_path": "/abs/path/file.md",
  "doc_origin": "local|portableMind",
  "doc_id": "<connector-id-or-path-hash>",
  "session_id": "X",
  "submitted_at": "2026-05-11T15:22:33.421Z",
  "submitter": "rickkoloski@gmail.com",
  "message": null
}
```

### 2.4 CLI / CommandSurface

- `./scripts/md-editor file.md --session=X` — open + register interest. Idempotent (re-running just re-registers; under 1:1 cap, replaces any prior interest).
- `./scripts/md-editor --session=X --release [file.md|--all]` — release interest for one doc or all docs.
- URL scheme: `&session=…`.
- `CommandSurface/OpenFileCommand` carries `sessionID: String?` through.

### 2.5 Harness actions (DEBUG-only)

- `submit_focused {session_id, message?}` — drive Submit programmatically.
- `register_session_interest {tabID, session_id}` — declare interest on an already-open tab.
- `release_session_interest {tabID, session_id}` — release.
- `dump_session_interest {path}` — emit `{tabID: [{session_id, label, registered_at}, ...]}` for verification.

### 2.6 Behavior on manual opens — v1 stays silent, defer the affordance

**Decision:** No "Wait for session…" menu item in v1. Slot reserved in the toolbar dropdown for v1.1.

> **Rick (Q5 annotation):** *"I was going to defer this, as the dogfooding has shown that far and away the most common use is what we're doing right now. You're asking for feedback and presenting the feedback request by opening the doc."*

The canonical pattern is **CC opens the doc to ask for feedback** — the request *is* the open. v1 optimizes for that path. Manual-from-Finder opens stay session-less, interest-less, and Submit-disabled.

### 2.7 Tab close releases interest + heartbeat with disable knob

> **Rick (§2.7 annotation):** "does doc close unregister interest?"

**Yes — closing the tab releases the interest.** Tab close ⇒ `EditorDocument` deallocates ⇒ its `interestedSessions` array drops ⇒ the editor's view of who's-waiting-on-which-doc updates. The session's sidecar dir continues to exist (and other docs may still hold its interest from other open tabs) but no Submit affordance is reachable for the closed doc.

> **Rick (Q3 annotation):** "let's add the concept and set to an initial value. We can set it to zero or minus one to disable it."

**Heartbeat — present in v1, with disable knob.** Two tunables:

- `heartbeatIntervalSec: TimeInterval` — CC-side write cadence. Default 60s. **Setting to 0 or negative disables CC-side heartbeat writes.**
- `stalenessTimeoutSec: TimeInterval` — editor-side prune threshold. Default 300s. **Setting to 0 or negative disables editor-side staleness pruning.**

With both disabled, interest persists indefinitely until explicit release or tab close.

Editor-side pruning is a periodic sweep (~5min). The session's sidecar dir's `heartbeat.json` mtime is the truth; the dir's existence is checked too (cleanly-shutdown CC removes the dir).

### 2.8 Origin routing

Same dispatch pattern as D19's save-routing:

- **`.local` origin** → sidecar (the standalone-mode realization).
- **`.portableMind` origin** → sidecar **also** in v1. Connected-mode (PM `StatusApplication` transition via API/MCP) is deferred to a follow-up paired with D20-era connection-management work. Per `docs/portablemind-positioning.md` Q3, the standalone-to-connected upgrade path is itself an open design question.

### 2.9 Cross-session visibility — N/A in v1

**Decision:** Locked to 1:1 cardinality. Cross-session visibility is moot in v1 because at most one session is interested in any given doc.

> **Rick (§2.9 + Q4 annotations):** *"we can account for an eventual cardinality greater than one, but there are some UX questions that will come with doing this cleanly. For this reason, I would be OK with simply: 'the session that opens the doc is interested in it', as a v1."*

Wire format and `EditorDocument.interestedSessions: [SessionInterest]` already leave room for n:m; the v1 cap is purely a UX/CLI enforcement.

### 2.10 Submit-with-message — v1.1

**Decision:** Deferred to v1.1.

> **Rick (Q2 annotation):** "Submit with message was going to be my 1.1, as you see above. We can add it to v1.0 if it's impact is minimal OR if it forces us to design a certain way that will come up inevitably."

Impact is **not** minimal (requires an inline mini-editor or modal; first place we'd surface a "Submit with X parameter" pattern), and the wire-format pre-includes `message: String?` (null in v1) so adding it in v1.1 doesn't break compatibility. Defer.

### 2.11 Stale-version reconciliation — agent-side, CLAUDE.md-injected

**Decision:** Agent always reads the latest version on Submit; project-level CLAUDE.md convention handles substantial-conflict alerting.

> **Rick (Q7 annotation):** *"agent always reads the latest version of the doc. We can add a prompt injection (claude.md) to instruct the agent as to what to do if there is a substantial conflict between what it was expecting and what it saw in the current version of the doc. Namely alert the user."*

- **Editor responsibility:** stop at "Submit happened; here's the path + payload." No content hash on the sidecar in v1.
- **Agent (CLAUDE.md) responsibility:** *"When a Submit event fires for a doc you'd previously authored, re-read the doc first. If its content has diverged substantially from what you wrote, surface the divergence to the user before acting."* This snippet ships as part of D30's deliverables (additions to the project's CLAUDE.md or a referenced convention file).

### 2.12 Session ID source — resolved

> **Rick (Q1 annotation):** "this was the original question I was asking and I need your help to answer it."

**Finding:** Claude Code does **not** currently expose a per-session ID env var. Env probe shows `CLAUDECODE=1`, `AI_AGENT=claude-code/2.1.121/agent`, `CLAUDE_CODE_ENTRYPOINT=cli`, `CLAUDE_CODE_EXECPATH=…` — no per-session UUID. The closest stable id is `TERM_SESSION_ID` (macOS Terminal's per-window UUID).

**Decision:**

1. **The editor treats `--session=X` as opaque.** Any non-empty ASCII-printable string ≤64 chars works.
2. **The CLI shim auto-defaults:** `--session="${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}"`. Explicit `--session=…` flag overrides. If neither env var is set and no flag is passed, no session_id is sent → no interest registered → manual-open path.
3. **Rick's setup convention (recommended):** each terminal pane / CC session gets `export MD_EDITOR_SESSION_ID=cc1` (or `cc2`, `cc3`…) in its shell init. The short slug:
   - Matches the existing terminal-color mental model (`memory/feedback_terminal_colors.md`).
   - Renders cleanly in the tab badge (`cc1`) instead of a long UUID.
   - Lets Rick visually correlate badge color, terminal color, CLI prompt, and chat window.
4. **Forward path:** if Claude Code later exposes a canonical per-session env var, the shim's default chain becomes `${MD_EDITOR_SESSION_ID:-${CLAUDE_SESSION_ID:-$TERM_SESSION_ID}}` — additive, no breaking change.

**Implementation simplicity:** §2.4's `sessionID: String?` plumbing is enough — the editor never needs to know the id's shape or source. All complexity sits in the shell shim's default substitution.

---

## 3. Renumbering

> **Rick (Q8 annotation):** "What about we start a D3x series and reserve the D25... for file operations?"

**Decision:**
- **D26-D29 reserved for the file-operations series** (continuation of D23/D23.1's deferred-follow-ups: directory rename/move, multi-select ops, drag-drop, cross-connector ops, Local-side delete/create-folder UI).
- **D30 = Submit / Handoff v1** (this deliverable).
- The D3x series is the **"agent loop"** branch of the roadmap; D2x stays the file-management branch.
- This file: `d26_submit_handoff_design_thread.md` → `d30_submit_handoff_design_thread.md`.

---

## 4. Scope estimate

~2 days, unchanged. Toolbar-button surface + 1:1 cap simplify the UI work; heartbeat with disable knob is +30 LoC; everything else carries over. Manual-open menu deferred to v1.1.

Work breakdown (will become the plan phases):

- Toolbar Submit button + dropdown scaffold (button-state binding to focused tab's interest set)
- `EditorDocument.interestedSessions` (v1 cap = 1; data model accommodates n:m)
- `SessionInterest` struct + sidecar-dir layout + heartbeat writer/reader (with disable knob)
- CLI shim: env-var defaulting + `--session=…` flag + `--release` action
- `CommandSurface/OpenFileCommand.sessionID: String?` plumbing
- Origin-dispatched Submit (Local sidecar; PM also-sidecar in v1)
- Four harness actions
- CLAUDE.md convention snippet for stale-version reconciliation
- Manual test plan: 1-session-1-doc happy path, tab-close releases interest, heartbeat disable matrix, session ID source matrix (env-var / flag / neither), CC-side fs.watch smoke

---

## 5. Next actions

1. ~~CC reads `**Decision:**` / `**Assumption:**` markers, updates this doc inline with resolutions.~~ **DONE** (this revision).
2. CC drafts the triad: `d30_submit_handoff_spec.md` + `d30_submit_handoff_plan.md` + `d30_submit_handoff_prompt.md`.
3. Triad review with Rick.
4. Implementation phases per the plan.

---

## 6. Related references

- `Sources/Handoff/README.md` — module-boundary stub (D2's reserved hook for this exact deliverable).
- `docs/vision.md` — Principle 1 Level 2 ("Submit is an explicit verb that says 'your turn.'").
- `docs/portablemind-positioning.md` — standalone/connected Submit mapping; Q3 is the open design question for the connected-mode upgrade.
- `docs/stack-alternatives.md` — architecture lesson #4 (Submit/Handoff protocol).
- `docs/roadmap_ref.md` — D20 (connection-management UX) is the natural pair for connected-mode Submit; D26-D29 reserved for file-ops follow-ups.
- `memory/feedback_design_against_realized_usage.md` — the constraint that locked v1 as session-aware (not session-blind).
- `memory/feedback_terminal_colors.md` — the parallel-session visual-identity convention that motivates the short-slug session_id default (cc1/cc2/cc3).
- `memory/md_editor_dogfood_workflow.md` — the `**Question:**` / `**Decision:**` annotation convention this thread used.

---

## 7. Post-triad blocker pass (2026-05-11) — RESOLVED

After drafting the spec/plan/prompt, three real blockers surfaced. All resolved by Rick's `rak:` annotations below. Resolutions folded into the spec (D14-D19 decision-log rows) and plan (Phase 3 extension-strategy callout for B2; Phase 5 save-then-submit + NSAlert wiring; Phase 6 reshaped to ship the convention as a standalone asset).

### B1 — Unsaved-changes-on-Submit behavior

**Question:** When the user clicks Submit on a tab with a dirty buffer, what happens?

Three options:

- **(A) Save-then-Submit.** Submit triggers a save first; sidecar emits only on save success. Save failure (notably PM conflict-detection) propagates cleanly — the user resolves the conflict via D19's existing modal, then re-clicks Submit. Couples Submit's atomicity to D14/D19 save semantics.
- **(B) Submit independent of save.** Sidecar emits with whatever's on disk; dirty buffer ignored. Agent reads stale content; CLAUDE.md convention's "substantial conflict" alert fires after re-read.
- **(C) Block Submit when dirty.** Toolbar button disabled while buffer is dirty; user must save manually first.

**My recommendation: (A).** Submit's whole point is "your turn, look at the latest" — the latest must be on disk. Save failures propagate cleanly through D19's modal. Option (B) creates a guaranteed alert-firing on every dirty Submit, which trains the user to ignore the alert. Option (C) adds a UX step the user will hate (click, wait, click, wait).

rak: a for sure

### B2 — Interest persistence across editor relaunch

**Question:** Tab restoration exists today (`WorkspaceStore.restorePersistedTabs` reopens files by path from UserDefaults). Does session interest survive editor relaunch too?

Two options:

- **(A) Don't persist interest.** Tabs come back; interest sets empty; Submit button disabled until CC re-registers (via `--session=` re-open or `register_session_interest` harness). Simpler model.
- **(B) Persist interest** alongside `openTabsKey`. Restored tabs come back with their prior interests. Requires session_id + label per persisted tab in UserDefaults. Adds a "stale interest from a dead session" failure mode that staleness pruning would handle, but on a 5-minute lag.

**My recommendation: (A).** Editor relaunches are rare; CC sessions that survive a relaunch can re-register cheaply. Persisting interest creates a stale-cleanup problem on the relaunch side that buys little. If dogfood surfaces a "I relaunched the editor and lost my Submit affordance" complaint, revisit in v1.1.

rak: so long as we don't make a reconsideration of this choice a nightmare to revisit, A is good

### B3 — Sidecar write failure UX

**Question:** What happens if `SubmitSidecarWriter.write` throws (disk full, permission denied, sandbox issue)?

Three options:

- **(A) NSAlert** with the underlying error. Matches D14 unsupported-Save and D23.1 destructive-confirmation patterns. User immediately knows Submit didn't fire.
- **(B) Toolbar button shake / red flash** (visual feedback only). Lighter weight; user might miss it.
- **(C) Console-log-only** with a small status indicator somewhere. User definitely misses it.

**My recommendation: (A).** Matches established pattern; cheap to add; the user must know the sidecar didn't land — otherwise they'll wait for an agent response that's never coming.

rak: A is good. This is an edge case (hopefully). It's far more likely to come up with remote files, but so long as we're returning and presenting a good error message, we can defer advanced functionality related to specific error conditions.

---

## 8. Non-blocker decisions (worth pinning before Phase 5)

Lower-stakes than B1-B3, but worth a quick **Decision:** marker if you want to lock them.

- **`doc_id` format for Local files.** SHA-256 of `URL.standardizedFileURL.path` at Submit time. Stable across runs; invalidated by rename (which is correct — rename = different identity). PM uses the existing `<connector-id>:file:<llm-id>` shape — already canonical.

rak: this sounds good.

- **`submitter` field source.** `NSFullUserName()` for v1 (single-user dev context). PM-tenant identity is connected-mode territory; defer.

rak: defer for now.

- **CLAUDE.md heartbeat one-liner shape.** Plain backgrounded process + `kill %1` on session exit. Shell function or `trap`-based cleanup is v1.1 polish.

rak: Let's add a "claude.md addition" prompt to our source tree. We'll include it as an asset when we get to a distro package (maybe a help file or a startup hint).