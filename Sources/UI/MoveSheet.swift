// D23 phase 5 — Move modal sheet for PM file nodes. Variant of
// SaveAsSheet: same tree picker (PickConnectorTreeView), no filename
// field (the file's name is preserved on move), Save labeled "Move".
//
// Triggered via `WorkspaceStore.moveRequest`; rendered as `.sheet(item:)`
// at WorkspaceView level. On Save the modal calls
// PMFileOperations.move which calls connector.moveFile (PATCH
// llm_files/:id with directory_path=newPath) and updates any open tabs.

import SwiftUI

struct MoveSheet: View {
    let request: WorkspaceStore.MoveRequest
    @ObservedObject var workspace: WorkspaceStore

    @State private var selectedDirectory: ConnectorNode?
    @State private var isMoving: Bool = false
    @State private var errorMessage: String?

    init(request: WorkspaceStore.MoveRequest,
         workspace: WorkspaceStore) {
        self.request = request
        self.workspace = workspace
        // Default selection: the connector's root. User picks a more
        // specific target by drilling in the picker.
        _selectedDirectory = State(
            initialValue: request.node.connector.rootNode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Move")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Move '\(request.node.name)' to a new directory.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Where").font(.caption).foregroundStyle(.secondary)
                if let viewModel = workspace.treeViewModels[request.node.connector.id] {
                    PickConnectorTreeView(
                        viewModel: viewModel,
                        selection: $selectedDirectory)
                        .frame(minHeight: 240)
                        .background(
                            Color(NSColor.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor),
                                        lineWidth: 1))
                } else {
                    Text("No connector available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240,
                               alignment: .center)
                }
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
                .accessibilityIdentifier("md-editor.move-sheet.error")
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { workspace.dismissMove() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("md-editor.move-sheet.cancel")
                Button("Move") { Task { await performMove() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canMove || isMoving)
                    .accessibilityIdentifier("md-editor.move-sheet.save")
            }
        }
        .padding(16)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 420, idealHeight: 500)
        .accessibilityIdentifier("md-editor.move-sheet")
    }

    /// Save enabled when a target directory is selected and it isn't
    /// the file's current parent (no-op move).
    private var canMove: Bool {
        guard let target = selectedDirectory,
              target.kind == .directory else { return false }
        // Reject no-op: target == current parent. The current parent
        // path is request.node.path's parent — derive from it.
        let currentParentPath = parentPath(of: request.node.path)
        if target.path == currentParentPath { return false }
        return true
    }

    /// Strip the last path component from `path`. Roughly equivalent to
    /// `URL.deletingLastPathComponent` but works on the connector's
    /// path-string semantics (PortableMind paths use `/` separators
    /// regardless of platform).
    private func parentPath(of path: String) -> String {
        if let idx = path.lastIndex(of: "/") {
            let parent = String(path[..<idx])
            return parent.isEmpty ? "/" : parent
        }
        return "/"
    }

    @MainActor
    private func performMove() async {
        guard let target = selectedDirectory, canMove else { return }
        isMoving = true
        errorMessage = nil
        defer { isMoving = false }
        do {
            _ = try await PMFileOperations.move(
                node: request.node,
                to: target,
                store: workspace)
            workspace.dismissMove()
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
