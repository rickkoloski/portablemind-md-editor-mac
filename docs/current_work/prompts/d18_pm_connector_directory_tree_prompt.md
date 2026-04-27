# D18 Prompt — Workspace connector + PortableMind directory tree

You are working on `~/src/apps/md-editor-mac`. Your job is to build the first concrete slice of the long-parked D7+ PortableMind integration: a `Connector` storage abstraction, a PortableMind connector that talks to Harmoniq's REST API, and a sidebar that shows both Local and PortableMind tree roots side-by-side. Read-only file open is included; write-back is **out of scope** (deferred per spec § Out of scope).

This is a **foundational architecture deliverable** plus a visible UI milestone. The protocol you introduce here is the editor's first cross-OS abstraction (`stack-alternatives.md` §3 abstraction #3 "File-system abstraction") — design the seams carefully because every future remote-storage connector (and the Linux/Windows ports) will land behind this protocol.

---

## Read first (in this order)

1. `docs/current_work/specs/d18_pm_connector_directory_tree_spec.md` — the contract. Decision log captures the four scope answers (CD-approved 2026-04-27).
2. `docs/current_work/planning/d18_pm_connector_directory_tree_plan.md` — six phases, DOD per phase, file-by-file changes.
3. `docs/vision.md` + `docs/portablemind-positioning.md` — the why.
4. `docs/stack-alternatives.md` §3 — context on the cross-OS abstraction list this protocol joins.
5. `docs/engineering-standards_ref.md` — accessibility identifiers, localizable strings, never opt back into TK2.
6. `docs/issues_backlog.md` — read i01 (Read-tool cache misreport) before doing save-roundtrip verification; use `Bash grep`/`stat` not `Read` when the user has just typed in the editor.
7. Memory pointers (in `~/.claude/projects/-Users-richardkoloski-src/memory/`):
   - `feedback_no_shortcuts_pre_users.md` — build the hard thing right; no compat fallbacks.
   - `md_editor_dogfood_workflow.md` — `**Question:**` / `**Decision:**` markers on their own line; permanent `## Open questions` section + `## Decision log` table.
   - `harmoniq_mcp_points_at_prod.md` — Harmoniq prod is `www.dsiloed.com`; localhost is for code iteration.
   - `harmoniq_seed_test_credentials.md` — seed test users available on localhost.

---

## Reference code (don't import, mirror)

The harmoniq frontend has a working version of every UI behavior we need to mirror. Read these for shape:

- `~/src/apps/harmoniq/harmoniq-frontend/src/apps/file-artifact/components/DirectoryTree.tsx` — lazy-load pattern, expand state, badge predicate, count rendering.
- `~/src/apps/harmoniq/harmoniq-frontend/src/components/shared/TenantInitialsBadge.tsx` — initials algorithm, colors (`#FCE4EC` bg / `#E5007E` fg), tooltip behavior.
- `~/src/apps/harmoniq/reference-code/model_api/app/controllers/api/v1/llm_directories_controller.rb` (and `llm_files_controller.rb`) — endpoint shapes, params, response envelope.
- `~/src/apps/harmoniq/reference-code/model_api/app/models/llm_directory.rb` and `llm_file.rb` — field names, sharing/tenant fields.

Don't import or vendor any of this. Mirror the pattern in Swift.

---

## Where to work

Production code in `Sources/`. The plan creates these new directories:

- `Sources/Connectors/` — the protocol, `LocalConnector.swift`, and a `PortableMind/` subdir for the PM-specific files.
- `Sources/Auth/` — `KeychainTokenStore.swift`.
- `Sources/UI/` — `TenantInitialsBadge.swift` (or co-locate under a sidebar-specific path if one exists).

`xcodegen generate` after adding/removing files. Build with `source scripts/env.sh && xcodebuild -project MdEditor.xcodeproj -scheme MdEditor -configuration Debug -derivedDataPath ./.build-xcode build`.

---

## How to work

Follow the six phases in the plan **in order**. Each phase ends in a buildable + smokeable + committable state.

Per phase:
1. Read the phase's "New files" / "Files updated" / "DOD".
2. Make the change.
3. Build.
4. Run the smoke for that phase's DOD (open the app, click around, check the relevant behavior).
5. Commit per the message in the plan; one-line `STATUS.md` entry if you create one for the deliverable (optional — only useful if you expect interruption).

