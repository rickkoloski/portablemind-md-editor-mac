# D25 — Implementation plan

**Spec:** `docs/current_work/specs/d25_tab_tooltip_and_reveal_spec.md`
**Branch:** `feature/d25-tab-tooltip-and-reveal` (already cut from `main`).

Two phases. Both are SwiftUI/AppKit only — no backend changes.

---

## Phase 1 — Tab hover tooltip (small)

**Goal:** hovering a tab surfaces the full canonical path.

### Touchpoints

| File | Change |
|---|---|
| `Sources/WorkspaceUI/TabBarView.swift` | Add `.help(tabTooltip)` on the outer `Button(action: onFocus)` of `TabItemView`. |

### Detail

```swift
private var tabTooltip: String {
    PathFormatting.absolutePathForCopy(document) ?? ""
}
```

`.help("")` on macOS suppresses the tooltip; non-empty surfaces it. SwiftUI's `.help(_:)` accepts `LocalizedStringKey` or `String`; the `String` overload handles dynamic text correctly.

### DOD

- Hover delay matches stock macOS tooltip delay.
- Local tab inside home → tooltip shows `~/src/.../foo.md`.
- Local tab outside home → tooltip shows full absolute path.
- PM tab → tooltip shows displayPath (`/Sales & Marketing/foo.md`).
- Untitled local tab → no tooltip.
- Build clean.
- Live-editor smoke: open one local + one PM tab, hover both, confirm both tooltips.
- Commit: `D25 phase 1 — tab hover tooltip`.

---

## Phase 2 — Reveal in File Tree

**Goal:** right-click any tab → menu item that expands ancestors in the sidebar tree and scrolls to the file's row. Outside-tree case → NSAlert.

### Touchpoints

| File | Change |
|---|---|
| `Sources/Workspace/WorkspaceStore.swift` | Add `@Published var pendingRevealNodeID: String? = nil`. Add `func revealInTree(document:) async`. Add `func clearReveal()`. |
| `Sources/WorkspaceUI/WorkspaceView.swift` | Wrap `ScrollView` content in `ScrollViewReader { proxy in ... }`. Add `.onChange(of: workspace.pendingRevealNodeID)` that scrolls + clears. |
| `Sources/WorkspaceUI/TabBarView.swift` | Add "Reveal in File Tree" item to the tab's `.contextMenu`. |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | `tabReveal(documentID:) -> String`. |

### `WorkspaceStore.revealInTree(document:)`

Pseudocode:
```swift
@MainActor
func revealInTree(document: EditorDocument) async {
    guard let (model, targetNodeID, ancestorPaths) = resolveRevealTarget(for: document)
    else {
        outsideTreeAlert(for: document)
        return
    }
    for path in ancestorPaths {
        await model.expand(path: path)
    }
    // Let SwiftUI render the freshly-expanded rows before scrolling.
    try? await Task.sleep(nanoseconds: 50_000_000)
    pendingRevealNodeID = targetNodeID
}
```

`resolveRevealTarget(for:)`:
- PM tab: pull `connectorNode.id` (already correct shape `portablemind:file:1234`); find the `PortableMindConnector`'s tree view-model.
- Local tab: build `targetNodeID = "local:\(url.path)"`; find `LocalConnector` view-model; verify `url.path` is under `connector.rootNode.path`.
- Walk ancestors: starting from connector root, accumulate `rootPath`, then each intermediate dir up to (but not including) the file itself.
- If no matching connector OR path is outside the connector's tree → return nil.

`outsideTreeAlert(for:)`:
```swift
let alert = NSAlert()
alert.messageText = "This file is outside currently open directories"
alert.informativeText = pathForAlert(document) ?? document.displayName
alert.runModal()
```

### Scroll mechanism

```swift
ScrollViewReader { proxy in
    ScrollView { ... existing ... }
        .onChange(of: workspace.pendingRevealNodeID) { newValue in
            guard let id = newValue else { return }
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            workspace.clearReveal()
        }
}
```

The 50ms sleep in `revealInTree` lets the freshly-expanded rows render before `pendingRevealNodeID` becomes non-nil. `proxy.scrollTo` finds the row by its ForEach-`id: \.id` identity (which is `node.id`).

### Outside-tree cases verified

1. Local file opened from outside the workspace root: `LocalConnector` is loaded but `url.path` doesn't have the workspace prefix → alert.
2. Local file but no workspace at all: `connectors` is empty (or has only PM) → no `LocalConnector` → alert.
3. PM tab with no PM connector loaded (token cleared after open): `PortableMindConnector` not in `connectors` → alert.
4. Untitled tab (no `url`, no `connectorNode`): would resolve to neither → alert with `displayName` ("Untitled").

### DOD

- Right-click tab → "Reveal in File Tree" appears as a menu item between Copy Relative Path and end of menu (with a `Divider()` above it).
- Local tab inside workspace → tree expands ancestors + scrolls to row. Manual smoke: open `docs/foo/bar.md`; reveal scrolls to `bar.md` row with `foo/` expanded.
- PM tab → PM tree expands ancestors (each loads asynchronously, see spinner) + scrolls to file row.
- Outside-tree cases (4 above) → NSAlert with full path or "Untitled".
- Build clean; `xcodebuild test` GREEN.
- Commit: `D25 phase 2 — Reveal in File Tree`.

---

## Phase 3 — Close-out

| Artifact | Purpose |
|---|---|
| `docs/current_work/testing/d25_tab_tooltip_and_reveal_manual_test_plan.md` | Walkthrough recipes per AC. |
| `docs/current_work/stepwise_results/d25_tab_tooltip_and_reveal_COMPLETE.md` | Close-out doc. |
| `docs/roadmap_ref.md` | New row D25, mark D22's "Reveal-in-Sidebar deferred" line as resolved. |

Merge to `main`; tag `v0.7.1` (patch — UX polish on top of v0.7).

---

## Risks

1. **50ms sleep is brittle.** If a deeply-nested file's tree level takes longer to render than 50ms, the scroll may target a not-yet-laid-out row. Fallback if observed in smoke: switch to `.task(id: pendingRevealNodeID)` modifier inside the sidebar (runs after body re-evaluates) and remove the sleep.
2. **`.help()` on a Button.** SwiftUI macOS shows tooltips for `.help()` on most container modifiers; verified working in `TabItemView` already (the warning triangle uses `.help(...)`). The outer Button should accept `.help()` too — if not, fallback is a `.background(... NSViewRepresentable for trackingArea)`.
3. **Local connector ancestor cache.** `LocalConnector.childrenSync(of:)` always returns sync data, so `model.expand(path:)` for a local ancestor is a no-op (no async load needed) — just toggles `expanded`. Confirmed by re-reading `ConnectorTreeViewModel.expand(path:)`.
