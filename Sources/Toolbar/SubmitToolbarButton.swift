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
///
/// **SwiftUI observation chain (two layers):**
/// SwiftUI's `@ObservedObject` doesn't transitively subscribe to
/// nested `ObservableObject`s. Two separate subscriptions are needed:
///
/// 1. **Focus changes** — observe `TabStore` directly. `WorkspaceStore`
///    declares `let tabs = TabStore()` (a separate ObservableObject,
///    not a `@Published` property), so observing `WorkspaceStore`
///    alone misses tab-open / focused-index changes. `TabBarView`
///    works for the same reason: it observes the TabStore directly.
/// 2. **Interest-set changes** on the focused doc — the inner
///    `ActiveDocSubmitButton` takes `@ObservedObject var document:
///    EditorDocument` so mutations to `interestedSessions` trigger a
///    body re-evaluation.
struct SubmitToolbarButton: View {
    @ObservedObject private var tabs = WorkspaceStore.shared.tabs

    var body: some View {
        if let doc = tabs.focused {
            ActiveDocSubmitButton(document: doc)
        } else {
            DisabledSubmitMenu(
                reason: "No active tab is connected to an AI Session")
        }
    }
}

/// Inner view scoped to a single focused document. `@ObservedObject`
/// gives us the per-doc subscription that propagates
/// `interestedSessions` changes back into a body re-render.
private struct ActiveDocSubmitButton: View {
    @ObservedObject var document: EditorDocument

    private var interest: SessionInterest? {
        document.interestedSessions.first
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
            SubmitButtonLabel()
        }
        .disabled(interest == nil)
        .accessibilityIdentifier(AccessibilityIdentifiers.toolbarSubmit)
        .accessibilityLabel("Submit")
        .overlay(
            HoverTooltipOverlay(text: helpText)
                .allowsHitTesting(interest == nil)
        )
    }

    private func performSubmit() {
        Task {
            do {
                _ = try await SubmitDispatcher.submit(document: document)
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

/// Rendered when there is no focused document at all (no open tabs).
/// The Menu shape is preserved so the toolbar's layout stays stable
/// across the empty-workspace transition.
private struct DisabledSubmitMenu: View {
    let reason: String

    var body: some View {
        Menu {
            EmptyView()
        } label: {
            SubmitButtonLabel()
        }
        .disabled(true)
        .accessibilityIdentifier(AccessibilityIdentifiers.toolbarSubmit)
        .accessibilityLabel("Submit")
        .overlay(
            HoverTooltipOverlay(text: reason)
                .allowsHitTesting(true)
        )
    }
}

/// Shared paperplane label so the active and disabled variants render
/// pixel-identically.
private struct SubmitButtonLabel: View {
    var body: some View {
        Label("Submit", systemImage: "paperplane.fill")
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(red: 222/255, green: 222/255, blue: 222/255))
    }
}