If a phase's DOD doesn't go GREEN, don't paper over with workarounds. Stop and surface a `**Question:**` per the dogfood convention. The plan flags the implementation questions I already know about (§ Risks); raise new ones as they arise.

---

## Critical: the protocol shape is the contract

The `Connector` protocol is the long-lived abstraction; concrete implementations come and go. Get the protocol right.

- **Async by default.** Even Local IO is async in the protocol so PM (network) and Local (disk) share a call site.
- **Path semantics are connector-defined.** The protocol takes opaque `String` paths; meanings are documented per implementation. Don't try to unify URL and `/projects/2024/docs` into one path type — they're different namespaces.
- **No leaky abstractions.** The sidebar view should not branch on `connector is PortableMindConnector`. Anything PM-specific (badges, file counts) lives on `ConnectorNode` fields that any connector can populate (`tenant: TenantInfo?`, `fileCount: Int?`).
- **Errors are typed.** `ConnectorError` carries enough information for inline error rows; don't `throw NSError` from connector code.

If you find yourself wanting to add a connector-specific method to the protocol, **stop and surface a `**Question:**`**. That's a sign the protocol design is leaking.

---

## Critical: Harmoniq API is prod by default

Memory `harmoniq_mcp_points_at_prod.md` is binding here too. Default base URL = `https://www.dsiloed.com/api/v1`. Override via `UserDefaults` key `PortableMindBaseURL` for localhost/staging. **Default to localhost during D18 development to avoid touching production data while building**, then flip back to prod for final smoke before COMPLETE. Document the override in the COMPLETE doc.

The dev token-seeding flow (Debug menu in debug builds, or `security add-generic-password` from CLI) is captured in the plan and must be repeated in the COMPLETE doc — D19 will replace it with proper sign-in UI.

---

## Visible-milestone discipline

The "first visible milestone" framing in the spec matters: by end of phase 3, **the user opens the app and sees a PortableMind root in the sidebar that they can expand and navigate**, even if no files have been opened yet. Phases 4–5 enrich; phase 3 is the demo-able beat.

Resist the urge to land phases 4–5 before phase 3's UI is polished enough to show. If phase 3 looks rough, dwell there.

---

## Manual test plan

Plan § Phase 6 sketches the test plan structure (§A–§G). Output goes in `docs/current_work/testing/d18_pm_connector_directory_tree_manual_test_plan.md`.

Per `feedback_manual_test_plans.md`, the manual test plan is a first-class SDLC artifact. Don't skip it. After D18 ships it'll likely graduate to XCUITest for the deterministic parts (sidebar structure, badge presence on cross-tenant rows, disabled-row behavior); the manual plan stays.

---

## Issues backlog

If you trip over anything non-blocking during implementation, append it to `docs/issues_backlog.md` with the next available `i##` ID. The cache-misreport one (i01) is already there; future entries follow the same H2 / fields-table shape. Keeps the deliverable focused.

---

## What NOT to do

- Don't add write-back. PM tab is `isReadOnly = true`. Save commands disabled. Write-back is the **next deliverable** after D19.
- Don't build the sign-in UI. Token comes from Keychain (debug menu or `security` CLI). Sign-in is **D19's job**.
- Don't try to make the PM tree behave exactly like Finder (drag-and-drop between roots, etc.) — out of scope.
- Don't filter unsupported files OUT of the tree. They show as **disabled rows with a tooltip** (Q1 decision). Hiding them would lose discovery affordance.
- Don't poll the PM API. Lazy-load on expand only. (PM-side file watching is a future deliverable.)
- Don't cache file content on disk. Read-only tabs hold content in memory; closing the tab releases it.

---

## When you finish a phase

End-of-phase status update (one or two sentences) so CD can sanity-check progress without reading the diff:

> **Phase N complete:** <what works now> Commit `<sha>`. <Anything noteworthy / any new `**Question:**` raised>.

When all six phases are GREEN and the manual test plan is walked, write the COMPLETE doc per the template and update `docs/roadmap_ref.md`. Don't tag a release on this one — D18 is foundational; the user-facing tag waits for D19's connection-management UX.
