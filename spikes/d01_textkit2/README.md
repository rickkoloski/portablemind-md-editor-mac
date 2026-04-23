# D1: TextKit 2 Live-Render Spike

**Status:** In Progress
**Purpose:** Throwaway Xcode/SPM sample app that validates TextKit 2's ability to deliver the live-render markdown UX for md-editor-mac.

See:
- `../../docs/current_work/specs/d01_textkit2_live_render_spike_spec.md`
- `../../docs/current_work/planning/d01_textkit2_live_render_spike_plan.md`

## Layout

```
d01_textkit2/
├── Package.swift                    SPM manifest, SwiftUI macOS exec + swift-markdown dep
├── Sources/TextKit2LiveRenderSpike/ Swift sources
├── samples/                         Test markdown files (sample-01…sample-05)
├── evidence/                        Screen recording, transcript, Instruments trace
├── scripts/env.sh                   Sets DEVELOPER_DIR to Xcode
└── README.md                        This file
```

## Build

```bash
source scripts/env.sh
swift build
swift run TextKit2LiveRenderSpike
```

Once XcodeGen is set up:
```bash
xcodegen generate
open TextKit2LiveRenderSpike.xcodeproj
```

## Disposable

This is a spike. The code is not intended for reuse as-is. Value = findings doc + evidence.
