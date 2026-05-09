# D25 Manual Test Plan — Tab tooltip + Reveal in File Tree

**Spec:** `docs/current_work/specs/d25_tab_tooltip_and_reveal_spec.md`
**Plan:** `docs/current_work/planning/d25_tab_tooltip_and_reveal_plan.md`
**Branch:** `feature/d25-tab-tooltip-and-reveal`

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
2. Open a workspace folder (File → Open Folder…) — a real project so the tree has nesting.
3. Set a PortableMind token (Debug menu) so the PM connector loads.
4. Open at least:
   - One Local file under a nested directory in the workspace.
   - One PortableMind file under a non-root PM directory (e.g. `/Sales & Marketing/foo.md`).

---

## Test cases

### TC-1 Tab hover tooltip — Local tab inside home

**Action:** Hover the tab for a Local file inside the user's home directory (e.g. `~/src/.../foo.md`). Wait the standard tooltip delay (~1s).

**Expect:**
- Tooltip appears with home-relative path: `~/src/apps/md-editor-mac/Sources/...`.

### TC-2 Tab hover tooltip — Local tab outside home

**Action:** Hover a tab whose file is outside `$HOME` (e.g. `/Volumes/External/foo.md` or `/private/etc/...`).

**Expect:**
- Tooltip shows full absolute path with no `~` collapse.

### TC-3 Tab hover tooltip — PortableMind tab

**Action:** Hover the tab for a PM file under a nested directory (e.g. `/Sales & Marketing/foo.md`).

**Expect:**
- Tooltip shows the PM displayPath verbatim (`/Sales & Marketing/foo.md`).

### TC-4 Tab hover tooltip — Untitled tab

**Action:** Open a brand-new untitled buffer (File → New, or whatever surface creates an untitled doc with no URL). Hover the tab.

**Expect:**
- Tooltip shows "Untitled" (the doc's `displayName` fallback).

### TC-5 Reveal in File Tree — Local tab inside workspace

**Setup:** Local tab is for `<workspace>/dir1/dir2/foo.md`; collapse the tree (right-click root → toggle disclosures so `dir1` is collapsed).

**Action:** Right-click the tab → "Reveal in File Tree".

**Expect:**
- Sidebar tree expands `dir1` then `dir2`.
- Tree scrolls so `foo.md` row is roughly centered in the sidebar viewport.

### TC-6 Reveal in File Tree — PortableMind tab

**Setup:** PM tab is for `/Sales & Marketing/foo.md`; collapse the PM root in the sidebar.

**Action:** Right-click the tab → "Reveal in File Tree".

**Expect:**
- PM root expands (root spinner during async load if cache cold).
- `Sales & Marketing` directory expands (spinner during async load).
- Tree scrolls so `foo.md` row is roughly centered.

### TC-7 Reveal in File Tree — Local file OUTSIDE workspace

**Setup:** Open a Local file via File → Open File… that lives outside the workspace root (e.g. `~/Documents/random.md` while workspace is `~/src/apps/md-editor-mac`).

**Action:** Right-click the tab → "Reveal in File Tree".

**Expect:**
- NSAlert: messageText "This file is outside currently open directories", informativeText shows full path (`~/Documents/random.md`).

### TC-8 Reveal in File Tree — no workspace open + PM tab

**Setup:** Close the workspace (so only PM connector is loaded — actually requires the editor to support no-workspace + PM token, which it does via the no-folder-open empty state). PM tab open.

**Action:** Right-click the tab → "Reveal in File Tree".

**Expect:**
- Reveal works against the PM tree (PM connector still loaded).
- Negative companion: if the PM token is then cleared (Debug menu → clear token, which removes the PM connector), Reveal on the same tab → NSAlert with the PM displayPath.

### TC-9 Reveal in File Tree — PM tab after token cleared

**Setup:** Open a PM tab. Clear the token (Debug menu). The PM connector is removed; the tab remains open as a stale view.

**Action:** Right-click the tab → "Reveal in File Tree".

**Expect:**
- NSAlert: messageText "This file is outside currently open directories", informativeText shows the PM displayPath.

### TC-10 Reveal in File Tree — Untitled tab

**Action:** Open a new untitled buffer; right-click the tab → "Reveal in File Tree".

**Expect:**
- NSAlert: messageText "This file is outside currently open directories", informativeText "Untitled".

---

## Failure pointers

If a test fails, check:

1. **Tooltip not appearing.** The `.help()` modifier must be inside the Button's label (on the `.contentShape(Rectangle())` surface), not after `.buttonStyle(.plain)` on the outer Button. SwiftUI's plain-styled Button doesn't reliably forward `.help()` from outer modifiers to the underlying NSView. See `TabBarView.swift` and the inline comment.
2. **Reveal scrolls to wrong row.** `ScrollViewReader.scrollTo(id, anchor: .center)` looks up rows by their ForEach `id: \.id` identity, which equals the connector-qualified `node.id`. PM file ids are `portablemind:file:<N>`; PM dir ids are `portablemind:dir:<N>`; Local node ids are `local:<absolute path>`.
3. **Reveal scrolls but row not visible.** The 50ms `Task.sleep` between expansion and `pendingRevealNodeID` publish must be long enough for SwiftUI to render newly-expanded rows. If a deeply-nested path proves brittle, switch to a `.task(id: pendingRevealNodeID)` modifier inside the sidebar.
4. **PM ancestor expansion stuck.** Each `await viewModel.expand(path:)` chains an async fetch through the connector. If the PM API is slow / down, the spinner shows on the PM root row; eventually it'll load or surface the connector error. Reveal will scroll only after all expansions resolve.
5. **Outside-tree alert shows wrong informativeText.** `outsideTreeAlert` uses `PathFormatting.absolutePathForCopy(document)` first, then falls back to `document.displayName`. PM tabs always have a displayPath; Untitled local tabs return nil and fall back to "Untitled".
