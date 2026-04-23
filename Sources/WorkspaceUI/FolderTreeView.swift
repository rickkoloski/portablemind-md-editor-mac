import SwiftUI

/// Left sidebar showing the workspace root as a collapsible tree.
/// SwiftUI `OutlineGroup` loads children lazily via the
/// `FolderTreeLoader`, so deep trees don't walk eagerly.
struct FolderTreeView: View {
    let rootNode: FolderNode
    let onSelectFile: (URL) -> Void

    var body: some View {
        // Render the root's direct children as top-level rows — that
        // implicitly expands the root one level. Each child directory
        // gets its own OutlineGroup, which starts collapsed and
        // expands on click.
        List {
            ForEach(rootNode.children ?? [], id: \.id) { node in
                if node.isDirectory {
                    OutlineGroup(node, children: \.children) { subnode in
                        FolderRowView(node: subnode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !subnode.isDirectory {
                                    onSelectFile(subnode.url)
                                }
                            }
                            .accessibilityIdentifier(AccessibilityIdentifiers.folderTreeRow(url: subnode.url))
                    }
                } else {
                    FolderRowView(node: node)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectFile(node.url) }
                        .accessibilityIdentifier(AccessibilityIdentifiers.folderTreeRow(url: node.url))
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier(AccessibilityIdentifiers.folderTree)
    }
}

private struct FolderRowView: View {
    let node: FolderNode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(node.isDirectory ? .secondary : .primary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}
