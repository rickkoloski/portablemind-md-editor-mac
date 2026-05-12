import AppKit
import SwiftUI

/// SwiftUI's `.help()` on a `.disabled` control is suppressed by
/// macOS's hover handling. NSView's `toolTip` property uses
/// NSTrackingArea which fires regardless of enabled state — this
/// wrapper overlays a hover-only tooltip surface that works on
/// disabled buttons. Hit-testing is gated by the caller so clicks
/// still reach the underlying control when it's enabled.
private struct HoverTooltipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

/// D30 phase 5 — toolbar Submit button.
///
/// Button-with-dropdown shape (`Menu`). Acts on the currently focused
/// tab; enabled when that tab has a non-empty interest set; disabled
/// otherwise. `⌘⏎` keyboard shortcut. Submit failures surface as
/// NSAlert per D16.
///
/// Tab badge (small dot beside the dirty-dot) is informational only —
/// it does not trigger Submit; the toolbar button is the single
/// affordance.
struct SubmitToolbarButton: View {
    @ObservedObject private var workspace = WorkspaceStore.shared

    private var focusedDoc: EditorDocument? {
        workspace.tabs.focused
    }

    private var interest: SessionInterest? {
        focusedDoc?.interestedSessions.first
    }

    private var helpText: String {
        guard let interest else {
            return "No active tab is connected to an AI Session"
        }
        let name = interest.label ?? interest.sessionID
        return "Submit to \(name) (⌘↩)"
    }

    var body: some View {
        Menu {
            Button("Submit") { performSubmit() }
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier(AccessibilityIdentifiers.toolbarSubmitDropdownSubmit)
        } label: {
            Label("Submit", systemImage: "paperplane.fill")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(red: 222/255, green: 222/255, blue: 222/255))
        }
        .disabled(interest == nil)
        .accessibilityIdentifier(AccessibilityIdentifiers.toolbarSubmit)
        .accessibilityLabel("Submit")
        // Tooltip-on-disabled fallback: when the Menu is disabled, SwiftUI's
        // `.help()` is suppressed. NSView.toolTip uses NSTrackingArea and
        // fires regardless. Overlay is only hit-testable when disabled, so
        // clicks pass through to the Menu when enabled.
        .overlay(
            HoverTooltipOverlay(text: helpText)
                .allowsHitTesting(interest == nil)
        )
    }

    private func performSubmit() {
        guard let doc = focusedDoc else { return }
        Task {
            do {
                _ = try await SubmitDispatcher.submit(document: doc)
            } catch {
                presentSubmitError(error)
            }
        }
    }

    private func presentSubmitError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not record submission"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
