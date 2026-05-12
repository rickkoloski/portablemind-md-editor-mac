# D30 Manual Test Plan — Submit / Handoff (standalone-mode v1)

**Spec:** `docs/current_work/specs/d30_submit_handoff_spec.md`
**Plan:** `docs/current_work/planning/d30_submit_handoff_plan.md`
**Branch:** `feature/d30-submit-handoff`

---

## Setup

1. Build & launch:
   ```bash
   source scripts/env.sh
   xcodegen generate
   xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
              -configuration Debug -derivedDataPath ./.build-xcode build
   open ./.build-xcode/Build/Products/Debug/MdEditor.app
   ```
2. Cleanup before each fresh run (test artifacts shouldn't leak across runs):
   ```bash
   rm -rf "$HOME/Library/Application Support/ai.portablemind.md-editor/submits"/test-*
   rm -f /tmp/d30-* /tmp/mdeditor-command.json
   ```
3. Write a fixture:
   ```bash
   echo '# D30 fixture\n\nHello.' > /tmp/d30-fixture.md
   ```

---

## Cross-cutting harness recipe

Driver-controlled smoke that exercises all of Scenarios A, D, E (atomic, repeatable). One-paste:

```bash
# Open with session interest.
~/src/apps/md-editor-mac/scripts/md-editor /tmp/d30-fixture.md --session=test-cc1

sleep 1

# Verify interest registered.
echo '{"action":"dump_session_interest","path":"/tmp/d30-dump.json"}' \
  > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6
jq '.tabs[].interests[0].session_id' /tmp/d30-dump.json
# expect: "test-cc1"

# Dirty the buffer (proper edit path).
echo '{"action":"set_selection","location":0,"length":0}' \
  > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6
echo '{"action":"insert_text","text":"EDITED "}' \
  > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6

# Submit (should save-then-emit).
echo '{"action":"submit_focused","path":"/tmp/d30-submit.json"}' \
  > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6
jq '.' /tmp/d30-submit.json

# Verify on-disk reflects the edit (save ran first).
head -1 /tmp/d30-fixture.md
# expect: "EDITED # D30 fixture"

# Verify sidecar payload.
SIDECAR=$(jq -r .sidecarPath /tmp/d30-submit.json)
jq '.' "$SIDECAR"
# expect: doc_origin=local, doc_id=<sha-256-hex>, session_id="test-cc1",
#         submitter=<NSFullUserName>, message=null

# Force the staleness sweep (no heartbeat is writing).
echo '{"action":"force_staleness_sweep","path":"/tmp/d30-sweep.json"}' \
  > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6
jq '.' /tmp/d30-sweep.json
# expect: interestCountBefore=1, interestCountAfter=0

# Cleanup.
rm -rf "$HOME/Library/Application Support/ai.portablemind.md-editor/submits/test-cc1"
rm -f /tmp/d30-fixture.md /tmp/d30-*.json
```

---

## Test cases

### TC-1 Open with `--session=` registers interest (Scenario A)

**Action:** `./scripts/md-editor /tmp/d30-fixture.md --session=cc1`.

**Expect:**
- Tab opens; small colored dot appears next to the dirty-dot.
- Toolbar Submit button (paperplane icon) is enabled.
- `dump_session_interest` shows one tab with `interests[0].session_id == "cc1"`.

**Failure pointers:** `Sources/CommandSurface/OpenFileCommand.swift` (param parsing), `Sources/Workspace/WorkspaceStore.swift#registerInterest`, `Sources/WorkspaceUI/TabBarView.swift` (badge render).

### TC-2 Env-var default for session id

**Action:**
```bash
MD_EDITOR_SESSION_ID=cc-env ./scripts/md-editor /tmp/d30-fixture.md
```

**Expect:** Same as TC-1, with `session_id == "cc-env"`.

**Failure pointers:** `scripts/md-editor` — `session_arg` defaulting chain.

### TC-3 Explicit empty `--session=` opts out

**Action:**
```bash
MD_EDITOR_SESSION_ID=cc1 ./scripts/md-editor /tmp/d30-fixture.md --session=
```

**Expect:**
- Tab opens with **no** badge.
- Toolbar Submit button is disabled.
- `dump_session_interest` shows the tab with `interests: []`.

### TC-4 No `--session=` and no env-var falls back to TERM_SESSION_ID

**Action:**
```bash
( unset MD_EDITOR_SESSION_ID; ./scripts/md-editor /tmp/d30-fixture.md )
```

**Expect:** Interest registered with `session_id == "$TERM_SESSION_ID"` (the macOS Terminal's per-window UUID).

### TC-5 Toolbar Submit enabled state

**Action:** Open `/tmp/d30-fixture.md` (no session) and another file `/tmp/d30-fixture2.md --session=cc2`. Click each tab.

**Expect:**
- On fixture (no session): toolbar Submit is **disabled**; hover tooltip "No session waiting on this doc".
- On fixture2 (cc2 session): toolbar Submit is **enabled**; hover tooltip "Submit to cc2 (⌘↩)".

### TC-6 Submit emits a sidecar with the correct payload

**Action:** With cc1 registered on `/tmp/d30-fixture.md`, click Submit (or `⌘⏎`, or harness `submit_focused`).

**Expect:**
- File appears at `~/Library/Application Support/ai.portablemind.md-editor/submits/cc1/<unix-ms>-<short-hash>.json`.
- Payload:
  - `doc_path` = absolute path of fixture.
  - `doc_origin` = `"local"`.
  - `doc_id` = SHA-256 hex of `URL.standardizedFileURL.path` (64 hex chars).
  - `session_id` = `"cc1"`.
  - `submitted_at` = ISO8601 with millisecond precision.
  - `submitter` = `NSFullUserName()` (e.g. `"Richard Koloski"`).
  - `message` = JSON `null` (the key is present).

**Failure pointers:** `Sources/Handoff/SubmitDispatcher.swift#makePayload`, `Sources/Handoff/SubmitSidecar.swift#write` (atomic-write path), `Sources/Handoff/SubmitSidecar.swift#docID(forLocal:)` (canonicalization).

### TC-7 Save-then-Submit on a dirty buffer (D14)

**Action:** Open `/tmp/d30-fixture.md --session=cc1`; insert text via the harness or by typing; verify buffer is dirty (dirty-dot visible); click Submit.

**Expect:**
- Save runs first: on-disk file content reflects the edit.
- Sidecar emits AFTER save success.
- Buffer transitions to clean (dirty-dot gone).

**Failure pointers:** `Sources/Handoff/SubmitDispatcher.swift#submit` — the `if document.dirty` guard and the `try await document.save(force: false)` line.

### TC-8 Save failure blocks the sidecar (D14)

**Action:** Open a PM tab with a server version newer than the local `lastSeenUpdatedAt` (D19 conflict-detection scenario); edit; click Submit. When the conflict modal appears, click Cancel.

**Expect:**
- Conflict modal appears (D19 path).
- After cancel, **no** sidecar file is written.
- Buffer remains dirty.
- Re-clicking Submit re-runs the save attempt.

**Failure pointers:** `Sources/Handoff/SubmitDispatcher.swift` rethrows `saveBeforeSubmitFailed`; `Sources/Toolbar/SubmitToolbarButton.swift#performSubmit` catches and skips sidecar.

### TC-9 Sidecar write failure surfaces NSAlert (D16)

**Action:** Hard to provoke organically — easiest path: temporarily chmod the user's Application Support container to read-only (or simulate via a harness shim that mocks the failure). Click Submit.

**Expect:**
- NSAlert appears with `messageText = "Could not record submission"` and the underlying error in `informativeText`.
- No partial sidecar file remains on disk.

**Failure pointers:** `Sources/Handoff/SubmitDispatcher.swift` throws `sidecarWriteFailed`; `SubmitToolbarButton.presentSubmitError`.

### TC-10 Tab close releases interest (Scenario D)

**Action:** Open `/tmp/d30-fixture.md --session=cc1`. `dump_session_interest` → 1 interest. Close the tab via the tab-strip × or `⌘W`. `dump_session_interest` again.

**Expect:** Tab is gone; the dumped tab list no longer includes it; the session's sidecar dir on disk continues to exist (no implicit cleanup).

### TC-11 `--release file.md` (CLI path)

**Action:** With cc1 registered on the fixture: `./scripts/md-editor --session=cc1 --release /tmp/d30-fixture.md`.

**Expect:** `dump_session_interest` shows the tab still open but with `interests: []`. Toolbar Submit is now disabled.

### TC-12 `--release --all`

**Action:** Register cc1 on two files; run `./scripts/md-editor --session=cc1 --release --all`.

**Expect:** Both tabs' interest sets are empty.

### TC-13 1:1 cap — re-register replaces

**Action:** Register cc1 on the fixture; immediately register cc2 via the harness:
```bash
echo '{"action":"register_session_interest","session_id":"cc2","label":"replacement"}' \
  > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
```

**Expect:** `interests` array has length 1, and the single entry's `session_id` is `cc2`. cc1 is gone.

### TC-14 Heartbeat helper + staleness sweep (Scenario E)

**Action:**
1. Start the heartbeat helper for a session that's NOT registered on any tab:
   ```bash
   MD_EDITOR_SESSION_ID=cc-living MD_EDITOR_HEARTBEAT_INTERVAL_SEC=5 \
     ~/src/apps/md-editor-mac/scripts/md-editor-heartbeat &
   ```
2. Verify `heartbeat.json` appears under `~/Library/.../submits/cc-living/` and refreshes every 5s.
3. Register cc-living on the fixture via the harness. Force a sweep:
   ```bash
   echo '{"action":"force_staleness_sweep","path":"/tmp/sweep.json"}' \
     > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6
   jq . /tmp/sweep.json
   ```
4. Expect `interestCountBefore == interestCountAfter` (interest preserved — heartbeat is fresh).
5. `kill %1` to stop the heartbeat. Wait until heartbeat.json is older than 300s OR temporarily lower the threshold:
   ```bash
   defaults write ai.portablemind.md-editor submitStalenessTimeoutSec -float 5
   sleep 10
   echo '{"action":"force_staleness_sweep","path":"/tmp/sweep2.json"}' \
     > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json && sleep 0.6
   jq . /tmp/sweep2.json
   ```
6. Expect `interestCountAfter < interestCountBefore` (sweep released cc-living's interest).

**Failure pointers:** `Sources/Handoff/HeartbeatPruner.swift`, `Sources/Handoff/SubmitSidecar.swift#isStale`, `scripts/md-editor-heartbeat`.

### TC-15 Disable knob — heartbeat helper (`MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0`)

**Action:** `MD_EDITOR_SESSION_ID=cc-disabled MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0 ~/src/apps/md-editor-mac/scripts/md-editor-heartbeat`.

**Expect:** Script exits immediately (`$?` is 0). No `heartbeat.json` written.

### TC-16 Disable knob — editor-side sweep (`submitStalenessTimeoutSec ≤ 0`)

**Action:**
```bash
defaults write ai.portablemind.md-editor submitStalenessTimeoutSec -int 0
```
Restart the editor. Register a session with no heartbeat; force_staleness_sweep.

**Expect:** Sweep no-ops; interest remains registered indefinitely.

Cleanup:
```bash
defaults delete ai.portablemind.md-editor submitStalenessTimeoutSec
```

### TC-17 Manual-open path (Scenario C)

**Action:** Double-click `/tmp/d30-fixture.md` in Finder (NOT via the shim).

**Expect:**
- Tab opens with no badge.
- Toolbar Submit is disabled.
- `dump_session_interest` shows `interests: []` on the tab.

### TC-18 PM tab origin routing (D7)

**Action:** Open a PortableMind tab with a session (use the Debug menu to set the token, register a session id on the PM tab via the harness `register_session_interest`, then `submit_focused`).

**Expect:**
- Sidecar emits with `doc_origin = "portableMind"`, `doc_id = "<connector-id>:file:<llm-file-id>"`, `doc_path` = PM displayPath.

---

## Graduation to XCUITest

`SubmitSidecar` payload + atomic-write + `isStale` are covered by unit tests today (`UnitTests/SubmitSidecarTests.swift`, 12 tests + 4 staleness tests). `SessionInterest` color stability is covered (`UnitTests/SessionInterestTests.swift`, 6 tests).

The UI surfaces (toolbar button enabled state, badge render, NSAlert on failure) are reachable from XCUITest via the `accessibilityIdentifier`s already in place (`toolbarSubmit`, `toolbarSubmitDropdownSubmit`, `tabSessionBadge`). When XCUITest coverage is added in a later deliverable, prioritize:

- Toolbar Submit enabled/disabled state across focus changes.
- Tab badge appears/disappears on register/release.
- NSAlert message text on synthesized failures.

The save-then-Submit dirty-buffer flow is harness-driven via `insert_text` + `submit_focused` (recipe at the top of this file); XCUITest can drive the same path by sending real keyDown events.
