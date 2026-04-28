// D19 phase 4 — singleton owner of the in-flight save-conflict NSAlert.
//
// The save flow throws `ConnectorError.conflictDetected` when the server's
// `updated_at` is newer than the version the client last saw. saveFocused
// catches it and asks this presenter to display an Overwrite / Cancel
// dialog. Choice is returned to the caller as `Choice.overwrite` (re-save
// with `force: true`) or `.cancel` (leave the buffer dirty).
//
// The active NSAlert is exposed via `dismiss(choice:)` so the harness
// (`dismiss_conflict_dialog`) can drive the dialog without focus-stealing
// XCUITest interactions. Sheet presentation is preferred to runModal so
// the harness Timer keeps firing while the dialog is up.

import AppKit

@MainActor
final class ConflictDialogPresenter {
    static let shared = ConflictDialogPresenter()

    enum Choice { case overwrite, cancel }

    private weak var activeAlert: NSAlert?

    private init() {}

    /// True iff a conflict dialog is currently showing. Read by the
    /// harness state-dump action so tests can wait for the dialog to
    /// be on screen before issuing `dismiss_conflict_dialog`.
    var isShowing: Bool { activeAlert != nil }

    /// Show the conflict dialog. Returns when the user (or the harness)
    /// picks an option. Sheet-mounted on the first visible NSWindow;
    /// falls back to `runModal` if no window is found (shouldn't happen
    /// in normal operation, but keeps the path safe under tests).
    func present(serverUpdatedAt: Date) async -> Choice {
        let alert = NSAlert()
        alert.messageText = "Remote file has changed"
        alert.informativeText = """
            This file was modified on PortableMind since you opened it. \
            The server's last-modified time is \(formatted(serverUpdatedAt)).

            Overwrite the server version with your local edits?
            """
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Cancel")

        activeAlert = alert
        defer { activeAlert = nil }

        let response: NSApplication.ModalResponse
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            response = await withCheckedContinuation { cont in
                alert.beginSheetModal(for: window) { resp in
                    cont.resume(returning: resp)
                }
            }
        } else {
            response = alert.runModal()
        }
        return response == .alertFirstButtonReturn ? .overwrite : .cancel
    }

    /// Programmatically dismiss the active dialog by clicking the
    /// matching button. Returns `false` if no dialog is active or the
    /// expected button isn't present.
    @discardableResult
    func dismiss(choice: Choice) -> Bool {
        guard let alert = activeAlert else { return false }
        let idx = (choice == .overwrite) ? 0 : 1
        guard idx < alert.buttons.count else { return false }
        alert.buttons[idx].performClick(nil)
        return true
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
