# D23 Plan — PortableMind file management

**Spec:** `docs/current_work/specs/d23_pm_file_management_spec.md`
**Created:** 2026-05-07
**Branch:** `feature/d23-pm-file-management`

---

## 0. Approach

Six phases. Phase 1 is an API + protocol spike (gates the deliverable on the model_api endpoint surface). Phases 2-5 ship one operation each; the tree picker built in phase 2 is reused. Phase 6 closes the deliverable.

1. **API + protocol spike.** Confirm model_api endpoints; extend `Connector` protocol; extend `PortableMindAPIClient` with the new methods.
2. **Save As (modal + tree picker + connector wiring).** Replaces the "unsupported" alert.
3. **New File (reuses Save As modal).** New menu item, ⌘⌥N, empty buffer.
4. **Rename (sidebar inline edit + connector wiring).**
5. **Move (sidebar context menu → tree picker modal → connector wiring).**
6. **Manual test plan + COMPLETE + roadmap.**

Each phase ends in a commit. Stop and surface a `**Question:**` if a phase reveals scope drift.

---

## 0.1 Verification approach

Continues the harness-first pattern from D18/D19/D24:
- Phase 1 spike: model_api endpoint reconnaissance + a small Swift integration test against the local Harmoniq dev instance (or a stubbed `URLProtocol` if the local instance isn't running).
- Phases 2-5: each adds a harness action that exercises the operation end-to-end without going through the UI modal (`pm_save_as`, `pm_new_file`, `pm_rename`, `pm_move`). The UI modal's controller calls the same shared service the harness action does.
- Phase 6: D17 + D19 manual test plans rerun. New manual test plan covers D23-specific scenarios.

---

## Phase 1 — API + protocol spike

**Goal:** Confirm what `/api/v1/llm_files` and `/api/v1/llm_directories` accept on the server side. Extend the `Connector` protocol and `PortableMindAPIClient` with the new methods so phases 2-5 can wire UI without re-discovering the API shape.

**Spike:**

- Read `reference-code/model_api/app/controllers/api/v1/llm_files_controller.rb` (and any associated services) to enumerate the existing endpoints. Likely candidates:
  - `POST /api/v1/llm_files` — create with `llm_directory_id`, `name`, multipart content (mirrors the upload pattern). Body shape per controller.
  - `PATCH /api/v1/llm_files/:id` — already used for save (D19). Likely also accepts `name` and `llm_directory_id` for rename/move; verify.
- Read `reference-code/model_api/app/controllers/api/v1/llm_directories_controller.rb` to confirm the directory tree endpoint covers everything we need for the tree picker (likely yes — D18 already uses it).
- For each missing endpoint: surface as a backend dependency in `docs/current_work/issues/d23_pm_file_management_BLOCKED.md`. Don't block phase 2 indefinitely — if the gap is small, file a model_api PR alongside; if it's large, escalate to CD.

**Files updated:**

- `Sources/Connectors/Connector.swift` — extend the protocol:
  ```swift
  /// Create a new file at `parent`/`name` with `bytes`. Returns the
  /// resulting node. Connectors that don't support creation throw
  /// `.unsupported`.
  func createFile(in parent: ConnectorNode,
                  name: String,
                  bytes: Data) async throws -> ConnectorNode

  /// Rename `node` to `newName` (same parent directory). Returns the
  /// refreshed node.
  func renameFile(_ node: ConnectorNode,
                  to newName: String) async throws -> ConnectorNode

  /// Move `node` to `newParent`. Returns the refreshed node.
  func moveFile(_ node: ConnectorNode,
                to newParent: ConnectorNode) async throws -> ConnectorNode
  ```
  Default implementations throw `.unsupported`. `LocalConnector` provides FileManager-backed implementations. `PortableMindConnector` provides API-backed implementations.

- `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` — new methods mirroring `updateFile`'s shape (path-based per spec Q9 correction):
  ```swift
  func createFile(directoryPath: String, name: String, bytes: Data) async throws -> LlmFile
  func renameFile(fileID: Int, newName: String) async throws -> LlmFile
  func moveFile(fileID: Int, newDirectoryPath: String) async throws -> LlmFile
  ```

- `Sources/Connectors/PortableMind/PortableMindConnector.swift` — implement the protocol methods; populate the cached tree with the new/changed nodes.

- `Sources/Connectors/LocalConnector.swift` — implement using `FileManager` (`createFile(atPath:)`, `moveItem(at:to:)` for both rename and move). Local rename = move within same parent.

**Cache mutation:** the connector exposes (per Q7):
```swift
/// D23 — splice a new/updated node into the cached tree. The sidebar
/// observer re-renders. Caller is responsible for ensuring `node`'s
/// parent path matches the location implied by the operation.
func upsertNode(_ node: ConnectorNode)

/// D23 — remove a node from the cached tree.
func removeNode(_ nodeID: String)
```

(Or equivalent — exact API shape decided in phase 1 once we see the cache layout.)

**Harness:** no new actions yet. Phase 2 adds the first one.

**DOD:**

- Build clean.
- Spike `BLOCKED.md` exists if any model_api endpoint is missing; otherwise document the endpoints in the spike result (deletable note inline, or a `spikes/d23_api_recon/README.md`).
- Existing 23 unit tests still pass.
- D17 + D19 manual test plans rerun GREEN.

**Commit:** `D23 phase 1 — API spike + Connector protocol extensions`

---

## Phase 2 — Save As (modal + tree picker)

**Goal:** Replace the "Save As not yet supported" alert. Build the reusable tree picker UI; wire to `Connector.createFile`.

**Files created:**

- `Sources/UI/PickConnectorTreeView.swift` — SwiftUI / AppKit view that displays a connector's directory tree with disclosure + selection. Selection state binds to `@State var selectedDirectory: ConnectorNode?`.
- `Sources/UI/SaveAsModal.swift` — the modal. Filename text field, connector picker (segmented control), tree picker view, Save / Cancel buttons. Shows inline errors. Accessibility identifiers per engineering-standards §2.1.
- `Sources/Workspace/PMFileOperations.swift` — shared service the modal AND the harness call. Wraps `connector.createFile` + tab-lifecycle handling (per Q2: switch existing tab to new node).

**Files updated:**

- `Sources/App/MdEditorApp.swift::saveAsFocused()` — replaces the PM-branch alert with `SaveAsModalController.present(for: doc)`. Local-tab branch unchanged (NSSavePanel still works).
- `Sources/Workspace/EditorDocument.swift` — adds a small mutator so the document's `connectorNode` and `url` can be replaced after Save As. Buffer + dirty state preserved (the new file's content matches the buffer at save time).

