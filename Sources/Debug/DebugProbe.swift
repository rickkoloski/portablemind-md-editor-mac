// D15.1 — in-window diagnostic state for click + scroll debugging.
// Toggled via View menu → "Show Debug HUD" (off by default). When on,
// the toolbar's trailing slot shows scrollY, last click coordinates,
// resolved fragment kind/position, and table cell coords if applicable.
//
// This is purely an instrumentation surface — it doesn't gate any
// logic. Strip / hide if/when production usage warrants.

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class DebugProbe: ObservableObject {
    static let shared = DebugProbe()

    @Published var scrollY: CGFloat = 0
    @Published var lastClickViewX: CGFloat = 0
    @Published var lastClickViewY: CGFloat = 0
    @Published var lastClickContainerY: CGFloat = 0
    @Published var lastClickLine: Int = 0
    @Published var lastFragKind: String = "—"
    @Published var lastFragOriginY: CGFloat = 0
    @Published var lastTableRow: Int = -1
    @Published var lastTableCol: Int = -1
    @Published var lastFragmentClass: String = "—"

    private init() {}

    func recordScroll(_ y: CGFloat) {
        if abs(scrollY - y) > 0.5 { scrollY = y }
    }

    func recordClick(viewPoint: NSPoint,
                     containerY: CGFloat,
                     line: Int,
                     fragKind: String,
                     fragOriginY: CGFloat,
                     tableRow: Int,
                     tableCol: Int,
                     fragmentClass: String) {
        lastClickViewX = viewPoint.x
        lastClickViewY = viewPoint.y
        lastClickContainerY = containerY
        lastClickLine = line
        lastFragKind = fragKind
        lastFragOriginY = fragOriginY
        lastTableRow = tableRow
        lastTableCol = tableCol
        lastFragmentClass = fragmentClass
    }
}

/// One-line monospaced read-out of probe state. Designed to slot into
/// the trailing toolbar group.
struct DebugProbeHUD: View {
    @ObservedObject private var probe = DebugProbe.shared

    var body: some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(tooltip)
    }

    private var line: String {
        let cell = probe.lastTableRow >= 0
            ? "tbl(r=\(probe.lastTableRow),c=\(probe.lastTableCol))"
            : probe.lastFragKind
        return String(format:
            "scrollY=%.0f click=(%.0f,%.0f) line=%d frag=%@ fragY=%.0f",
            probe.scrollY,
            probe.lastClickViewX, probe.lastClickViewY,
            probe.lastClickLine,
            cell,
            probe.lastFragOriginY)
    }

    private var tooltip: String {
        """
        scrollY: contentView.bounds.origin.y
        click: in textView coords
        line: 1-based, computed from source position
        frag: kind / table cell coords
        fragY: layoutFragmentFrame.origin.y reported by the resolved fragment
        fragmentClass: \(probe.lastFragmentClass)
        containerY: \(String(format: "%.0f", probe.lastClickContainerY))
        """
    }
}
