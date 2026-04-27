# D19 Prompt — PortableMind save-back

You are working on `~/src/apps/md-editor-mac` on branch `feature/d19-pm-save-back`. Your job is to add write-back to the PortableMind connector — click an `.md` file in the PM sidebar, edit it, ⌘S persists the change to Harmoniq's LlmFile API. Read-only behavior from D18 stays as a graceful-degradation fallback (denied permissions, offline, etc.).

This deliverable closes the human↔agent feedback loop on PortableMind-stored docs. After D19, the dogfood `**Question:**` → `**Decision:**` workflow we established last weekend works on PM-resident roadmaps / specs / decision logs, not just local files.

---

## Read first (in this order)

1. `docs/current_work/specs/d19_pm_save_back_spec.md` — the contract. Decision log captures the four scope answers (CD-approved 2026-04-27).
2. `docs/current_work/planning/d19_pm_save_back_plan.md` — five phases with DOD per phase + harness action additions.
3. D18 prompt and COMPLETE: `docs/current_work/prompts/d18_pm_connector_directory_tree_prompt.md` + `docs/current_work/stepwise_results/d18_pm_connector_directory_tree_COMPLETE.md`. The infrastructure D19 builds on.
4. `docs/engineering-standards_ref.md` — especially §3.1 (branching: feature/d##-*) and §0.1 in the D19 plan (harness-first verification).
5. `docs/issues_backlog.md` — i01 (Read cache) is relevant; use `Bash grep`/`stat` rather than `Read` to verify save round-trips.
6. Memory pointers (`~/.claude/projects/-Users-richardkoloski-src/memory/`):
   - `feedback_no_shortcuts_pre_users.md` — pre-user products build the hard thing right.
   - `md_editor_dogfood_workflow.md` — `**Question:**` / `**Decision:**` markers.
   - `harmoniq_mcp_points_at_prod.md` — base URL default is prod; UserDefaults override for localhost.

---

## Reference code (don't import, mirror)

The Harmoniq write endpoint research is captured in plan §Phase 2:

- Route: `PATCH /api/v1/llm_files/:id` (or `PUT`).
- Body: `multipart/form-data`; the file part name is `llm_file[file]`; content-type for `.md` is `text/markdown`.
- Auth: same Bearer + X-Tenant-ID combo as read.
- Response: standard `{success, llm_file: {url, updated_at, ...}}` envelope; the URL is a fresh 20-minute signed URL.
- **No server-side conflict detection** — pure last-writer-wins. D19 client-side adds the optimistic prompt (Q2 decision).
- Storage-quota: 402 with `error_code: "DOCUMENT_STORAGE_LIMIT_EXCEEDED"`.

Controller is `app/controllers/api/v1/llm_files_controller.rb` lines 306–362 in `~/src/apps/harmoniq/reference-code/model_api`. Don't import or vendor; mirror the contract in Swift.

---

## Where to work

Production code in `Sources/`. New files go in:
- `Sources/Connectors/PortableMind/MultipartFormDataBuilder.swift` (phase 2).

Existing files to edit (per plan):
- `Sources/Connectors/Connector.swift`, `LocalConnector.swift`, `PortableMind/PortableMindConnector.swift` (phases 1 + 3 + 4)
- `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` (phase 2)
- `Sources/Workspace/EditorDocument.swift` (phases 1 + 3 + 4)
- `Sources/Workspace/TabStore.swift` (phase 3)
- `Sources/Editor/EditorContainer.swift` (phase 3)
- `Sources/WorkspaceUI/TabBarView.swift` (phase 3)
- `Sources/App/MdEditorApp.swift` (phases 3 + 4 + 5)
- `Sources/Debug/HarnessCommandPoller.swift` (phases 2 + 3 + 4)

`xcodegen generate` after adding/removing files; build with `source scripts/env.sh && xcodebuild ...`.

---

## How to work

Follow the five phases in the plan **in order**. Each phase ends in a buildable + smokeable + committable state.

Per phase:
1. Read the phase's "Files updated" / "Harness actions added" / "DOD".
2. Make the change.
3. Build.
4. Run the smoke (harness-driven; see "Verification" below).
5. Commit per the message in the plan.

If a phase's DOD doesn't go GREEN, don't paper over with workarounds. Stop and surface a `**Question:**` per the dogfood convention.

---

## Critical: route saves through the Connector

EditorDocument currently has a `save()` that writes to a local `URL`. D19 routes saves through the connector. The local path becomes a special case of the connector contract (LocalConnector implements `saveFile` mirroring D14 behavior).

Don't introduce a fork in the codebase where local files take a separate save path — that's the D18 protocol's whole point. If you find yourself wanting to special-case Local in EditorDocument, that's a sign the protocol seam is leaking; surface a `**Question:**`.

---

## Critical: Q2 conflict-detection IS the firm protection; the fallback is the safety valve

The Q2 decision (server-wins prompt with graceful fallback) is two things:

1. **Firm protection:** GET `updated_at` before each PATCH; if newer than `lastSeenUpdatedAt`, modal prompt before overwriting. This is the user-facing data-loss prevention.

2. **Safety valve:** if the GET-before-PATCH itself fails (network blip, server 5xx that's not auth-related), proceed with the PATCH directly (last-writer-wins). This honors the realistic field condition that flaky networks shouldn't block saves.

Don't conflate the two. Auth failures on the GET (401/403) should NOT trigger the fallback — they should surface as save errors. Only network-class errors fall through.

---

## Critical: Q3 optimistic save UX

The editor stays responsive while saves fly. Don't gate keystrokes on save completion. If a save fails:
- Surface a non-blocking error (sheet on the focused tab, or banner — pick one and document).
- Keep the dirty buffer; user can retry.
- If a second save fires while the first is in flight, debounce or coalesce — don't queue indefinitely. Document the choice in COMPLETE.

If you find yourself wanting to lock the editor during a save, surface a `**Question:**`.

---

## Verification: harness-first

Same stack as D18 — `Sources/Debug/HarnessCommandPoller.swift` JSON-file IPC, no focus-stealing. New harness actions per phase (see plan §0.1):

- Phase 2: `pm_save_smoke {fileID, text, resultPath}`
- Phase 3: `connector_save_focused {resultPath}` + extended `focused_doc_info`
- Phase 4: `dump_save_state {resultPath}` + `dismiss_conflict_dialog {choice}`

Verify the round-trip: write command JSON via `Bash`, wait for command-file disappearance (or result-file non-empty for async), `cat` + `jq` the result, assert. App keeps focus wherever the user puts it.

---

## Test fixture for conflict detection (phase 4)

To test the conflict prompt, you need to mutate a PM file out-of-band while the editor has it open. Use `pm_save_smoke` (introduced in phase 2) twice: once from a separate harness command to write content via the API, once from the editor's ⌘S (or `connector_save_focused`). The first write changes `updated_at`; the second hits the prompt.

---

## Manual test plan

Plan §Phase 5 sketches the structure. Output goes in `docs/current_work/testing/d19_pm_save_back_manual_test_plan.md`. Mirrors the harness action coverage with human-runnable steps.

---

## What NOT to do

- Don't add auto-save / debounced save (Q1 deferral).
- Don't implement three-way merge or conflict resolution UI beyond the Q2 prompt.
- Don't enable Save As / rename / move on PM tabs (Q4 — unsupported dialog only). The unified PM file-management deliverable (post-D20) handles those.
- Don't add an offline-save queue. D19 surfaces network errors loud and clear; queue + retry is a separate deliverable.
- Don't lock the editor during saves (Q3 — optimistic UX).
- Don't write a new HTTP / multipart library beyond the small `MultipartFormDataBuilder` helper. URLSession + a ~50 LOC builder is sufficient.

---

## When you finish a phase

End-of-phase status update (one or two sentences) so CD can sanity-check progress without reading the diff:

> **Phase N complete:** <what works now> Commit `<sha>`. <Anything noteworthy / any new `**Question:**` raised>.

When all five phases are GREEN and the manual test plan is walked, write the COMPLETE doc per the template and update `docs/roadmap_ref.md`. D19 deliverable closes; merge `feature/d19-pm-save-back` into `main` per engineering-standards §3.1.
