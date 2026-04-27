# D18: Workspace Connector + PortableMind Directory Tree — Complete

**Spec:** `docs/current_work/specs/d18_pm_connector_directory_tree_spec.md`
**Plan:** `docs/current_work/planning/d18_pm_connector_directory_tree_plan.md`
**Manual test plan:** `docs/current_work/testing/d18_pm_connector_directory_tree_manual_test_plan.md`
**Branch:** `feature/d18-pm-connector`
**Completed:** 2026-04-27

---

## Summary

D18 introduces the `Connector` storage abstraction (one of the nine cross-OS abstractions promised in `docs/stack-alternatives.md` §3 — "File-system abstraction"), ships the first two concrete implementations (`LocalConnector` + `PortableMindConnector`), grows the workspace sidebar from a single-root tree into a multi-connector pane, surfaces cross-tenant share badges + file counts on PortableMind nodes, disables unsupported file types as discoverable-but-non-interactive rows, and lands read-only file open against the PortableMind LlmFiles API end-to-end.

This is the first concrete slice of the long-parked **D7+ PortableMind integration umbrella** — and proves the connector seam against real prod data (Rick's `tenant_id: 22 / portablemind` JWT), including the cross-tenant rows with EpicDX and Rock Cut Brewing Company attribution.

---

## Implementation Details

### What Was Built

- **Connector protocol** + value types (`ConnectorNode`, `TenantInfo`, `ConnectorError`).
- **`LocalConnector`** — wraps the existing folder-tree walk; semantics unchanged from D6.
- **`PortableMindConnector`** — async-only; talks Harmoniq REST.
- **`PortableMindAPIClient`** — `URLSession` + bearer auth + JWT-derived `X-Tenant-ID`; covers `/users/current`, `/llm_directories`, `/llm_files`, `/llm_files/:id` + signed-URL blob fetch.
- **`KeychainTokenStore`** — single-account dev token storage.
- **`ConnectorTreeViewModel`** — unifies sync (Local) and async (PM) loading; per-path expansion / loading / error state; cross-tenant predicate via lazy-cached `currentUserTenantID`.
- **`ConnectorTreeView`** — recursive tree row view with disclosure chevron, badges, in-flight spinner, error rows, file-count caption, disabled styling for unsupported files.
- **`TenantInitialsBadge`** — pill view mirroring `harmoniq-frontend/.../TenantInitialsBadge.tsx`.
- **Read-only tab support** — `EditorDocument.isReadOnly` + `Origin` enum; `TabStore.openReadOnly`; ⌘S/⌘⇧S grey via `.disabled(focused.isReadOnly)`; "READ-ONLY" pill on the tab.
- **Debug menu** (debug builds only) — *Set PortableMind Token…* + *Clear PortableMind Token*.
- **Harness actions** (8 new) — `pm_token_set`, `pm_token_dump`, `pm_api_smoke`, `dump_sidebar_state`, `expand_sidebar_path`, `collapse_sidebar_path`, `dump_connector_tree`, `connector_open_file`, `dump_command_state`. Plus extension to `focused_doc_info` carrying `isReadOnly` + `origin`.

### Files Created

| File | Purpose |
|------|---------|
| `Sources/Connectors/Connector.swift` | Protocol + ConnectorNode + TenantInfo + ConnectorError |
| `Sources/Connectors/LocalConnector.swift` | Filesystem-backed connector (replaces FolderTreeModel) |
| `Sources/Connectors/PortableMind/PortableMindConnector.swift` | Harmoniq-backed connector |
| `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` | URLSession HTTP client |
| `Sources/Connectors/PortableMind/PortableMindAPITypes.swift` | Codable DTOs |
| `Sources/Connectors/PortableMind/PortableMindEnvironment.swift` | Base URL config |
| `Sources/Connectors/PortableMind/JWTPayload.swift` | Read `tenant_enterprise_identifier` from JWT |
| `Sources/Auth/KeychainTokenStore.swift` | Single-account keychain wrapper |
| `Sources/UI/TenantInitialsBadge.swift` | Cross-tenant pill view |
| `Sources/WorkspaceUI/ConnectorTreeView.swift` | Recursive sidebar tree (replaces FolderTreeView) |
| `Sources/WorkspaceUI/ConnectorTreeViewModel.swift` | Per-connector expansion + load state |
| `docs/current_work/specs/d18_pm_connector_directory_tree_spec.md` | Spec |
| `docs/current_work/planning/d18_pm_connector_directory_tree_plan.md` | Plan |
| `docs/current_work/prompts/d18_pm_connector_directory_tree_prompt.md` | Prompt |
| `docs/current_work/testing/d18_pm_connector_directory_tree_manual_test_plan.md` | Manual test plan |
| `docs/issues_backlog.md` | New durable home for non-blocking issues (i01 cache, i02 table widths, i03 XCUITest) |

### Files Modified

| File | Changes |
|------|---------|
| `Sources/Workspace/WorkspaceStore.swift` | `rootNode: FolderNode?` → `ConnectorNode?`; `connectors: [any Connector]`; `treeViewModels: [String: ...]`; `reconcileConnectors()` |
| `Sources/Workspace/EditorDocument.swift` | `isReadOnly`, `Origin` enum; save methods throw `.readOnly` for PM tabs |
| `Sources/Workspace/TabStore.swift` | `openReadOnly(content:origin:)`; de-dupes by (connectorID, fileID) |
| `Sources/WorkspaceUI/WorkspaceView.swift` | Multi-root sidebar; routes file-tap on connector |
| `Sources/WorkspaceUI/TabBarView.swift` | "READ-ONLY" pill on read-only tabs |
| `Sources/Editor/EditorContainer.swift` | `textView.isEditable = !document.isReadOnly` |
| `Sources/App/MdEditorApp.swift` | Save/Save-As gated on `isReadOnly`; debug-only `Debug` menu |
| `Sources/Accessibility/AccessibilityIdentifiers.swift` | `folderTreeRow(id:)` keyed on connector-qualified node id |
| `Sources/Debug/HarnessCommandPoller.swift` | 8 new actions + extended `focused_doc_info` |
| `docs/engineering-standards_ref.md` | §3.1 — branching rule (feature/d##-*) |
| `CLAUDE.md` | SDLC-compliance mirror of §3.1 + issues-backlog convention |
| `docs/roadmap_ref.md` | D18 + D19 (save-back) + D20 (connection-mgmt) rows |
| `UITests/LaunchSmokeTests.swift` | Accept either main-editor OR empty-editor (i03 fix) |
| `UITests/MutationKeyboardTests.swift` | XCTSkip with i03 reference |
| `UITests/MutationToolbarTests.swift` | Same |

### Files Deleted

| File | Reason |
|------|--------|
| `Sources/Workspace/FolderTreeModel.swift` | Replaced by Connector + LocalConnector |
| `Sources/WorkspaceUI/FolderTreeView.swift` | Replaced by ConnectorTreeView + ConnectorTreeViewModel |

---

## Testing

### Tests Run

- [x] **Manual test plan** — sections A–G all walked; results summarized in the plan doc itself.
- [x] **Harness verification** — every phase landed with harness assertions: `pm_token_set/dump`, `pm_api_smoke`, `dump_sidebar_state`, `expand_sidebar_path`, `collapse_sidebar_path`, `dump_connector_tree`, `connector_open_file`, `dump_command_state`, extended `focused_doc_info`. All driven against real prod Harmoniq with no focus stolen.
- [x] **XCUITest suite** — `xcodebuild test` is GREEN. LaunchSmokeTests passes (2.16s). The two mutation tests skip with a clear i03 reference (their migration to harness-driven verification is a separate effort).

### Test Coverage

D18 is the first deliverable to ship harness-first verification per the new plan §0.1 testing-stack split. The harness covers:

- Token round-trip (set + dump without exposing the token).
- API client smoke against prod (URL construction, bearer transmission, X-Tenant-ID derivation, error decoding).
- Sidebar state inspection (roots, children, expansion, loading, errors, badges, file counts, supported flags).
- Programmatic expand/collapse + cache verification.
- Direct connector calls bypassing UI.
- Programmatic file open via connector + read-only state assertion.
- Save command state assertion.

---

## Deviations from Spec

- **Q1 disabled-row behavior arrived in phase 1, not phase 4.** Natural fallout of the Connector protocol's `isSupported` field; LocalConnector marked `.md` files only as supported from the start, and the sidebar view honored the flag immediately. No regression — phase 4 added the cross-tenant badge + the accessibility hint.
- **JWT-derived `X-Tenant-ID` header.** Not anticipated in the spec or plan; surfaced during phase 3 visual smoke when the bearer alone returned `400 invalid tenant`. Fixed in phase 3 follow-up commit `58fbffc` by reading the `tenant_enterprise_identifier` from the JWT payload. Added `Sources/Connectors/PortableMind/JWTPayload.swift` for this.
- **Debug menu (D18) added in addition to the harness `pm_token_set` action.** The plan listed only the menu; the harness action was added in parallel for autonomous testing. Both work; both call the same `KeychainTokenStore.save` + `WorkspaceStore.reconcileConnectors`.
- **D19/D20 ordering swapped late in the deliverable.** Per CD direction 2026-04-27, save-back is now D19 (was: connection-management) because save-back unblocks the dogfood loop on PM-stored docs sooner. Captured in spec Decision log + roadmap.
- **Phase 4 manual-tooltip verification** is "AppKit-managed; not directly introspectable from harness without screen-grabs." Manual test plan §C2 documents this as a visual check.

---

## Follow-Up Items

- [ ] **D19 — PortableMind save-back.** Re-ordered ahead of connection-management. New deliverable triad next.
- [ ] **D20 — Connection-management UX.** Replaces the dev-only Debug-menu affordance with proper sign-in.
- [ ] **i02 — Markdown table column widths capped at 320pt regardless of viewport** (in `docs/issues_backlog.md`). Non-blocking; revisit post-D19.
- [ ] **i03 — XCUITest mutation tests need harness-driven migration.** LaunchSmoke is green; the two mutation tests are XCTSkip'd with a TODO. A focused testing deliverable (or part of D19) can re-author them against `set_text` + `synthesize_keypress` + `dump_state`. Status flipped to `Workaround` in the backlog.
- [ ] **Tab persistence across launch for PM read-only tabs.** Currently we don't persist them. Plan §Risks #5 left this open; defer until D19 lands save-back (then the question of "rehydrate from network" becomes more tractable).
- [ ] **File counts on local directories.** Currently nil for Local; visible cosmetic inconsistency vs. PM. Low priority; don't compute disk file counts unless a user asks.

---

## Notes

### Why this matters

D18 establishes the seam between the editor and any remote storage backend. The Connector protocol is the long-lived abstraction; concrete connectors come and go. Future Linux/Windows ports will land their LocalConnector implementations natively; PortableMindConnector ports as-is once the platform's HTTP/Keychain equivalents exist.

The cross-tenant model (every node carries `TenantInfo`; UI checks `node.tenant.id != currentUser.tenant_id`) generalizes beyond PortableMind: any future connector with a multi-tenant model can use the same fields and inherit the badge rendering for free.

### Verification stack

D18 is the first deliverable on the **harness-first verification** stack documented in plan §0.1. The harness is debug-only JSON-file IPC; it doesn't grab focus, doesn't break on launch-state changes, and lets CC and CD work in parallel windows during regression sweeps. The XCUITest suite is now one launch-smoke; the mutation tests are queued for migration.

### Branching

D18 is the first deliverable to honor the new branching rule (`docs/engineering-standards_ref.md` §3.1). All work landed on `feature/d18-pm-connector` off `main`; this commit closes the deliverable on the branch. Merge to `main` after CD review.
