# D31 — Restore-Doesn't-Work Diagnostic

**Bug:** Opening a file → quit → relaunch → tab doesn't return.
**Fix attempted:** willSet-timing fix at `f147bf0`. User reports bug persists.
**Goal:** Isolate cause (no-persist vs no-flush vs no-restore) before adding belt+braces fixes.

Run the four steps in order. Paste output from steps 1–4 back to CC.

---

## Step 1 — Clean slate + fresh build

Run from a terminal at `~/src/apps/md-editor-mac`:

```bash
cd ~/src/apps/md-editor-mac && \
  defaults delete ai.portablemind.md-editor recent.entries.v1 2>/dev/null ; \
  defaults delete ai.portablemind.md-editor recent.folders.v1 2>/dev/null ; \
  defaults delete ai.portablemind.md-editor session.state.v1 2>/dev/null ; \
  defaults delete ai.portablemind.md-editor openTabs 2>/dev/null ; \
  defaults delete ai.portablemind.md-editor focusedTabIndex 2>/dev/null ; \
  source scripts/env.sh && \
  xcodebuild -project MdEditor.xcodeproj -scheme MdEditor -configuration Debug \
    -derivedDataPath ./.build-xcode build 2>&1 | tail -3 && \
  echo "--- binary timestamp ---" && \
  ls -lT ./.build-xcode/Build/Products/Debug/MdEditor.app/Contents/MacOS/MdEditor
```

**Confirm:** `BUILD SUCCEEDED` and the binary timestamp is from just now.

---

## Step 2 — Launch app, open ONE file, then BEFORE quitting

Launch:

