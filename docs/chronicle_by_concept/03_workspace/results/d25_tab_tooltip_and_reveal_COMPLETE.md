# D25: Tab tooltip + Reveal in File Tree — Complete

**Spec:** `docs/current_work/specs/d25_tab_tooltip_and_reveal_spec.md`
**Plan:** `docs/current_work/planning/d25_tab_tooltip_and_reveal_plan.md`
**Prompt:** `docs/current_work/prompts/d25_tab_tooltip_and_reveal_prompt.md`
**Manual test plan:** `docs/current_work/testing/d25_tab_tooltip_and_reveal_manual_test_plan.md`
**Branch:** `feature/d25-tab-tooltip-and-reveal`
**Tag:** `v0.7.1` (UX-polish patch on top of v0.7)
**Completed:** 2026-05-08

---

## Summary

Two dogfood-discovered papercuts on the tab strip, closed in a single small deliverable:

1. **Tab hover tooltip** — every tab now reveals its full canonical path on hover. Resolves the "which `README.md` is this?" identity question that tab-label truncation introduces.
2. **Reveal in File Tree** — right-click a tab → menu item that expands the sidebar tree's ancestors and scrolls to the file's row. Closes the "Reveal-in-Sidebar deferred" follow-up D22 carried since 2026-04-28.

Both share the same surface (the tab) and the same path-resolution helper (`PathFormatting.absolutePathForCopy(doc)`).

---

## Implementation Details

### What Was Built

- **Tab hover tooltip** — `.help(...)` on `TabItemView`'s inner `.contentShape(Rectangle())` surface (inside the Button label, NOT on the outer plain-styled Button — see deviations §1). Reuses `PathFormatting.absolutePathForCopy(doc)`; falls back to `document.displayName` for Untitled tabs.
- **Reveal in File Tree** — context-menu item on each tab. Calls `WorkspaceStore.revealInTree(document:)` which:
  1. Resolves which connector / view-model owns the document (Local: workspace `LocalConnector`; PM: matching `PortableMindConnector` by id).
  2. Computes the ancestor path list via `ancestorPathsFromRoot(rootPath:nodePath:separator:)` — handles the empty-string PM root and the absolute Local root uniformly.
  3. `await viewModel.expand(path:)` for each ancestor in root-to-parent order. PM expansion is async; Local is sync.
  4. `Task.sleep(50ms)` so SwiftUI renders the freshly-expanded rows before the scroll-target is published.
  5. Sets `pendingRevealNodeID` (transient `@Published`).
- **`WorkspaceView.sidebar`** — wraps existing `ScrollView` in `ScrollViewReader { proxy in ... }`. `.onChange(of: workspace.pendingRevealNodeID)` calls `proxy.scrollTo(id, anchor: .center)` and clears via `workspace.clearReveal()`.
- **Outside-tree alert** — stock NSAlert with messageText "This file is outside currently open directories" and the file's full path as informativeText. Covers four paths: Local-outside-workspace, no-workspace + PM tab, PM-token-cleared, Untitled.
- **AccessibilityIdentifier** — `tabReveal(documentID:)`.

### Files Modified

| File | Changes |
|------|---------|
| `Sources/WorkspaceUI/TabBarView.swift` | `.help(...)` inside the Button label on the `.contentShape(Rectangle())` surface; "Reveal in File Tree" item appended to `.contextMenu` (after `Divider()`). |
| `Sources/Workspace/WorkspaceStore.swift` | `import AppKit`; `pendingRevealNodeID: String?`; `revealInTree(document:)`, `clearReveal()`, `resolveRevealTarget(for:)`, `ancestorPathsFromRoot(...)`, `outsideTreeAlert(for:)`. |
| `Sources/WorkspaceUI/WorkspaceView.swift` | Sidebar `ScrollView` wrapped in `ScrollViewReader`; `.onChange(of: pendingRevealNodeID)` → `proxy.scrollTo(id, anchor: .center)`. |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | `static func tabReveal(documentID: UUID) -> String`. |

### Files Created