**Harness actions added:**

- `pm_save_as` `{tabId, parentNodeID, name}` — creates a new PM file via the same code path the modal uses; on success, switches the focused tab. Result file emits the new node's id + path.

**DOD:**

- ⌘⇧S on a PM tab opens the modal (replaces the alert).
- Save As completes successfully against the local Harmoniq instance (manual smoke).
- The current tab now points at the new file; buffer / caret / scroll preserved.
- Sidebar tree picks up the new node without a full refetch.
- Inline error surfaces for: network failure, write-forbidden, quota exceeded, name conflict.
- D17 + D19 manual test plans rerun GREEN.

**Commit:** `D23 phase 2 — Save As (PM tab) modal + tree picker + connector wiring`

---

## Phase 3 — New File

**Goal:** Add File → New PortableMind File… menu item and ⌘⌥N shortcut. Reuse the Save As modal with a different initial state (empty buffer, default filename "Untitled.md").

**Files updated:**

- `Sources/App/MdEditorApp.swift` — add the menu item + keyboard shortcut. Calls `PMFileOperations.newFile(...)` which presents the same modal as Save As but with empty initial bytes.
- `Sources/Workspace/PMFileOperations.swift` — add `newFile(in: connector)` entry point. After successful create, opens a new tab pointed at the new node.
- `Sources/UI/SaveAsModal.swift` — accepts an `intent: .saveAs | .newFile` parameter; the title bar text and default filename change accordingly.

**Harness actions added:**

- `pm_new_file` `{connectorID, parentNodeID, name, bytes}` — creates a new file and opens it as a new tab. Result file emits the new node's id + path.

**DOD:**

- ⌘⌥N opens the modal in "New File" mode (empty buffer, default filename "Untitled.md").
- Successful create opens a new tab pointed at the new file.
- Buffer is empty. Tab is focused.

**Commit:** `D23 phase 3 — New PortableMind File`

---

## Phase 4 — Rename

**Goal:** Sidebar inline rename for PM files. Right-click → Rename or F2. Wires to `Connector.renameFile`.

**Files updated:**

- `Sources/Workspace/SidebarView.swift` (or wherever the file-tree row is rendered): add a rename mode to the row view. The row's name label becomes a `TextField` when the row is in rename mode. ⏎ commits, ⎋ cancels. Accessibility identifier on the rename TextField.
- Sidebar context menu: add "Rename" item for PM file rows. Wired to enter rename mode.
- `Sources/Workspace/PMFileOperations.swift` — add `rename(node: ConnectorNode, to: String) async throws -> ConnectorNode`. After success, calls `connector.upsertNode(refreshedNode)` and updates any open tabs whose `connectorNode.id` matches.
- F2 keyboard shortcut on selected PM file row → enter rename mode.

**Harness actions added:**

- `pm_rename` `{nodeID, newName}` — renames via the same code path; result file emits the refreshed node.

