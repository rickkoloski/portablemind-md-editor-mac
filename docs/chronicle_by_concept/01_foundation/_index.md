# 01 — Foundation

## Overview

The two deliverables that produced "an actual macOS app" out of nothing. D1 answered the existential question — *can a Word/Docs-feel markdown editor be built on TextKit 2 where source is rendered in-place?* — and D2 promoted the spike's answer into a real Xcode project with the engineering discipline (sandbox, accessibility identifiers, xcodegen, Info.plist) that everything since has built on.

This is the only concept in the project where the question was "should we build this at all?" rather than "how should we build this?".

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d01_textkit2_live_render_spike` | Feasibility spike on TextKit 2 in-place rendering | GREEN recommendation; spike code at `spikes/d01_textkit2/` (FROZEN — do not modify per project structure rules) |
| `d02_project_scaffolding` | Promote spike to a real project | `MdEditor.xcodeproj` (xcodegen-generated, committed for reproducibility); engineering-standards `_ref.md` born here |

## Common Tasks

- **"How do we build / run / test the project?"** → `results/d02_project_scaffolding_COMPLETE.md` and `CLAUDE.md` — but those are living docs. This concept captures only the *establishment* of those conventions.
- **"Why TextKit 2 specifically?"** → `specs/d01_textkit2_live_render_spike_spec.md`. (Note: TextKit 2 was abandoned for tables in 2026-04-26 — see `04_tables_tk2_retired` and `05_tables`. TextKit 2 is still used for non-table markdown rendering.)
- **"Where did the engineering standards (sandbox, accessibility identifiers, etc.) come from?"** → D2's COMPLETE doc records the establishment of `docs/engineering-standards_ref.md`.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-22 | **TextKit 2 is feasible for in-place markdown live-render.** | D1 COMPLETE |
| 2026-04-22 | **xcodegen is the source-of-truth** for `MdEditor.xcodeproj`. The committed `.xcodeproj` is regenerated from `project.yml`. | D2 COMPLETE |
| 2026-04-22 | **Every view gets an `accessibilityIdentifier`** — established as a cross-deliverable standard. | `docs/engineering-standards_ref.md` §2 |

## Dependencies

- **Successor concepts:** every other concept builds on this. `02_authoring_basics` adds mutation primitives, `03_workspace` adds the sidebar/tabs, and so on.
- **Note on the live state of TextKit 2:** D17 retired TK2 *for tables* — see `04_tables_tk2_retired`. D1's "TK2 is feasible" decision still holds for non-table rendering (headings, bold, code blocks, paragraphs).