| File | Purpose |
|------|---------|
| `docs/current_work/specs/d25_tab_tooltip_and_reveal_spec.md` | Spec |
| `docs/current_work/planning/d25_tab_tooltip_and_reveal_plan.md` | Plan |
| `docs/current_work/prompts/d25_tab_tooltip_and_reveal_prompt.md` | Prompt |
| `docs/current_work/testing/d25_tab_tooltip_and_reveal_manual_test_plan.md` | Manual test plan |
| `docs/current_work/stepwise_results/d25_tab_tooltip_and_reveal_COMPLETE.md` | This file |

---

## Phase commit log

| Phase | Commit | Notes |
|---|---|---|
| Triad + phase 1 | `fdb728e` | spec/plan/prompt + tab tooltip (initial placement on outer Button) |
| Phase 2 + tooltip placement fix | `cc12a11` | Reveal in File Tree complete; tooltip moved inside Button label after live-smoke confirmed outer placement didn't fire |
| Close-out | _this commit_ | manual test plan + COMPLETE + roadmap; ff-merge to main; tag v0.7.1 |

---

## Smoke evidence

Verified live by Rick 2026-05-08:
- Right-click tab → "Reveal in File Tree" — works (ancestors expand, tree scrolls to file row).
- Tooltip after placement fix — works on hover.

---

## Deviations from Spec

### 1. `.help()` placement: outside Button → inside Button label

The spec / plan called for `.help(...)` on the outer Button (after `.buttonStyle(.plain)`). Phase-1 implementation followed that, but live smoke showed the tooltip never appearing. Root cause: SwiftUI's `.help()` on a plain-styled outer Button doesn't reliably forward to the underlying NSView's tooltip when the button uses custom content. Working `.help()` calls in the same file (warning-triangle, READ-ONLY badge, dirty-dot) are all on leaf views inside the Button label.

Fix in phase 2: moved `.help(...)` inside the Button label, on the same `.contentShape(Rectangle())` surface, immediately above the closing brace of the label. Tooltip now fires on hover as designed.

Captured as risk #2 in the plan ("If not, fallback is a `.background(... NSViewRepresentable for trackingArea)`"). The simpler in-label placement avoided the NSViewRepresentable fallback.

### 2. Untitled-tab tooltip: empty-string suppression → displayName fallback

Spec said "Untitled local tab → no tooltip" via empty-string `.help("")` suppression. Implementation falls back to `document.displayName` ("Untitled") instead. Showing the doc's name on hover is harmless and clearer than silent fallback; the spec preference was soft. No user-visible regression.

---

## Testing

- [x] **Build clean** through both phases.
- [x] **Unit tests:** MdEditorUnitTests 23/23 GREEN (no new tests; behavior is UI-coupled and covered by the manual test plan).
- [x] **Live editor smoke** (commits `fdb728e` + `cc12a11`):
  - Reveal in File Tree on PM and Local tabs — verified.
  - Tab hover tooltip after placement fix — verified.
- [x] **D17 + D19 + D23 manual test plans:** unaffected (tab strip is additive only).

---

## Follow-Up Items

The spec's "Out of scope" section is the canonical list. None moved into scope during D25:

- **Sidebar row selection state** — pairs with future multi-select work for D26+ directory CRUD.
- **Reveal keyboard shortcut** (e.g. ⌘⇧L "Locate in Sidebar") — if dogfood proves right-click discovery is too slow.
- **Multi-line tooltip with metadata** (size, last-saved timestamp, dirty state) — would need a custom NSPopover; `.help()` is text-only.

---

## Notes

- **Closes D22's deferred Reveal-in-Sidebar item.** D22's COMPLETE doc explicitly listed Reveal-in-Sidebar as deferred. D25 is the follow-up; the roadmap's D22 row is annotated to point at D25.
- **`pendingRevealNodeID` pattern** is a clean substrate for any future "scroll-to-row" trigger (e.g. cross-session "open these tabs and reveal them" commands, or harness actions). Reusable.
- **No backend changes.** SwiftUI/AppKit only; PM connector untouched.
- **Roadmap entry placed after D24.2** (last completed UX-shipped deliverable). D24/D24.1/D24.2 are responsive-table-column work; D25 is the tab-strip polish.
