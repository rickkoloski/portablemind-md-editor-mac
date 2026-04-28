// D18 phase 3 — recursive view rendering one connector's tree section
// in the sidebar. Replaces D6's FolderTreeView (which was OutlineGroup
// + sync KeyPath only). This view drives off ConnectorTreeViewModel
// so the same code path handles sync (Local) and async (PortableMind)
// connectors uniformly.

import SwiftUI

struct ConnectorTreeView: View {
    @ObservedObject var viewModel: ConnectorTreeViewModel
    let onSelectFile: (ConnectorNode) -> Void

    var body: some View {
        ConnectorRowView(
            node: viewModel.connector.rootNode,
            level: 0,
            viewModel: viewModel,
            onSelectFile: onSelectFile
        )
        .accessibilityIdentifier(
            "md-editor.sidebar.connector-root.\(viewModel.connector.id)")
    }
}

private struct ConnectorRowView: View {
    let node: ConnectorNode
    let level: Int
    @ObservedObject var viewModel: ConnectorTreeViewModel
    let onSelectFile: (ConnectorNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if viewModel.isExpanded(node.path) {
                expandedContent
            }
        }
    }

    @ViewBuilder
    private var row: some View {
        HStack(spacing: 6) {
            // Indentation
            if level > 0 {
                Spacer()
                    .frame(width: CGFloat(level) * 14)
            }

            // Disclosure chevron / placeholder
            if node.kind == .directory {
                Button {
                    viewModel.toggle(path: node.path)
                } label: {
                    Image(systemName: viewModel.isExpanded(node.path)
                          ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 12)
            }

            // Icon
            Image(systemName: iconName)
                .foregroundStyle(node.kind == .directory ? .secondary : .primary)
                .frame(width: 16)

            // Name (with disabled state for unsupported files)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(node.isSupported ? .primary : Color.secondary)
                .fontWeight(level == 0 ? .semibold : .regular)

            // Cross-tenant badge (PortableMind only; visible when
            // node.tenant != currentUser.tenant).
            if let tenant = node.tenant, viewModel.isCrossTenant(node) {
                TenantInitialsBadge(tenant: tenant)
            }

            // In-flight spinner
            if viewModel.isLoading(node.path) {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 2)
            }

            Spacer(minLength: 0)

            // File-count caption (directories only, when known + > 0)
            if node.kind == .directory,
               let count = node.fileCount, count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .help(rowHelpText)
        .accessibilityIdentifier(
            AccessibilityIdentifiers.folderTreeRow(id: node.id))
        .accessibilityHint(node.isSupported ? "" : "file type not supported")
        .contextMenu {
            // D21 — Copy Path / Copy Relative Path. VS Code-style.
            // Same handles for any tree row: local files/folders and
            // PortableMind file/folder nodes. Path semantics differ
            // by connector — see PathFormatting.
            Button("Copy Path") {
                PathFormatting.copyToClipboard(
                    PathFormatting.absolutePathForCopy(node))
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button("Copy Relative Path") {
                PathFormatting.copyToClipboard(
                    PathFormatting.relativePathForCopy(node))
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let error = viewModel.errorMessage(at: node.path) {
            HStack(spacing: 6) {
                Spacer().frame(width: CGFloat(level + 1) * 14)
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        } else if let children = viewModel.childrenIfLoaded(at: node.path) {
            ForEach(children, id: \.id) { child in
                ConnectorRowView(
                    node: child,
                    level: level + 1,
                    viewModel: viewModel,
                    onSelectFile: onSelectFile
                )
            }
        }
        // Loading state shows in the spinner on the parent row;
        // don't draw a placeholder list here.
    }

    private var iconName: String {
        if level == 0 {
            return node.connector.rootIconName
        }
        return node.kind == .directory ? "folder" : "doc.text"
    }

    /// D21 — tooltip text. Local root rows show the full `~`-prefixed
    /// path (so users with multiple `src/...` projects open can
    /// distinguish them at a glance). Unsupported file rows show the
    /// "not supported" hint. Other rows show nothing.
    private var rowHelpText: String {
        if level == 0, node.connector.id == "local" {
            return PathFormatting.displayLocalPath(node.path)
        }
        if !node.isSupported { return "file type not supported" }
        return ""
    }

    private func handleTap() {
        switch node.kind {
        case .directory:
            viewModel.toggle(path: node.path)
        case .file:
            if node.isSupported {
                onSelectFile(node)
            }
        }
    }
}
