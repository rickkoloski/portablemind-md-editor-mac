import SwiftUI

/// Top-level workspace layout — sidebar (folder tree) on the left,
/// main area (tab bar + editor / empty state) on the right.
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
        if let rootNode = workspace.rootNode {
            FolderTreeView(rootNode: rootNode) { node in
                _ = workspace.tabs.open(fileURL: URL(fileURLWithPath: node.path))
            }
        } else {
            VStack(spacing: 8) {
                Text("No folder open")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("File → Open Folder… or drop a folder here (soon).")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        WorkspaceDetailView(tabs: workspace.tabs)
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
