import SwiftUI

/// Left sidebar showing the workspace root as a collapsible tree.
/// SwiftUI `OutlineGroup` loads children lazily via the connector's
/// `childrenSync(of:)`, so deep trees don't walk eagerly.
///
/// D18 phase 1: takes a `ConnectorNode` root from the active
/// connector. Phase 3 generalizes to multiple roots (Local + PM).
struct FolderTreeView: View {
    let rootNode: ConnectorNode
    let onSelectFile: (ConnectorNode) -> Void

    var body: some View {
        // Render the root's direct children as top-level rows — that
        // implicitly expands the root one level. Each child directory
        // gets its own OutlineGroup, which starts collapsed and
        // expands on click.
        List {
            ForEach(rootNode.children ?? [], id: \.id) { node in
                if node.kind == .directory {
                    OutlineGroup(node, children: \.children) { subnode in
                        FolderRowView(node: subnode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if subnode.kind == .file && subnode.isSupported {
                                    onSelectFile(subnode)
                                }
                            }
                            .accessibilityIdentifier(
                                AccessibilityIdentifiers.folderTreeRow(id: subnode.id))
                    }
                } else {
                    FolderRowView(node: node)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if node.isSupported { onSelectFile(node) }
                        }
                        .accessibilityIdentifier(
                            AccessibilityIdentifiers.folderTreeRow(id: node.id))
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier(AccessibilityIdentifiers.folderTree)
    }
}

private struct FolderRowView: View {
    let node: ConnectorNode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.kind == .directory ? "folder" : "doc.text")
                .foregroundStyle(node.kind == .directory ? .secondary : .primary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(node.isSupported ? .primary : Color.secondary)
            Spacer(minLength: 0)
        }
        .help(node.isSupported ? "" : "file type not supported")
    }
}
