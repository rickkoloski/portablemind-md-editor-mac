import SwiftUI

/// Top-level workspace layout — sidebar (multi-connector tree) on the
/// left, main area (tab bar + editor / empty state) on the right.
struct WorkspaceView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(workspace.rootURL?.lastPathComponent ?? "MdEditor")
    }

    @ViewBuilder
    private var sidebar: some View {
        if workspace.connectors.isEmpty {
            VStack(spacing: 8) {
                Text("No folder open")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("File → Open Folder… to choose a workspace folder.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("Or set a PortableMind token in the Debug menu (debug builds only).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workspace.connectors, id: \.id) { connector in
                        if let model = workspace.treeViewModels[connector.id] {
                            ConnectorTreeView(viewModel: model) { node in
                                handleSelect(node, on: connector)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.folderTree)
        }
    }

    @ViewBuilder
    private var detail: some View {
        WorkspaceDetailView(tabs: workspace.tabs)
    }

    private func handleSelect(_ node: ConnectorNode, on connector: any Connector) {
        if connector.id == "local" {
            _ = workspace.tabs.open(fileURL: URL(fileURLWithPath: node.path))
            return
        }
        // PortableMind: read-only tab. Async fetch via the connector;
        // open a read-only tab on completion. Failures present as a
        // brief alert (network / auth issues are loud enough that we
        // don't want them silently dropped).
        Task {
            do {
                let bytes = try await connector.openFile(node)
                let text = String(data: bytes, encoding: .utf8) ?? ""
                let fileID = Self.parseFileID(from: node.id, prefix: "\(connector.id):file:")
                let origin = EditorDocument.Origin.portableMind(
                    connectorID: connector.id,
                    fileID: fileID ?? -1,
                    displayPath: node.path
                )
                workspace.tabs.openReadOnly(content: text, origin: origin)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't open \(node.name)"
                alert.informativeText = "\(error)"
                alert.runModal()
            }
        }
    }

    private static func parseFileID(from id: String, prefix: String) -> Int? {
        guard id.hasPrefix(prefix) else { return nil }
        return Int(id.dropFirst(prefix.count))
    }
}

/// Detail side of the workspace split. Observes `TabStore` directly
/// so focus / open / close changes re-render the editor region —
/// without this, nested ObservableObject mutations on
/// `workspace.tabs` do not propagate through the outer
/// `@ObservedObject var workspace` (a SwiftUI-nested-ObservableObject
/// gotcha).
private struct WorkspaceDetailView: View {
    @ObservedObject var tabs: TabStore

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(tabs: tabs)
            Divider()
            if let focused = tabs.focused {
                EditorContainer(document: focused)
                    .id(focused.id)
            } else {
                EmptyEditorView()
            }
        }
    }
}
