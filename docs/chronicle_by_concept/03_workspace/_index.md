# 03 — Workspace

## Overview

Five deliverables that turned the editor from a single-document tool into a workspace. D6 is the foundation — folder-tree sidebar, tabs, multi-file external-edit watching, the `CommandSurface` + URL scheme + CLI wrapper that lets agents drive the editor from outside. D9, D10, D11 are the view-state polish that makes that workspace usable: jump-to-line on open, toggleable line numbers, and CLI control of the line-number toggle. D25 (shipped 2026-05-08, tag `v0.7.1`) closed two dogfood papercuts on the tab strip: hover tooltip with full canonical path and right-click → "Reveal in File Tree" — closing the deferred Reveal-in-Sidebar follow-up that D22 carried since 2026-04-28.

D6 is one of the largest deliverables in the project — it introduced the dogfood loop that everything since has relied on. The CLI wrapper (`./scripts/md-editor file.md:42`) is what makes Claude Code able to surface review-ready docs to the user without focus-stealing dialogs.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d06_workspace_foundation` | Folder tree + tabs + watcher + URL scheme + CLI | The whole multi-file authoring surface. Single-window scene; file:// URL scheme; `scripts/md-editor` CLI shim. |
| `d09_scroll_to_line` | `:42` line-jump on open | CLI suffix `:N` and URL `&line=N&column=M` route to a scroll target after the document loads. |
| `d10_line_numbers` | Toggleable line numbers | View menu + ⌘⌥L. Persistent via UserDefaults. |
| `d11_cli_line_numbers` | CLI control of line-number toggle | `set-view --line-numbers=on\|off` flag. Explicit-state discipline — never toggle, always set. |
| `d25_tab_tooltip_and_reveal` | Tab hover tooltip + Reveal in File Tree | `.help(...)` on `TabItemView` (inside the Button label, not outside — see decision below) for full-path hover tooltip; right-click → "Reveal in File Tree" expands sidebar ancestors via `await ConnectorTreeViewModel.expand(path:)` and scrolls to the file's row via `WorkspaceStore.pendingRevealNodeID` + `ScrollViewReader.onChange`. Outside-tree case → stock NSAlert with full path. Closes D22's deferred Reveal-in-Sidebar item. |

## Common Tasks

- **"How does the editor open a file via the CLI?"** → `specs/d06_workspace_foundation_spec.md` (the CommandSurface section). The flow is: `./scripts/md-editor file.md` → URL scheme → `URLSchemeHandler.handle` → `WorkspaceStore.tabs.open`.
- **"Why does the editor have a single-window scene rather than `WindowGroup`?"** → D6 finding: `WindowGroup` spawns a new window on every external event. Three `./scripts/md-editor …` invocations produced three windows on one process. Switched to single-window `Window("MdEditor", id: "main")`.
- **"How does the file watcher avoid echo-loops on save?"** → `specs/d06_workspace_foundation_spec.md` plus `06_persistence_and_connectors`'s D14 — the watcher pause/restart guard around writes is part of the persistence concept, not this one.
- **"How do I add a new view-state CLI flag?"** → D11 establishes the `set-view` action + flag pattern. New flags follow the same explicit-state discipline (no toggles, always pass `on|off`).
- **"How does Reveal in File Tree work?"** → D25 spec + `Sources/Workspace/WorkspaceStore.swift` `revealInTree(document:)`. Resolves the matching connector view-model, walks ancestors top-down via `ancestorPathsFromRoot(...)` (handles PM's empty-string root and Local's absolute root uniformly), calls `await ConnectorTreeViewModel.expand(path:)` for each ancestor, sleeps 50ms so SwiftUI lays out the freshly-expanded rows, then publishes `pendingRevealNodeID`. Sidebar `ScrollViewReader.onChange` consumes via `proxy.scrollTo(id, anchor: .center)` and clears. Outside-tree case (Local-outside-workspace, no-workspace + PM tab, PM-token-cleared, Untitled) surfaces an NSAlert with full path.
- **"Why is `.help()` inside the Button label, not on the outer Button?"** → SwiftUI gotcha: `.help()` on a plain-styled outer Button (`.buttonStyle(.plain)` + custom content) doesn't reliably forward to the underlying NSView tooltip. Working `.help()` calls (warning-triangle, READ-ONLY badge, dirty-dot) are all on leaf views inside the Button label. D25 phase 1 hit this; phase 2 fixed by moving `.help()` inside the Button label on the same `.contentShape(Rectangle())` surface. Pattern reusable for any future tooltip on a custom-styled Button.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-23 | **Single-window scene, not `WindowGroup`.** External events route to the existing window. | D6 COMPLETE |
| 2026-04-23 | **CLI is a shell shim around the URL scheme**, not a separate IPC channel. One way to drive the editor from outside, not two. | D6 COMPLETE |
| 2026-04-23 | **Explicit state via CLI** — `--line-numbers=on\|off`, never `--toggle`. Idempotent, scriptable, no need to know prior state. | D11 spec |
| 2026-05-08 | **`.help()` placement is inside the Button label**, on the same `.contentShape(Rectangle())` surface as the working dirty-dot / warning-triangle tooltips. SwiftUI doesn't reliably forward `.help()` on plain-styled outer Buttons with custom content. | D25 deviation §1 |
| 2026-05-08 | **`pendingRevealNodeID` pattern** — transient `@Published` ID, consumed by sidebar `ScrollViewReader.onChange`, cleared after `scrollTo`. Reusable substrate for any future scroll-to-row trigger (cross-session "open these tabs and reveal them," harness actions). | D25 spec |
| 2026-05-08 | **Outside-tree surface is a stock NSAlert** with messageText "This file is outside currently open directories" + full path as informativeText. Covers Local-outside-workspace, no-workspace + PM tab, PM-token-cleared, and Untitled. | D25 spec |

## Dependencies

- **Predecessors:** `01_foundation` (project), `02_authoring_basics` (mutation primitives that operate inside the workspace).
- **Successors:**
  - `04_tables_tk2_retired` and `05_tables` extend the editor *inside* the workspace.
  - `06_persistence_and_connectors` adds save semantics (D14) and the connector abstraction (D18, D19, D23, D23.1) that *replaced* D6's bare-`FolderTreeModel` with `LocalConnector` + `PortableMindConnector`. D25's Reveal-in-Tree relies on `ConnectorTreeViewModel.expand(path:)` introduced by that concept.
- **Cross-cutting:** the harness command-poller (`Sources/Debug/HarnessCommandPoller.swift`) was introduced here in spirit (action dispatch over `/tmp/mdeditor-command.json`); subsequent concepts extended it deliberately rather than reinventing.
- **Side-quests adjacent to this concept (no triads):**
  - **D21** (2026-04-27) — File tree path affordances on row context menu (Copy Path / Copy Relative Path, root tooltip, "Show Path in Tree" toggle). Shipped from commits alone, no SDLC triad. See `docs/roadmap_ref.md` D21 row.
  - **D22** (2026-04-28) — Tab right-click Copy Path / Copy Relative Path. Surfaced during D19 phase 4 dogfood; shipped from commits alone. Reveal-in-Sidebar deferred from D22 was closed by **D25** above. See `docs/roadmap_ref.md` D22 row.
