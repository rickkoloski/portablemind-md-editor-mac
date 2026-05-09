# D25 — Tab tooltip + Reveal in File Tree

**Status:** DRAFT (compact — single-session enhancement triad).

**Trace:**
- `docs/roadmap_ref.md` D22 row: "Reveal-in-Sidebar **deferred to a future iteration**." This is that future iteration.
- Surfaced during dogfood 2026-05-08 — Rick: "this tool has become key to my workflows."

**Position in roadmap:** D25 — UX polish on the tab strip. Pairs two small enhancements that share the tab-context-menu surface and the same path-resolution helper.

---

## Why now

Two papercuts surfaced during dogfood:

1. **No way to see a tab's full path at a glance.** The tab label truncates with middle-ellipsis at ~160pt. When several tabs share a leaf name (`README.md` from different repos; `index.md` from different dirs) or when the user wants to confirm which `foo.md` is open, hovering should reveal the full canonical path. The Copy Path / Copy Relative Path entries from D22 require a click to see the path.

2. **No way to jump from an open tab to its location in the sidebar.** D22 shipped Copy Path on tabs precisely because the agent-opened-via-CLI case meant the file's tree position wasn't visible. D22's COMPLETE doc explicitly deferred Reveal-in-Sidebar; v1 made do with copy-paste. After three weeks of dogfood (D23/D23.1 PM workflows, daily authoring), Reveal-in-Tree is now the missing piece.

---

## Scope

In scope:

