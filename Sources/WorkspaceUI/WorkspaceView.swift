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
        // D23 phase 2 — Save As / New File modal sheet. Bound to
        // workspace.saveAsRequest so any code path (App-level
        // saveAsFocused, harness pm_save_as) can drive the sheet by
        // setting the request.
        .sheet(item: $workspace.saveAsRequest) { request in
            SaveAsSheet(request: request, workspace: workspace)
        }
        // D23 phase 4 — Rename modal sheet. Same pattern as Save As;
        // bound to workspace.renameRequest. Driven by the sidebar
        // context menu (right-click → Rename…) on PM file rows.
        .sheet(item: $workspace.renameRequest) { request in
            RenameSheet(request: request, workspace: workspace)
        }
        // D23 phase 5 — Move modal sheet. Tree picker variant of
        // SaveAsSheet (no filename field). Bound to
        // workspace.moveRequest; driven by sidebar context menu
        // (right-click → Move to…) on PM file rows.
        .sheet(item: $workspace.moveRequest) { request in
            MoveSheet(request: request, workspace: workspace)
        }
        // D23.1 — Create Folder sheet. Bound to
        // workspace.createDirectoryRequest. Driven by sidebar
        // context menu (right-click → New Folder…) on PM directory
        // rows.
        .sheet(item: $workspace.createDirectoryRequest) { request in
            CreateDirectorySheet(request: request, workspace: workspace)
        }
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
            // D25 — wrap in `ScrollViewReader` so `revealInTree`'s
            // pending scroll-target can drive `proxy.scrollTo(nodeID,
            // anchor: .center)`. Each row's identity comes from
            // `ForEach(... id: \.id)` in `ConnectorTreeView`, so
            // `nodeID` matches the connector-qualified node id.
            ScrollViewReader { proxy in
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
                .onChange(of: workspace.pendingRevealNodeID) { newValue in
                    guard let id = newValue else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    workspace.clearReveal()
                }
            }
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
        // Connector-backed file. Async fetch; open via openFromConnector
        // which computes read-only/editable from connector.canWrite.
        // D19 phase 3 — PM files become editable here.
        Task {
            do {
                let (bytes, refreshedNode) = try await connector.openFile(node)
                let text = String(data: bytes, encoding: .utf8) ?? ""
                workspace.tabs.openFromConnector(content: text,
                                                 node: refreshedNode)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't open \(node.name)"
                alert.informativeText = "\(error)"
                alert.runModal()
            }
        }
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
