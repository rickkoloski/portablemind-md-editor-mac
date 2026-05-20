# D31: Open Recent + Session Restore — Manual Test Plan

**Spec:** `docs/current_work/specs/d31_mru_and_session_restore_spec.md`
**Plan:** `docs/current_work/planning/d31_mru_and_session_restore_plan.md`
**Branch under test:** `feature/d31-mru-and-session-restore`

This plan covers the success criteria that aren't fully exercised by automated tests:

| SC | Covered automatically | Covered here |
|---|---|---|
| SC1 — local + PM round-trip | Underlying logic in `RecentItemsStoreTests` | Yes (full launch round-trip) |
| SC2 — both files in menu, folder in Recent Folders | — | Yes |
| SC3 — deleted local file → silent skip + disabled menu entry | — | Yes |
| SC4 — cleared PM token → disabled entry; restore token → re-enabled | — | Yes |
| SC5 — 16th file evicts oldest | `testRecordLocalLRUCap` + `testRecordFolderLRUCap` | Optional spot-check |
| SC6 — Clear Menu empties everything | `testClearWipesAllThreeStores` | Yes (live UI) |
| SC7 — first launch / wiped defaults: `(No Recent Files)` shows | XCUITest skipped (i03) | Yes |
| SC8 — migration from legacy keys | `testMigrationFromLegacyKeys` + 3 sibling tests | Optional one-shot |

---

## Pre-flight

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor -configuration Debug \
  -derivedDataPath ./.build-xcode build
```

The build artifact lives at `./.build-xcode/Build/Products/Debug/MdEditor.app`.

**Two launch flavors used below:**

```bash
# Clean launch (preserves existing recents / session state)
open ./.build-xcode/Build/Products/Debug/MdEditor.app

