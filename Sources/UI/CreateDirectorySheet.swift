// D23.1 phase 2 — Create Folder modal sheet for PM. Variant of
// RenameSheet: single TextField, Save / Cancel, inline error. On
// Save calls PMFileOperations.createDirectory which calls
// connector.createDirectory + splices the cached tree.

import SwiftUI

struct CreateDirectorySheet: View {
    let request: WorkspaceStore.CreateDirectoryRequest
    @ObservedObject var workspace: WorkspaceStore

    @State private var name: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Folder")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Create a new folder in '\(request.parent.name)'.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("md-editor.new-folder-sheet.name")
            }
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage).font(.callout).lineLimit(3)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("md-editor.new-folder-sheet.error")
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { workspace.dismissCreateDirectory() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("md-editor.new-folder-sheet.cancel")
                Button("Create") { Task { await performCreate() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || isCreating)
                    .accessibilityIdentifier("md-editor.new-folder-sheet.save")
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 180)
        .accessibilityIdentifier("md-editor.new-folder-sheet")
    }

    private var canCreate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("/") else { return false }
        return true
    }

    @MainActor
    private func performCreate() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            _ = try await PMFileOperations.createDirectory(
                in: request.parent,
                name: name,
                store: workspace)
            workspace.dismissCreateDirectory()
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
