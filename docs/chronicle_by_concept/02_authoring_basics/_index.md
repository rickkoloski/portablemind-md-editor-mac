# 02 — Authoring Basics

## Overview

The two deliverables that turned the editor from "a text view that renders markdown" into "a tool a user can author markdown with". D4 built 13 source-mutation primitives wired to keyboard shortcuts (no UI yet — primitives only); D5 surfaced those primitives as a formatting toolbar with the Heading dropdown. By the end of D5, vision Principle 1 (Word/Docs-familiar authoring) was realized at its core level — bold/italic/headings/lists feel exactly like they would in any other editor.

The deliberate **invisible-plumbing-before-visible-feature** ordering (D4 mutations before D5 toolbar) is one of this project's recurring patterns: ship the primitive first, validate it via keyboard or harness, *then* add the UI so failures isolate cleanly.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d04_mutation_primitives` | 13 source mutations + keyboard bindings | Bold/italic/inline code/link/heading 0-6/bullet/numbered. Uniform toggle semantics, code-block safety, one-step undo. No UI yet. |
| `d05_formatting_toolbar` | Visible toolbar wired to D4 primitives | 7 direct buttons + Heading dropdown (Body + H1-H6) + View → Show/Hide Toolbar (⌘⌥T) with UserDefaults persistence. |

## Common Tasks

- **"How does ⌘B / ⌘I / etc. work?"** → `specs/d04_mutation_primitives_spec.md`. The mutation pipeline is keyboard-input → mutation function → source replacement.
- **"How do I add a new formatting button?"** → `specs/d05_formatting_toolbar_spec.md`, particularly the `ToolbarButton(action: .X)` pattern.
- **"Why did the View menu work get bundled here?"** → D5 COMPLETE — surfaced during toolbar work that `CommandMenu("View")` creates a duplicate menu unless you use `CommandGroup(replacing: .toolbar)`.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-22 | **Uniform toggle semantics across all 13 mutations.** Pressing the keyboard shortcut twice un-applies the mutation. | D4 COMPLETE |
| 2026-04-22 | **Mutations are no-ops inside fenced code blocks.** Markdown inside code is literal text. | D4 COMPLETE |
| 2026-04-22 | **All mutations are one-step undoable.** No multi-step undo to back out of a single keyboard shortcut. | D4 COMPLETE |
| 2026-04-22 | **Toolbar visibility is persistent** (UserDefaults). Closing and reopening the editor preserves the visibility choice. | D5 COMPLETE |
| 2026-04-22 | **UITest identifier queries on SwiftUI Button+Label use `.firstMatch`** (multiple nodes match per Button). Established as a cross-deliverable engineering-standard. | `docs/engineering-standards_ref.md` §2.1 |

## Dependencies

- **Predecessor:** `01_foundation` (project + TK2 live render).
- **Successor concepts:** every later concept builds on the mutation primitives — D9-D11 in `03_workspace` add view-state CLI controls; D14 in `06_persistence_and_connectors` saves the buffer authored via these mutations.
