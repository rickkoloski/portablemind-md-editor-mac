# [FROZEN] D1 TextKit 2 Spike — Do Not Modify

**This spike has been promoted to `apps/md-editor-mac/` (the real project) in D2 (2026-04-22).**

It is retained here as a minimal known-good reference — useful if we ever need to compare against a stripped-down implementation or reproduce a subtle behavior. **It must not be modified.** If you find a discrepancy between this spike and the real app, update the real app; the spike stays frozen.

Context:
- Spec: `../../docs/current_work/specs/d01_textkit2_live_render_spike_spec.md`
- Plan: `../../docs/current_work/planning/d01_textkit2_live_render_spike_plan.md`
- Findings / recommendation: `../../docs/current_work/stepwise_results/d01_textkit2_live_render_spike_COMPLETE.md`

The five findings surfaced by this spike (`.layoutManager` trap, initial-render pre-collapse, InlineCode range, CodeBlock range + fence tagging, XCUITest accessibilityIdentifier discipline) were all applied during the D2 lift. They are captured durably in `../../docs/engineering-standards_ref.md`.

## Layout (unchanged from the D1 spike)

```
d01_textkit2/
├── Package.swift                    SPM manifest, SwiftUI macOS exec
├── Sources/TextKit2LiveRenderSpike/ Swift sources (6 files)
├── samples/                         5 test markdown files
├── evidence/                        Demo transcript from D1
├── scripts/env.sh                   DEVELOPER_DIR helper
└── README.md                        This file
```

## If you need to run the spike

```bash
source scripts/env.sh
swift build
# SPM-run gives no foreground window; the real .app bundle lived at
#   .build-xcode/Build/Products/Debug/TextKit2LiveRenderSpike.app
# after `xcodegen generate && xcodebuild build`, but .build-xcode/ is
# gitignored so you'd need to regenerate.
```