```bash
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Open the same file you opened before (Nimble-First-Time-Login-Sqeuence.md) via the sidebar. **Leave the app running and the tab open.**

From a different terminal (do NOT quit the app):

```bash
defaults read ai.portablemind.md-editor 2>&1 | head -60
```

**Paste the output back to CC.**

This tells us: is persistence happening at all during the live session?

---

## Step 3 — Quit (⌘Q or File → Quit), wait 2s

**Step 2 already confirmed persistence is happening live** (both `recent.entries.v1` and `session.state.v1` keys present, `session.state.v1` starts with `{"focusedTab":"A...`).

Now check what survives the quit. Two flavors — try the first; if it errors, fall back to the second.

**Flavor A (decoded JSON, preferred):**

```bash
sleep 2 && \
  defaults export ai.portablemind.md-editor - | \
    plutil -extract "ai.portablemind.md-editor.session.state.v1" json -o - -
```

**Flavor B (raw hex if A doesn't work):**

```bash
sleep 2 && \
  defaults read ai.portablemind.md-editor "ai.portablemind.md-editor.session.state.v1"
```

**Flavor C (Python one-liner to print the decoded JSON):**

```bash
python3 -c "import subprocess, plistlib, json; d = plistlib.loads(subprocess.run(['defaults','export','ai.portablemind.md-editor','-'], capture_output=True).stdout); print(json.dumps(json.loads(d['ai.portablemind.md-editor.session.state.v1']), indent=2))"
```

**Paste the output back.**

Tells us: does the quit-time state match what step 2 showed, or does something change at quit?

---

## Step 4 — Relaunch app, wait for it to settle, then

Relaunch:

```bash
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Wait ~3 seconds for the app to fully come up. **Note whether tabs are visible in the restored UI** (the Nimble tab + the diagnostic doc should both restore if the bug is fixed).

Then check the post-relaunch state with this Python one-liner:

```bash
python3 -c "import subprocess, plistlib, json; d = plistlib.loads(subprocess.run(['defaults','export','ai.portablemind.md-editor','-'], capture_output=True).stdout); print(json.dumps(json.loads(d['ai.portablemind.md-editor.session.state.v1']), indent=2))"
```

**Paste the JSON back.**

Tells us which sub-case of restore failure we're in:

- **`openTabs` is `[]`** → restore READ the prior state, tab-open failed silently, then the post-restore persist wrote empty.
- **`openTabs` still has the prior tab UUIDs** → restore never consumed the state. Likely an early return in `restoreSession()`.

---

## Step 5 — Inspect the persisted entries (paths)

Step 4 confirms restore-side bug. Need to see WHAT paths the store is trying to open. Run this single-line Python:

```bash
python3 -c "import subprocess, plistlib, json; d = plistlib.loads(subprocess.run(['defaults','export','ai.portablemind.md-editor','-'], capture_output=True).stdout); print(json.dumps(json.loads(d['ai.portablemind.md-editor.recent.entries.v1']), indent=2))"
```

**Paste the JSON back.**

Tells us: are the persisted local paths absolute + valid + readable? If the paths are weird (relative, file:// URLs, symlinks, security-scoped bookmark blobs disguised as paths), `tabs.open(fileURL:)` is failing on `String(contentsOf:)` and silently returning nil.

---

## Step 6 — Manual file-read test against the persisted path

After step 5, copy ONE of the local paths from the JSON output. Then test whether the file can actually be read via stdin (sub for `<PATH>` with the path string, including any spaces — wrap in single quotes):

```bash
head -c 100 '<PATH>' && echo "" && echo "=== read OK ==="
```

If this errors or shows "Permission denied", that's the bug — sandbox or symlink issue. If it succeeds, the bug is elsewhere (probably in `tabs.open` itself).

---

## Diagnosis (after Step 5)

Step 5 showed three entries with valid local paths under home (workspace + Desktop). Not a sandbox / symlink issue. The bug is in WorkspaceStore.init.

### Root cause

`@Published` emits its current value synchronously on subscribe. Without `.dropFirst()`:

1. `WorkspaceStore.init()` subscribes to `tabs.$documents`
2. Combine immediately emits `[]` (empty initial value) to the new subscriber
3. The sink fires with `docs=[]`
4. `persistSessionState(docs:[], focusedIdx:nil)` runs
5. This is the **first** touch of `RecentItemsStore.shared` → triggers `RecentItemsStore.init()` → `load()` populates `sessionState` from disk
6. The very next line in the sink calls `updateSessionState(openTabIDs: [], focusedTabID: nil)` — **OVERWRITES** the just-loaded state to empty
7. Later, `restoreFromBookmarks` → `restoreSession()` reads the wiped-empty `sessionState` → early-returns

Result: every launch wipes the prior session before restore can consume it.

### Fix

`.dropFirst()` on both `$documents` and `$focusedIndex` publishers in `WorkspaceStore.init()`. Skips the synchronous initial-value emission; real user-driven changes still come through normally.

Committed at `57e3e91`.

---

## Step 7 — Retest after fix

Rebuild, then re-run the round-trip:

```bash
cd ~/src/apps/md-editor-mac && source scripts/env.sh && xcodebuild -project MdEditor.xcodeproj -scheme MdEditor -configuration Debug -derivedDataPath ./.build-xcode build 2>&1 | tail -3
```

Then:

1. Launch the app: `open ./.build-xcode/Build/Products/Debug/MdEditor.app`
2. Open 2 files (any combination of workspace + Desktop)
3. Quit (⌘Q)
4. Relaunch from Finder/terminal
5. **Expected:** both tabs auto-restore, previously focused tab focused, scroll line where you left off (±1)

If this works, the bug is fixed. If not, paste the post-relaunch JSON:

```bash
python3 -c "import subprocess, plistlib, json; d = plistlib.loads(subprocess.run(['defaults','export','ai.portablemind.md-editor','-'], capture_output=True).stdout); print(json.dumps(json.loads(d['ai.portablemind.md-editor.session.state.v1']), indent=2))"
```

---

## What the outputs will tell us

| Step 2 has session.state.v1 with openTabs[1]? | Step 3 matches Step 2? | Step 4 tab visible in UI? | Diagnosis |
|---|---|---|---|
| No | — | — | **Persist path broken** — sink isn't firing or isRestoring is stuck. Add logging. |
| Yes | No | — | **Quit-time flush issue** — UserDefaults batched, needs synchronize() or applicationWillTerminate handler. |
| Yes | Yes | No | **Restore path broken** — sessionState reads zero or entry lookup fails. Inspect restoreSession. |
| Yes | Yes | Yes | Bug fixed; was just stale binary from prior runs. |

Once we know which row we're in, the fix is targeted (and minimal).
