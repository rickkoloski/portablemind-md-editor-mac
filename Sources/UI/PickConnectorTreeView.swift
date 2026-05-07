// D23 phase 2 — directory-only single-selection tree picker for the
// Save As / New File / Move modals. Reuses `ConnectorTreeViewModel`
// so async children loading, expand state, and error display work the
// same way as the sidebar's `ConnectorTreeView`. Differences:
//
// 1. Files are hidden — only directories are clickable.
// 2. Selection is a single directory `ConnectorNode?` bound to a
//    parent state.
// 3. The selected row is highlighted; clicking a directory both selects
//    it AND expands it (a single click does both — feels lighter than
//    Finder's "click to select, double to expand" inside a modal).

import SwiftUI

struct PickConnectorTreeView: View {
    @ObservedObject var viewModel: ConnectorTreeViewModel
    @Binding var selection: ConnectorNode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PickRowView(
                    node: viewModel.connector.rootNode,
                    level: 0,
                    viewModel: viewModel,
                    selection: $selection)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier(
            "md-editor.save-as-modal.tree.\(viewModel.connector.id)")
    }
}

private struct PickRowView: View {
    let node: ConnectorNode
    let level: Int
    @ObservedObject var viewModel: ConnectorTreeViewModel
    @Binding var selection: ConnectorNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if viewModel.isExpanded(node.path), let children = directoryChildren {
                ForEach(children, id: \.id) { child in
                    PickRowView(
                        node: child,
                        level: level + 1,
                        viewModel: viewModel,
                        selection: $selection)
                }
            }
        }
    }

    @ViewBuilder
    private var row: some View {
        HStack(spacing: 6) {
            if level > 0 {
                Spacer().frame(width: CGFloat(level) * 14)
            }
            Image(systemName: viewModel.isExpanded(node.path)
                  ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if viewModel.isLoading(node.path) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            (selection?.id == node.id)
                ? Color.accentColor.opacity(0.18)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            select()
        }
        .accessibilityIdentifier(
            "md-editor.save-as-modal.tree.row.\(node.id)")
    }

    private func select() {
        // Single click: select + expand. The user almost always wants to
        // go deeper after picking; if they don't, the row is selected
        // anyway and Save uses it as the target.
        selection = node
        if !viewModel.isExpanded(node.path) {
            viewModel.toggle(path: node.path)
        }
    }

    /// Children of `node` that are directories — files are hidden in
    /// the picker since you can only save INTO a directory.
    private var directoryChildren: [ConnectorNode]? {
        guard let kids = viewModel.childrenIfLoaded(at: node.path) else {
            return nil
        }
        return kids.filter { $0.kind == .directory }
    }
}
