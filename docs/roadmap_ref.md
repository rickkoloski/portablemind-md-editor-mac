# md-editor-mac Roadmap (informal)

**Type:** Reference — informal planning sketch, not a commitment.
**Status:** Living; extend at the start of each deliverable cycle. Concrete commitments live in `docs/current_work/specs/dNN_*_spec.md` as they get drafted.

## Why this file exists

Rough ordering of planned deliverables so that current work has context for what comes next. **Order and scope can change.** Anything on this list that isn't in `docs/current_work/specs/` hasn't been scoped yet.

## Current ordering (as of 2026-04-22)

| D# | Deliverable | Status |
|---|---|---|
| D1 | TextKit 2 live-render feasibility spike | ✅ Complete — GREEN recommendation |
| D2 | Project scaffolding — promote spike to real project | Triad drafted, awaiting implementation |
| D3 | Packaging — Sparkle + DMG + Developer ID + notarization | Gates on Apple Developer Program enrollment |
| D4 | Source-mutation primitives + keyboard bindings (bold / italic / heading / link / list / code). No UI yet. | Planned |
| D5 | Formatting toolbar — visible buttons wired to D4's primitives + View → Show/Hide Toolbar | Planned; first user-visible "real feature" for the priority-1 audience |
| D6+ | **PortableMind integration** — connected mode, Submit → status transition, document↔entity association, tenant sign-in | Planned post-D5 per CD (Rick). Bridges the standalone app (D1–D5) to the PortableMind ecosystem per `docs/portablemind-positioning.md`. |

## Candidates (unscheduled)

Items on the table but not yet ordered. Most will slot into D6+ or later.

- Folder tree / sidebar navigation
- Outline / heading navigator panel
- Submit / Handoff primitive (standalone mode — git commit / sidecar file)
- Multi-document / tabs / window management
- Preferences window
- Dark mode polish
- Second document type (JSON or YAML) — proves Principle 3 and the document-type registry abstraction from D2
- Search within document; search across vault-like folder
- Typography switch (proportional body) — intentionally held back from D2 because it changes product feel
- VoiceOver / accessibility polish beyond the D2 baseline
- macOS Services menu integration, Quick Look, etc.
- Windows and Linux ports — the second implementations from the shared non-code SDLC artifacts per vision Principle 2

## Ordering principles

1. **Standalone product value first** (D1–D5 keep the app useful without any PortableMind dependency).
2. **Packaging before distribution need, not before.** D3 is right-sized at "can install on another mac"; can slip later if no second machine needs it yet.
3. **Invisible plumbing before visible feature** where it makes validation crisper (e.g., D4 mutations before D5 toolbar).
4. **Don't bundle typography changes with scaffolding or infrastructure.** Feel-changes get dedicated deliverables so we can observe their effect cleanly.
5. **Each deliverable traces back to at least one foundation doc** (`vision.md`, `competitive-analysis.md`, `portablemind-positioning.md`, `stack-alternatives.md`, `engineering-standards_ref.md`).

## Change log

- **2026-04-22** — Initial creation. D1 complete; D2 triad drafted; D3–D5 sketched; PortableMind integration positioned post-D5 per CD's direction during D2 spec review.
