# CLAUDE.md

Guidance for Claude Code when working on md-editor-mac.

## Project purpose

md-editor-mac is a native macOS markdown editor, purpose-built to bring non-technical and semi-technical users into LLM agentic human-in-the-loop workflows as first-class participants. It is the desktop surface for the PortableMind ecosystem — a Word/Docs-familiar authoring experience on a `.md`-files-on-disk foundation, so agents and humans can edit the same documents without either one being second-class. macOS is the initial target; Windows and Linux versions will follow, each natively implemented from shared non-code SDLC artifacts.

See `docs/vision.md` for the three principles driving the product.

---

## Technology stack

| Layer | Choice |
|---|---|
| Language | Swift (latest stable) |
| UI framework | SwiftUI primary, AppKit via `NSViewRepresentable` where needed |
| Text-editing engine | TextKit 2 with `NSTextView` bridging |
| Markdown parser | swift-markdown (Apple), cmark-gfm for GFM-specific nodes |
| File watching | NSFilePresenter for open docs, DispatchSourceFileSystemObject for folders |
| Packaging (v1) | Direct-download DMG, Developer ID + notarization |
| Updates | Sparkle (EdDSA-signed appcast) |
| Target macOS | Latest two major releases at implementation start |
| Local state | UserDefaults or small JSON; **no Core Data / SwiftData** |

Rationale and alternatives considered are in `docs/stack-alternatives.md`. The "Architecture lessons to capture for Windows and Linux" section there is a living contract — keep it honest as we build.

---

## Foundation documents (project-level references)

Five docs sit at `docs/` root as the project's north star. Every deliverable should trace back to at least one of them, and every deliverable spec must honor the standards in `docs/engineering-standards_ref.md`.

| Doc | What it decides |
|---|---|
| `docs/vision.md` | Three principles: purpose (agentic HITL companion), native-per-OS, markdown-today-structured-formats-tomorrow. Defines the two levels of "agent-aware." |
| `docs/competitive-analysis.md` | Sourced competitive landscape (Typora, iA Writer, Obsidian, Bear, Ulysses, Mark Text, Zed) with dimension matrix and 10 scoping questions. |
| `docs/portablemind-positioning.md` | How md-editor relates to the PortableMind ecosystem. Standalone-capable, PortableMind-aware. |
| `docs/stack-alternatives.md` | The committed macOS stack and the architecture lessons to extract for Windows/Linux. |
| `docs/engineering-standards_ref.md` | **Cross-deliverable rules that survive session turnover and context compaction.** Sandbox-safe source, locked bundle ID, Info.plist completeness, `accessibilityIdentifier` on every view, never touch `NSTextView.layoutManager`. Every spec must honor these; deferrals must be explicit. |

---

## Current work

Active deliverables live in `docs/current_work/`:

| Location | Contents |
|---|---|
| `specs/` | What to build — `dNN_name_spec.md` |
| `planning/` | How to build it — `dNN_name_plan.md` |
| `prompts/` | CC instructions — `dNN_name_prompt.md` |
| `stepwise_results/` | Completion records — `dNN_name_COMPLETE.md` |
| `issues/` | Blocked items — `dNN_name_BLOCKED.md` |

Completed work is chronicled in `docs/chronicle_by_concept/` (by domain) and `docs/chronicle_by_step/` (by time). Templates for every artifact type are in `docs/templates/`.

---

## Project structure

```
apps/md-editor-mac/
├── CLAUDE.md                       This file
├── project.yml                     xcodegen source for the real app
├── Info.plist                      generated from project.yml on xcodegen
├── MdEditor.xcodeproj/             generated; committed for reproducibility
├── Sources/                        App + all modules (see below)
│   ├── App/                        SwiftUI entry, window scene, Open…
│   ├── DocumentTypes/              Registry + Markdown type; JSON/YAML
│   │                               plug in here later
│   ├── Editor/                     TextKit 2 hosting + live-render
│   │   └── Renderer/               Markdown parser + cursor-on-line
│   ├── Files/                      NSFilePresenter external-edit watcher
│   ├── Accessibility/              Identifier constants
│   ├── Support/                    Typography, shared render types
│   ├── Handoff/                    stub (D6+)
│   ├── Toolbar/                    stub (D5)
│   ├── Keyboard/                   stub (D4)
│   ├── Settings/                   stub (TBD)
│   └── Localization/               Localizable.xcstrings
├── UITests/                        XCUITests (launch smoke + future)
├── scripts/env.sh                  DEVELOPER_DIR helper
├── docs/
│   ├── vision.md                   Foundation ref
│   ├── competitive-analysis.md     Foundation ref
│   ├── portablemind-positioning.md Foundation ref
│   ├── stack-alternatives.md       Foundation ref
│   ├── engineering-standards_ref.md Cross-deliverable rules
│   ├── roadmap_ref.md              Informal ordering
│   ├── current_work/               Active deliverables
│   ├── chronicle_by_concept/       Completed work by domain
│   ├── chronicle_by_step/          Completed work by time
│   └── templates/                  Artifact templates
└── spikes/
    └── d01_textkit2/               [FROZEN] D1 reference, do not modify
```

