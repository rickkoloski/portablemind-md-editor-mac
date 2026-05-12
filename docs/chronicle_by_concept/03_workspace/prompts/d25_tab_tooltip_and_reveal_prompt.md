# D25 Prompt — Tab tooltip + Reveal in File Tree

You are working on `~/src/apps/md-editor-mac` on branch `feature/d25-tab-tooltip-and-reveal`. Your job is to ship two small enhancements that close the dogfood-discovered papercuts on the tab strip:

1. **Hover tooltip** on each tab showing the full canonical path.
2. **Right-click → Reveal in File Tree** that expands the sidebar tree's ancestors and scrolls to the file's row. Files outside any open tree get a stock NSAlert.

D22 shipped Copy Path / Copy Relative Path on tabs and explicitly deferred Reveal-in-Sidebar; D25 is that follow-up. Pulled forward because the editor has become Rick's daily-driver and the missing Reveal is felt on every "where is this file in the tree?" check.

---

## Read first (in this order)

1. `docs/current_work/specs/d25_tab_tooltip_and_reveal_spec.md` — the contract. Q1–Q6 are answered up front.
2. `docs/current_work/planning/d25_tab_tooltip_and_reveal_plan.md` — the two-phase plan with file-by-file touchpoints.
3. `Sources/WorkspaceUI/TabBarView.swift` — the tab UI you're modifying. The outer Button + inner close Button + existing context menu (Copy Path / Copy Relative Path) is the surface.
4. `Sources/WorkspaceUI/PathFormatting.swift` — already has `absolutePathForCopy(doc)` for the tooltip text. Reuse it.
5. `Sources/Workspace/WorkspaceStore.swift` — add `pendingRevealNodeID` + `revealInTree(document:)` here (mirroring the D23 `requestSaveAs` / `dismissSaveAs` pattern).
6. `Sources/WorkspaceUI/WorkspaceView.swift` — wrap the existing `ScrollView` in a `ScrollViewReader`. Add `.onChange(of: workspace.pendingRevealNodeID)`.
7. `Sources/WorkspaceUI/ConnectorTreeViewModel.swift` — `expand(path:)` is already async-safe and idempotent. Just call it for each ancestor.
8. `docs/engineering-standards_ref.md` §2.1 — `accessibilityIdentifier` on the new menu item.

---

## Phase guidance

### Phase 1 — tooltip

One-line change: add `.help(tabTooltip)` to the outer `Button` in `TabItemView`. Compute `tabTooltip` from `PathFormatting.absolutePathForCopy(document) ?? ""` (empty string suppresses the tooltip; SwiftUI honors that).

Verify in the live editor:
- Local tab inside home → `~/src/.../foo.md`.
- Local tab outside home → absolute path.
- PM tab → `/Sales & Marketing/foo.md`-style displayPath.
- Untitled local tab → no tooltip.

Commit: `D25 phase 1 — tab hover tooltip`.

### Phase 2 — Reveal in File Tree

Add to `WorkspaceStore`:

```swift
@Published var pendingRevealNodeID: String? = nil

func revealInTree(document: EditorDocument) async {
    // Resolve which connector owns this doc's path.
    // PM:    connectorNode.id (already shape "portablemind:file:N").
    // Local: "local:\(url.path)" — verify url.path is under
    //        local connector's rootNode.path.
    // No match → outsideTreeAlert(for:) and return.
    //
    // Walk ancestors top-down; for each, await viewModel.expand(path:).
    // Sleep 50ms so SwiftUI renders the new rows.
    // Set pendingRevealNodeID = target.
}

func clearReveal() { pendingRevealNodeID = nil }
```

Outside-tree alert:

```swift
private func outsideTreeAlert(for document: EditorDocument) {
    let alert = NSAlert()
    alert.messageText = "This file is outside currently open directories"
    alert.informativeText = PathFormatting.absolutePathForCopy(document)
        ?? document.displayName
    alert.runModal()
}
```

Wrap WorkspaceView's sidebar in `ScrollViewReader { proxy in ... }` and:

```swift
.onChange(of: workspace.pendingRevealNodeID) { newValue in
    guard let id = newValue else { return }
    withAnimation { proxy.scrollTo(id, anchor: .center) }
    workspace.clearReveal()
}
```

Add the menu item in `TabItemView.contextMenu`:

```swift
Divider()
Button("Reveal in File Tree") {
    Task { @MainActor in
        await WorkspaceStore.shared.revealInTree(document: document)
    }
}
.accessibilityIdentifier(AccessibilityIdentifiers.tabReveal(documentID: document.id))
```

Add identifier in `AccessibilityIdentifiers.swift`:

```swift
static func tabReveal(documentID: UUID) -> String {
    "md-editor.tabs.reveal:\(documentID.uuidString)"
}
```

Verify all four outside-tree paths (Local-outside-workspace, no-workspace + PM tab, PM-token-cleared, Untitled) show the alert with the right path.

Commit: `D25 phase 2 — Reveal in File Tree`.

### Phase 3 — close-out

Manual test plan with one recipe per AC. COMPLETE doc references spec / plan / prompt. Roadmap row added; D22's "Reveal-in-Sidebar deferred" line marked resolved. ff-merge to `main`. Tag `v0.7.1`.

---

## Conventions

- Branch: `feature/d25-tab-tooltip-and-reveal` (already created).
- Commits: one per phase.
- Engineering-standards §2.1: every interactive element gets an accessibility identifier.
- Markdown dogfood markers (`**Question:**`, etc.) for any open question that surfaces during build.

---

## Done means

1. Phase 1 + 2 complete; one commit per phase.
2. Tab hover tooltip surfaces full path on both Local and PM tabs.
3. "Reveal in File Tree" expands ancestors + scrolls to row for both connector types.
4. Outside-tree cases (4 of them) surface the NSAlert with the full path.
5. `xcodebuild test` GREEN; D17 / D19 / D23 manual test plans unchanged.
6. Manual test plan walked end-to-end with results recorded.
7. COMPLETE doc references spec / plan / prompt / manual test plan.
8. Roadmap reflects D25 ✅; D22's "Reveal-in-Sidebar deferred" marked resolved.
9. Branch ff-merged to `main`; tag `v0.7.1` annotated and pushed.