# Reset launch (wipes the three D31 UserDefaults keys before first read)
open ./.build-xcode/Build/Products/Debug/MdEditor.app --args --reset-recents
```

To inspect persisted state from a terminal:

```bash
defaults read ai.portablemind.md-editor recent.entries.v1
defaults read ai.portablemind.md-editor recent.folders.v1
defaults read ai.portablemind.md-editor session.state.v1
```

---

## §A — SC7: First-launch empty state

1. Quit the app if running.
2. Launch with `--reset-recents`.
3. Click **File** in the menu bar.
4. Hover **Open Recent**.
5. **Expected:** submenu shows a single disabled item titled `(No Recent Files)`.
6. **Expected:** no Clear Menu, no Recent Folders header, no entries.

**Pass criteria:** §5 + §6 both observed. Failure modes to flag: submenu doesn't open; placeholder missing; any other items appear.

---

## §B — SC2 / SC5 spot-check: Recording opens

1. Quit, relaunch with `--reset-recents`.
2. **File → Open Folder…** → pick `~/src/apps/md-editor-mac` (the project folder).
3. In the sidebar, click `docs/_scratch.md` (or any other `.md` file).
4. Click another `.md` file in the sidebar (e.g. `docs/roadmap_ref.md`).
5. Click **File → Open Recent**.
6. **Expected:**
   - Both `.md` filenames appear under Open Recent, newest (the second one) on top.
   - Divider, then **Recent Folders** header (disabled).
   - `md-editor-mac` appears under Recent Folders.
   - Divider, then **Clear Menu**.
7. Optional LRU spot-check: open ~16 distinct files (use the harness or repeatedly click different sidebar entries). After the 16th, the first one should no longer appear in the menu.

---

## §C — SC1: Round-trip restore (local only)

1. From the state at end of §B (two local tabs open).
2. Scroll the focused tab to roughly line 30 (or any non-line-1 position).
3. Wait ~1s after scroll settles (D31 debounces scroll persistence at 500ms).
4. Quit the app cleanly (⌘Q).
5. Inspect:
   ```bash
   defaults read ai.portablemind.md-editor session.state.v1
   ```
   **Expected:** `openTabs` array has 2 UUIDs, `focusedTab` is one of them, `scrollLines` dictionary has 1-2 entries.
6. Relaunch (clean — NOT `--reset-recents`).
7. **Expected:** both tabs re-open in the same order, the previously-focused one is focused, the focused tab is scrolled to approximately the previous line (±1 line).

**Pass criteria:** all three of: tab set restored, focus restored, scroll line restored.

---

## §D — SC1: Round-trip restore (mixed local + PM)

Requires the PM token to be present in the Keychain (Debug → Set PortableMind Token… if not).

1. Quit, relaunch.
2. Verify a PM connector is loaded (sidebar has a `portablemind` root in addition to the local one).
3. Open one local `.md` file from the sidebar.
4. Open one PM `.md` file from the PM tree (any small file — `test-sample.md` if seeded).
5. Focus the PM tab. Scroll it.
6. Wait ~1s.
7. Quit.
8. Relaunch (clean).
9. **Expected:** both tabs return. PM tab arrives async (fetch resolves over network) — the focused-tab assignment lands once the PM fetch completes. Final state: PM tab is focused at the scroll line.

**Pass criteria:** mixed tabs both restored; focus + scroll preserved on the PM tab.

---

## §E — SC3: Deleted local file → silent skip on restore + disabled menu entry

1. State: a local tab is open from §C / §D and persisted.
2. Quit.
3. From a terminal, `rm` (or move) the local file that was open.
4. Relaunch.
5. **Expected:** the tab does NOT open. No error dialog. The other tab (if any) restores normally and the previously-focused tab gets focus iff the surviving tab WAS the focused one (or focus is nil if the deleted tab was focused).
6. Open **File → Open Recent**.
7. **Expected:** the deleted file still appears in the menu, greyed out, with `(unavailable)` suffix. Clicking it is a no-op.

---

## §F — SC4: Cleared PM token → disabled entry; restored token → re-enabled

1. Have at least one PM `RecentEntry` from §D.
2. Debug → Clear PortableMind Token.
3. Open **File → Open Recent**.
4. **Expected:** the PM entry appears greyed out with `(unavailable)` suffix.
5. Debug → Set PortableMind Token… (paste a valid token).
6. Re-open **File → Open Recent**.
7. **Expected:** the PM entry is enabled again.
8. Click it.
9. **Expected:** the PM file opens as a new tab via the existing connector path. No error.

---

## §G — SC6: Clear Menu

1. State: several entries in the menu (local + folder; PM if present).
2. **File → Open Recent → Clear Menu**.
3. Re-open **File → Open Recent**.
4. **Expected:** the submenu now shows only `(No Recent Files)`. Both file entries and folder entries are gone.
5. Inspect:
   ```bash
   defaults read ai.portablemind.md-editor
   ```
   **Expected:** `recent.entries.v1`, `recent.folders.v1`, and `session.state.v1` keys are gone (the in-store `clear()` removes all three keys).

---

## §H — SC8: Migration from legacy keys (one-shot)

This is a one-time path that runs only on first launch of the D31 build against a pre-D31 defaults domain. Worth running once on a real upgrade scenario; once migrated, the legacy keys are gone and the path is dormant.

1. Quit. From terminal, seed the legacy keys against the app's domain:
   ```bash
   defaults write ai.portablemind.md-editor openTabs -array \
     "$HOME/src/apps/md-editor-mac/README.md" \
     "/tmp/nonexistent-file-d31-migration.md"
   defaults write ai.portablemind.md-editor focusedTabIndex -int 0
   ```
2. Wipe the new keys to simulate a true upgrade:
   ```bash
   defaults delete ai.portablemind.md-editor recent.entries.v1 2>/dev/null
   defaults delete ai.portablemind.md-editor session.state.v1 2>/dev/null
   ```
3. Launch (clean — no `--reset-recents`).
4. **Expected:**
   - `README.md` opens as a tab and is focused.
   - The bogus `/tmp/nonexistent...` path is silently dropped.
   - `defaults read ai.portablemind.md-editor openTabs` → `does not exist`.
   - `defaults read ai.portablemind.md-editor focusedTabIndex` → `does not exist`.
   - `defaults read ai.portablemind.md-editor session.state.v1` → contains the README's RecentEntry UUID in `openTabs` and `focusedTab`.
5. **Expected:** Open Recent now shows `README.md` (only — migration intentionally does NOT backfill MRU entries for legacy state, only for the open tabs).

---

## §I — Harness recipe (optional, one-paste sanity)

For a fast no-UI sanity check that the store wiring is intact:

```swift
// In an Xcode breakpoint console, with WorkspaceStore.shared loaded:
po RecentItemsStore.shared.entries.map(\.displayName)
po RecentItemsStore.shared.folders.map(\.displayName)
po RecentItemsStore.shared.sessionState
```

Or from a script:

```bash
defaults read-type ai.portablemind.md-editor recent.entries.v1   # should be -type data
defaults read-type ai.portablemind.md-editor session.state.v1    # should be -type data
```

---

## Results

| Section | Date | Result | Notes |
|---|---|---|---|
| §A — SC7 empty state | | | |
| §B — recording opens | | | |
| §C — local round-trip | | | |
| §D — mixed local + PM | | | |
| §E — deleted local file | | | |
| §F — cleared PM token | | | |
| §G — Clear Menu | | | |
| §H — legacy migration | | | |

Update this table during dogfood; close out before merging to `main`.