**DOD:**

- Right-click → Rename works for PM files.
- F2 works on a selected PM file.
- The TextField focuses, prepopulated with current name; ⏎ commits, ⎋ cancels.
- Server PATCH succeeds; sidebar refreshes the row name; if the file is open, the tab title updates and `EditorDocument.connectorNode` is replaced (refreshed node from server).
- Buffer + caret + scroll preserved.
- Inline error feedback for invalid names (empty, contains `/`) and server errors (network, write-forbidden, name conflict).

**Commit:** `D23 phase 4 — Rename PM file (sidebar inline edit + connector)`

---

## Phase 5 — Move

**Goal:** Sidebar context menu → "Move to…" → tree picker modal → `Connector.moveFile`.

**Files created:**

- `Sources/UI/MoveFileModal.swift` — variant of SaveAsModal with the filename field hidden (rename happens elsewhere) and Save labeled "Move".

**Files updated:**

- Sidebar context menu: add "Move to…" item for PM file rows.
- `Sources/Workspace/PMFileOperations.swift` — add `move(node: ConnectorNode, to newParent: ConnectorNode) async throws -> ConnectorNode`. Calls `connector.moveFile(...)` and updates the cached tree (remove from old parent, upsert under new parent). Updates any open tabs.

**Harness actions added:**

- `pm_move` `{nodeID, newParentNodeID}` — moves via the same code path; result file emits the refreshed node.

**DOD:**

- Right-click → Move to… opens the modal with the tree picker.
- User selects a target directory; Save commits the move.
- Server PATCH (with `llm_directory_id`) succeeds; sidebar tree updates (node disappears from old parent, appears under new parent); open tabs update.
- Buffer + caret + scroll preserved.
- Inline error feedback for: same-directory selected (no-op), name conflict in target, server errors.

**Commit:** `D23 phase 5 — Move PM file (context menu + tree picker + connector)`

---

## Phase 6 — Manual test plan + COMPLETE + roadmap

**Goal:** Close the deliverable.

**Files created:**

- `docs/current_work/testing/d23_pm_file_management_manual_test_plan.md` — Save As, New File, Rename, Move, each × success / error scenarios. Harness-recipe blocks for each scenario.
- `docs/current_work/stepwise_results/d23_pm_file_management_COMPLETE.md` — completion record.

**Files updated:**

- `docs/roadmap_ref.md` — D23 marked Complete; change-log entry.

**DOD:**

- Manual test plan walked end-to-end against local Harmoniq.
- COMPLETE doc references spec, plan, prompt, manual test plan, harness actions added.
- D17 + D19 manual test plans GREEN.
- `xcodebuild test` GREEN — MdEditorUnitTests 23+ tests still pass (D23 doesn't add unit tests beyond harness coverage; the connector additions are integration-tested via the harness).
- Roadmap reflects D23 ✅; D20 stays Pending.

**Commit:** `D23 phase 6 — manual test plan + COMPLETE + roadmap`

---

## Risks / open implementation questions

1. **API endpoint coverage (phase 1).** Critical-path risk. If `POST /api/v1/llm_files` requires fields we don't have or doesn't accept the format we expect, phase 2 is blocked until backend ships. Mitigation: phase 1 spike resolves this before any UI work.
2. **Tree picker reuse and scope creep.** v1 picker is straight tree. Resist temptation to add search / favorites / recents until dogfood asks. Phase 2's `PickConnectorTreeView.swift` is intentionally small.
3. **Sidebar inline-rename TextField focus management.** SwiftUI's TextField focus inside a List row historically has accessibility-identifier and first-responder issues (D2-era engineering-standards §2.1 lessons). Phase 4 may need to drop to AppKit `NSTextField` for the rename mode.
4. **Concurrent-edit safety on rename/move.** D19's conflict-detection only fires on save. If a third party renames the same file while it's open, the editor's `connectorNode` becomes stale. Detection on next save → existing `.conflictDetected` path. Acceptable for v1.
5. **Cache invalidation correctness.** Q7's "splice the new/updated node into the cached tree" must keep the tree's expand state consistent. If the user has the target directory collapsed when a move happens, does the move-target stay collapsed? Yes — we just splice; UI doesn't auto-expand. (Could be a future ergonomic — auto-expand to reveal the moved file.)
6. **i04 stopgap interaction.** D23 calls `PortableMindAPIClient` which uses the bearer token loaded by `Sources/Auth/KeychainTokenStore.swift` (currently file-based per i04). No D23-specific token concerns.
7. **D20 dependency.** None. D23 doesn't need connection-management; the existing single-token Debug-menu flow keeps working. When D20 ships and supports multiple connections, the Save As modal's connector-picker dropdown will pick up multiple PM connections automatically.
