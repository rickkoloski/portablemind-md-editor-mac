// D23 phase 2 — Save As / New File modal sheet content. Triggered via
// `WorkspaceStore.saveAsRequest`; rendered as a SwiftUI `.sheet(item:)`
// attached at WorkspaceView level. Per spec Q1, this is a custom modal
// (not NSSavePanel) so we can host a connector tree picker.
//
// Phase 2 scope: Save As on a PM tab targeting a PM destination, plus
// Save As on a Local tab targeting a Local destination (the existing
// NSSavePanel path stays as the Local default trigger; this sheet is
// reachable for Local tabs only via the same path Save As routes
// through). The connector picker dropdown (cross-connector targets,
// e.g. "Save my Local doc into PortableMind") is parked for a follow-up.

import SwiftUI

struct SaveAsSheet: View {
    let request: WorkspaceStore.SaveAsRequest
    @ObservedObject var workspace: WorkspaceStore

    @State private var filename: String
    @State private var selectedDirectory: ConnectorNode?
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(request: WorkspaceStore.SaveAsRequest,
         workspace: WorkspaceStore) {
        self.request = request
        self.workspace = workspace
        _filename = State(initialValue: request.initialFilename)
        _selectedDirectory = State(
            initialValue: request.initialConnector.rootNode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            filenameField
            treePicker
            if let errorMessage {
                errorBanner(errorMessage)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 560)
        .accessibilityIdentifier("md-editor.save-as-sheet")
    }

    @ViewBuilder
    private var header: some View {
        let title = request.intent == .newFile
            ? "New File"
            : "Save As"
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            if request.intent == .saveAs {
                Text("Save '\(request.initialFilename)' as a new file in PortableMind.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Create a new file in PortableMind.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var filenameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name").font(.caption).foregroundStyle(.secondary)
            TextField("Filename", text: $filename)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("md-editor.save-as-sheet.filename")
        }
    }

    @ViewBuilder
    private var treePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Where").font(.caption).foregroundStyle(.secondary)
            if let viewModel = workspace.treeViewModels[request.initialConnector.id] {
                PickConnectorTreeView(
                    viewModel: viewModel,
                    selection: $selectedDirectory)
                    .frame(minHeight: 240)
                    .background(Color(NSColor.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.separator, lineWidth: 1))
            } else {
                Text("No connector available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240,
                           alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("md-editor.save-as-sheet.error")
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                workspace.dismissSaveAs()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("md-editor.save-as-sheet.cancel")

            Button(saveButtonLabel) {
                Task { await performSave() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave || isSaving)
            .accessibilityIdentifier("md-editor.save-as-sheet.save")
        }
    }

    private var saveButtonLabel: String {
        request.intent == .newFile ? "Create" : "Save"
    }

    private var canSave: Bool {
        let trimmed = filename.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("/") else { return false }
        guard selectedDirectory?.kind == .directory else { return false }
        return true
    }

    @MainActor
    private func performSave() async {
        guard let target = selectedDirectory, canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            switch request.intent {
            case .saveAs:
                guard let doc = request.document else {
                    errorMessage = "Internal error: Save As without source document"
                    return
                }
                _ = try await PMFileOperations.saveAs(
                    doc: doc, to: target, name: filename)
            case .newFile:
                _ = try await PMFileOperations.newFile(
                    in: target, name: filename, store: workspace)
            }
            workspace.dismissSaveAs()
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

private extension Color {
    static var separator: Color {
        Color(NSColor.separatorColor)
    }
}