---

## Running the project

Pane 2 (or any shell) from the repo root:

```bash
source scripts/env.sh                          # sets DEVELOPER_DIR for Xcode
xcodegen generate                              # (re)generate MdEditor.xcodeproj
xcodebuild -project MdEditor.xcodeproj \
           -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode \
           build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Run the UITest smoke check:

```bash
xcodebuild -project MdEditor.xcodeproj \
           -scheme MdEditor \
           -destination 'platform=macOS' \
           -derivedDataPath ./.build-xcode \
           test
```

First-run UITest on a new machine pops a macOS Accessibility/Automation permission dialog — grant Allow; the grant persists. See `docs/engineering-standards_ref.md` §2.1.

---

## Key patterns and conventions

*To be filled in as deliverables land. Expected early entries: document-type registry interface, editor state machine, Submit/Handoff protocol.*

The nine cross-OS architecture abstractions from `docs/stack-alternatives.md` are the spine:
1. Document-type registry
2. Editor state model
3. File-system abstraction
4. Submit / Handoff protocol
5. Toolbar taxonomy
6. Keyboard shortcut map
7. Accessibility contract
8. Settings schema
9. Localization strings table

When we write these, they live as design artifacts (above the stack) so Windows and Linux can implement them natively rather than port.

---

## SDLC Process Compliance

This project follows the SDLC framework from `~/src/ops/sdlc/`, using the **Native lifecycle** (`~/src/ops/sdlc/lifecycles/native.md`).

**CC must:**
- Follow the deliverable workflow (Spec → Planning → Implementation → Validation → Deploy → Result → Chronicle)
- Use deliverable IDs (D1, D2, ...) for all new work
- Create specs before implementing non-trivial features
- Document completions in `docs/current_work/stepwise_results/`
- Ask before deviating from established process

**Do not:**
- Skip the spec phase for significant work
- Implement features without deliverable IDs
- Deviate from the process without explicit approval
- Declare a mutation verified without a persistence round-trip (Persistence Rule; see `~/src/ops/sdlc/disciplines/testing.md`)

**Default posture for foundational specs:**
- Trace every spec to at least one foundation doc (vision, competitive-analysis, portablemind-positioning, stack-alternatives).
- Where a deliverable is a cross-OS architecture artifact (one of the nine abstractions above), write it as an OS-neutral design doc first, then a mac-specific implementation spec that references it.

### SDLC commands

| Command | Action |
|---|---|
| "Let's catalog our ad hoc work" | Reconcile informal work back into the process (`~/src/ops/sdlc/lifecycles/prototyping.md` § Reentry). |
| "Let's organize the chronicles" | Archive completed work (`~/src/ops/sdlc/operations/chronicle_organization.md`). |
| "Let's run an SDLC compliance audit" | Audit the project against SDLC standards (`~/src/ops/sdlc/operations/compliance_audit.md`). |
| "Let's update the SDLC" | Propose a process improvement (`~/src/ops/sdlc/operations/sdlc_changelog.md`). |

---

## CD/CC collaboration

**CD** is Rick. **CC** is me (Claude Code). The CD/CC collaboration model (`~/src/ops/sdlc/operations/collaboration_model.md`) applies:
- CC proposes, CD approves, before significant work.
- CC asks clarifying questions when specs are ambiguous rather than guessing.
- CD decides what to build; CC owns implementation detail within the approved approach.
- CD verifies architectural alignment; CC is trusted on code and factual statements about the codebase.

Communication style: terse, specific, no trailing summaries unless asked.
