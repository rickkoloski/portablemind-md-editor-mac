import AppKit
import SwiftUI

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
            return "No session waiting on this doc"
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
                .help(helpText)
        }
        .disabled(interest == nil)
        .accessibilityIdentifier(AccessibilityIdentifiers.toolbarSubmit)
        .accessibilityLabel("Submit")
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
