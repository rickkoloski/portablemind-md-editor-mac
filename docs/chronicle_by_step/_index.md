# Chronicle by step — md-editor timeline

**Type:** Reference — chronological index of completed deliverables. Concept chronicles are the primary navigation surface (`chronicle_by_concept/`); this file is the by-when backup.

Each row links to the deliverable's COMPLETE doc inside its concept folder. Active deliverables in flight (none currently) and pending deliverables (D20, D23+) live in `docs/roadmap_ref.md`, not here.

## Timeline

| Date | D# | Deliverable | Concept | Branch |
|---|---|---|---|---|
| 2026-04-22 | D1 | TextKit 2 live-render feasibility spike | [01_foundation](../chronicle_by_concept/01_foundation/) | `spike/d01-textkit2` |
| 2026-04-22 | D2 | Project scaffolding — promote spike to real project | [01_foundation](../chronicle_by_concept/01_foundation/) | `feature/d02-scaffolding` |
| 2026-04-22 | D4 | Source-mutation primitives + keyboard bindings (13 mutations) | [02_authoring_basics](../chronicle_by_concept/02_authoring_basics/) | `feature/d04-mutations` |
| 2026-04-22 | D5 | Formatting toolbar — visible buttons + Heading dropdown + View → Show/Hide Toolbar | [02_authoring_basics](../chronicle_by_concept/02_authoring_basics/) | `feature/d05-toolbar` |
| 2026-04-23 | D6 | Workspace foundation — folder tree sidebar, tabs, multi-file external-edit, CommandSurface + URL scheme + CLI | [03_workspace](../chronicle_by_concept/03_workspace/) | `feature/d06-workspace` |
| 2026-04-23 | D8 | GFM table rendering — TK2 NSTextLayoutFragment grid | [04_tables_tk2_retired ⚠️](../chronicle_by_concept/04_tables_tk2_retired/) | `feature/d08-tables` |
| 2026-04-23 | D9 | Scroll-to-line on open — CLI suffix `:42` + URL `&line=N&column=M` | [03_workspace](../chronicle_by_concept/03_workspace/) | `feature/d09-scroll-to-line` |
| 2026-04-23 | D10 | Toggleable line numbers — View menu + ⌘⌥L | [03_workspace](../chronicle_by_concept/03_workspace/) | `feature/d10-line-numbers` |
| 2026-04-23 | D11 | CLI control of line numbers — `set-view --line-numbers=on\|off` | [03_workspace](../chronicle_by_concept/03_workspace/) | `feature/d11-cli-line-numbers` |
| 2026-04-24 | D8.1 | Table reveal — caret-on-table opens pipe-source mode | [04_tables_tk2_retired ⚠️](../chronicle_by_concept/04_tables_tk2_retired/) | `feature/d08_1-table-reveal` |
| 2026-04-25 | D12 | Per-cell table editing — single-click in cell at natural height | [04_tables_tk2_retired ⚠️](../chronicle_by_concept/04_tables_tk2_retired/) | `feature/d12-cell-editing` |
| 2026-04-26 | D13 | Cell-edit overlay — Numbers/Excel-style inline overlay + modal popout | [04_tables_tk2_retired ⚠️](../chronicle_by_concept/04_tables_tk2_retired/) | `feature/d13-cell-overlay` |
| 2026-04-26 | D14 | Save / Save As — atomic UTF-8 write through ExternalEditWatcher guard | [06_persistence_and_connectors](../chronicle_by_concept/06_persistence_and_connectors/) | `feature/d14-save-save-as` |
| 2026-04-26 | D15 | Scroll-jump-on-typing fix — `renderCurrentText` save+restore scrollY | [04_tables_tk2_retired ⚠️](../chronicle_by_concept/04_tables_tk2_retired/) | `feature/d15-scroll-jump-fix` |
| 2026-04-26 | D15.1 | Scroll-jump root-cause investigation; **decision: stop fighting TK2** | [04_tables_tk2_retired ⚠️](../chronicle_by_concept/04_tables_tk2_retired/) | `feature/d15_1-scroll-jump-rca` |
| 2026-04-26 | D16 | TextKit 1 spike — native NSTextTable / NSTextTableBlock; four scenarios GREEN | [05_tables](../chronicle_by_concept/05_tables/) | `spike/d16-textkit1-tables` |
| 2026-04-26 | D17 | TextKit 1 migration — retired D8/D8.1/D12/D13/D15.1; ~3,200 lines deleted | [05_tables](../chronicle_by_concept/05_tables/) | `feature/d17-textkit1-migration` |
| 2026-04-27 | D18 | Workspace connector + PortableMind directory tree (read-only) | [06_persistence_and_connectors](../chronicle_by_concept/06_persistence_and_connectors/) | `feature/d18-pm-connector` |
| 2026-04-28 | D19 | PortableMind save-back — conflict-detection prompt; graceful fallback | [06_persistence_and_connectors](../chronicle_by_concept/06_persistence_and_connectors/) | `feature/d19-pm-save-back` |
| 2026-05-05 | D24 | Responsive table column layout — 3-pass measure/distribute/apply; resolves i02 | [05_tables](../chronicle_by_concept/05_tables/) | `feature/d24-responsive-table-columns` |
| 2026-05-06 | D24.2 | Slack-proportional column distribution + Q8 narrow-column lock-in; resolves i05, i06 | [05_tables](../chronicle_by_concept/05_tables/) | `feature/d24.2-slack-proportional-columns` |
| 2026-05-08 | D23 | PortableMind file management — Save As / New File / Rename / Move | [06_persistence_and_connectors](../chronicle_by_concept/06_persistence_and_connectors/) | `feature/d23-pm-file-management` |
| 2026-05-08 | D23.1 | PM delete-file + directory create/delete; closes TODO-D23-tree-splice | [06_persistence_and_connectors](../chronicle_by_concept/06_persistence_and_connectors/) | `feature/d23-pm-file-management` (shared with D23) |
| 2026-05-08 | D25 | Tab tooltip + Reveal in File Tree — closes D22's deferred Reveal-in-Sidebar | [03_workspace](../chronicle_by_concept/03_workspace/) | `feature/d25-tab-tooltip-and-reveal` |

## Side-quests landed off main during D19

| Date | ID | What | Where it lives |
|---|---|---|---|
| 2026-04-27 | D21 | File tree path affordances — Copy Path / Copy Relative Path on tree row context menu, root tooltip showing home-relative path, "Show Path in Tree" toggle on Local root. Shipped from commits alone, no SDLC triad. | `docs/roadmap_ref.md` (D21 row); referenced in `chronicle_by_concept/03_workspace/_index.md` Dependencies |
| 2026-04-28 | i04 | Bearer-token persistence stopgap (file-based; replaces broken cdhash-bound Keychain ACL on ad-hoc-signed builds) | `docs/issues_backlog.md` (i04 entry); revert recipe included |
| 2026-04-28 | D22 | Tab right-click context menu — Copy Path / Copy Relative Path. Reveal-in-Sidebar deferred → closed by **D25** 2026-05-08. | `docs/roadmap_ref.md` (D22 row); `Sources/WorkspaceUI/TabBarView.swift` |

## Notation

- ⚠️ = retired/historical concept. The deliverables are real; the code is gone (replaced or deleted by a later deliverable).
- Branches were deleted after merge; names preserved here for git-history archaeology.