| Enhancement | Surface | Behavior |
|---|---|---|
| **Tab tooltip** | Hover any tab in the tab bar | `.help()` shows the full canonical path. Local tabs: home-relative `~`-prefixed path or absolute (matches `PathFormatting.absolutePathForCopy(doc)`). PortableMind tabs: `displayPath` verbatim. Untitled local tabs (no URL): no tooltip (return nil → SwiftUI's `.help()` accepts `String?` only via wrapper; v1 uses an empty-string sentinel to suppress). |
| **Reveal in File Tree** | Right-click a tab → "Reveal in File Tree" | Resolves which connector tree owns the file. Expands every ancestor in order (async-safe for PM). Scrolls the sidebar to the file's row. If the file is **outside any open tree** (e.g., a Local file opened from outside the workspace, or a PM tab with no PM connector loaded), surfaces a stock NSAlert: **"This file is outside currently open directories"** with the full path as informativeText. |

Out of scope (v1):
- Reveal selecting / highlighting the row (just scroll). Tree row "selection" doesn't exist as a model concept yet; SwiftUI rows are tap-to-open without a sticky selection state.
- Keyboard shortcut for Reveal (matching D22's pattern of context-menu-only).
- Local-tab tooltip showing relative path (the absolute / home-relative form is the canonical "where is this" answer).

---

## Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-08 | **Q1 — Tooltip text format.** Use `PathFormatting.absolutePathForCopy(doc)` directly. Local: home-relative `~` form when inside home, else absolute. PM: displayPath verbatim (`/Sales & Marketing/foo.md`). Untitled local: no tooltip. | Reuses the D22 helper. Same canonical form the user already understands from Copy Path. |
| 2026-05-08 | **Q2 — Reveal menu item label.** "Reveal in File Tree". | Matches Rick's phrasing ("open the file tree to the file"). "File Tree" mirrors `AccessibilityIdentifiers.folderTree` and the project's own term in CLAUDE.md / engineering-standards (the sidebar's accessibility id is `md-editor.sidebar.folder-tree`). |
| 2026-05-08 | **Q3 — Outside-tree behavior.** When the tab's file isn't under any loaded connector, surface a stock NSAlert "This file is outside currently open directories" with the full path as informativeText. | Per Rick 2026-05-08: "we just want to surface an alert/modal saying 'This file is outside currently open directories' with the file path." NSAlert is the established pattern (D14 unsupported-Save, D23.1 delete confirm). |
| 2026-05-08 | **Q4 — Scroll mechanism.** Wrap the sidebar's existing `ScrollView` in a `ScrollViewReader`; expose a transient `pendingRevealNodeID: String?` on `WorkspaceStore`; sidebar `.onChange(of:)` calls `proxy.scrollTo(id, anchor: .center)` and clears the pending request. | Idiomatic SwiftUI. Decouples the WorkspaceStore (no SwiftUI proxy reference) from the sidebar (which holds the ScrollViewReader). |
| 2026-05-08 | **Q5 — Ancestor expansion.** Walk the path from connector root down to the file's parent; for each ancestor, call `await viewModel.expand(path:)` sequentially. PortableMind expansion is async (chains through `connector.children(of:)`); Local expansion is sync but serialized for uniformity. | Mirrors how a user would manually open the tree: top-down. Sequential await ensures each level's children are loaded before the next ancestor's path is checked. |
| 2026-05-08 | **Q6 — No keyboard shortcut.** | Mirrors D22's deliberate no-shortcut decision. Avoids shortcut churn; the menu item is discoverable via right-click. |

---

## Acceptance criteria

1. **Hover tab** → after macOS's standard tooltip delay, the full canonical path appears.
2. **Untitled tab** → no tooltip (no path to show).
3. **Right-click tab → Reveal in File Tree** on a Local tab inside the workspace → the sidebar's tree expands every ancestor and scrolls to the file's row.
4. **Right-click tab → Reveal in File Tree** on a PM tab → the sidebar's PM tree expands every ancestor (each loads asynchronously) and scrolls to the file's row.
5. **Right-click tab → Reveal in File Tree** on a Local tab whose file is outside the workspace root → NSAlert "This file is outside currently open directories" with the full path as informativeText.
6. **Right-click tab → Reveal in File Tree** on a PM tab when no PM connector is loaded → same NSAlert.
7. **`xcodebuild test` GREEN.**
8. **Manual test plan walked end-to-end** with results recorded in the close-out.

---

## Risks / open implementation questions

1. **Scroll target visibility.** SwiftUI's `ScrollViewReader.scrollTo(_:anchor:)` only works if the target view is in the rendered tree. Newly-expanded rows must be laid out before scrollTo fires. Mitigation: a brief `Task.sleep(50ms)` between the last `expand` and the published scroll-target write so the view has a chance to render the freshly-expanded rows. If 50ms proves brittle, we can drive the scroll from a `.task(id: pendingRevealNodeID)` modifier inside the sidebar — that runs after the body re-evaluates.
2. **Local tab ancestor walking.** Local nodes' paths are absolute (`/Users/rick/.../foo.md`); workspace root is also absolute. Ancestor walk is `nodeRelative = node.path.dropFirst(rootPath.count + 1)` then split on `/`, accumulate prefixes prepended with `rootPath`.
3. **PM root path is `""`.** PortableMind's `rootNode.path` is the empty string (verified in `PortableMindConnector.swift:35`). The asyncChildren cache is keyed by the empty string for the root. Ancestor list for `/Sales & Marketing/foo.md` is `["", "/Sales & Marketing"]`.
4. **Tab tooltip rebuild on rename/move.** PM Rename/Move (D23 phases 4+5) update `doc.origin` + `doc.connectorNode`. Since the tooltip computes from `doc.origin`, it'll reflect the new path on the next hover automatically. Save As (D23 phase 2) also rebinds origin. No extra wiring needed.

---

## Out of scope (deferred to future deliverables)

| Item | Sketch | Trigger |
|---|---|---|
| **Sidebar row selection state** | Persistent "selected row" highlight model. Reveal could then highlight the row briefly (Finder-style flash). | Pairs with multi-select work for D26+ directory CRUD. |
| **Reveal keyboard shortcut** | e.g. ⌘⇧L "Locate in Sidebar". | If dogfood proves the right-click discovery is too slow. |
| **Tooltip with last-saved timestamp / size** | Multi-line tooltip with metadata. | Future polish — `.help()` is text-only; would need a custom NSPopover. |
