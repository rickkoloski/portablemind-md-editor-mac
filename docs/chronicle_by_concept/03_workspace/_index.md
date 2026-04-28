# 03 — Workspace

## Overview

Four deliverables that turned the editor from a single-document tool into a workspace. D6 is the foundation — folder-tree sidebar, tabs, multi-file external-edit watching, the `CommandSurface` + URL scheme + CLI wrapper that lets agents drive the editor from outside. D9, D10, D11 are the view-state polish that makes that workspace usable: jump-to-line on open, toggleable line numbers, and CLI control of the line-number toggle.

D6 is one of the largest deliverables in the project — it introduced the dogfood loop that everything since has relied on. The CLI wrapper (`./scripts/md-editor file.md:42`) is what makes Claude Code able to surface review-ready docs to the user without focus-stealing dialogs.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d06_workspace_foundation` | Folder tree + tabs + watcher + URL scheme + CLI | The whole multi-file authoring surface. Single-window scene; file:// URL scheme; `scripts/md-editor` CLI shim. |
| `d09_scroll_to_line` | `:42` line-jump on open | CLI suffix `:N` and URL `&line=N&column=M` route to a scroll target after the document loads. |
| `d10_line_numbers` | Toggleable line numbers | View menu + ⌘⌥L. Persistent via UserDefaults. |
| `d11_cli_line_numbers` | CLI control of line-number toggle | `set-view --line-numbers=on\|off` flag. Explicit-state discipline — never toggle, always set. |

## Common Tasks

- **"How does the editor open a file via the CLI?"** → `specs/d06_workspace_foundation_spec.md` (the CommandSurface section). The flow is: `./scripts/md-editor file.md` → URL scheme → `URLSchemeHandler.handle` → `WorkspaceStore.tabs.open`.
- **"Why does the editor have a single-window scene rather than `WindowGroup`?"** → D6 finding: `WindowGroup` spawns a new window on every external event. Three `./scripts/md-editor …` invocations produced three windows on one process. Switched to single-window `Window("MdEditor", id: "main")`.
- **"How does the file watcher avoid echo-loops on save?"** → `specs/d06_workspace_foundation_spec.md` plus `06_persistence_and_connectors`'s D14 — the watcher pause/restart guard around writes is part of the persistence concept, not this one.
- **"How do I add a new view-state CLI flag?"** → D11 establishes the `set-view` action + flag pattern. New flags follow the same explicit-state discipline (no toggles, always pass `on|off`).

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-23 | **Single-window scene, not `WindowGroup`.** External events route to the existing window. | D6 COMPLETE |
| 2026-04-23 | **CLI is a shell shim around the URL scheme**, not a separate IPC channel. One way to drive the editor from outside, not two. | D6 COMPLETE |
| 2026-04-23 | **Explicit state via CLI** — `--line-numbers=on\|off`, never `--toggle`. Idempotent, scriptable, no need to know prior state. | D11 spec |

## Dependencies

- **Predecessors:** `01_foundation` (project), `02_authoring_basics` (mutation primitives that operate inside the workspace).
- **Successors:**
  - `04_tables_tk2_retired` and `05_tables` extend the editor *inside* the workspace.
  - `06_persistence_and_connectors` adds save semantics (D14) and the connector abstraction (D18, D19) that *replaced* D6's bare-`FolderTreeModel` with `LocalConnector` + `PortableMindConnector`.
- **Cross-cutting:** the harness command-poller (`Sources/Debug/HarnessCommandPoller.swift`) was introduced here in spirit (action dispatch over `/tmp/mdeditor-command.json`); subsequent concepts extended it deliberately rather than reinventing.
