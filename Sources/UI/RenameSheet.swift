// D23 phase 4 — Rename modal sheet for PM file nodes. Triggered via
// `WorkspaceStore.renameRequest`; rendered as `.sheet(item:)` at
// WorkspaceView level. Simpler than SaveAsSheet — no tree picker
// (rename is in-place); just a name field + Save/Cancel + inline
// error.

import SwiftUI

struct RenameSheet: View {
    let request: WorkspaceStore.RenameRequest
    @ObservedObject var workspace: WorkspaceStore

    @State private var newName: String
    @State private var isRenaming: Bool = false
    @State private var errorMessage: String?

    init(request: WorkspaceStore.RenameRequest,
         workspace: WorkspaceStore) {
        self.request = request
        self.workspace = workspace
        _newName = State(initialValue: request.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rename")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Rename '\(request.initialName)'.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("New name").font(.caption).foregroundStyle(.secondary)
                TextField("Filename", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("md-editor.rename-sheet.newname")
            }
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.callout)
                        .lineLimit(3)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("md-editor.rename-sheet.error")
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") {
                    workspace.dismissRename()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("md-editor.rename-sheet.cancel")
                Button("Rename") {
                    Task { await performRename() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRename || isRenaming)
                .accessibilityIdentifier("md-editor.rename-sheet.save")
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 180)
        .accessibilityIdentifier("md-editor.rename-sheet")
    }

    private var canRename: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("/") else { return false }
        guard trimmed != request.initialName else { return false }
        return true
    }

    @MainActor
    private func performRename() async {
        guard canRename else { return }
        isRenaming = true
        errorMessage = nil
        defer { isRenaming = false }
        do {
            _ = try await PMFileOperations.rename(
                node: request.node,
                to: newName,
                store: workspace)
            workspace.dismissRename()
        } catch let cerr as ConnectorError {
            errorMessage = describe(cerr)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func describe(_ error: ConnectorError) -> String {
        switch error {
        case .unauthenticated:
            return "Not signed in. Set token in Debug menu."
        case .writeForbidden(let body):
            return "Write denied: \(body)"
        case .storageQuotaExceeded(let body):
            return "Storage quota exceeded: \(body)"
        case .conflictDetected:
            return "Conflict detected on the server."
        case .network(let underlying):
            return "Network: \(underlying.localizedDescription)"
        case .server(let status, let message):
            return "Server \(status): \(message ?? "")"
        case .unsupported(let msg):
            return msg
        }
    }
}
