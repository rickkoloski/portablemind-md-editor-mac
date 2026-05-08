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

            // Name (with disabled state for unsupported files).
            // D21 — Local root row swaps to home-relative path when
            // the user has toggled "Show Path in Tree."
            Text(displayedName)
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

            // D21 — toggle the root row's display between just-name
            // and full home-relative path. Local roots only;
            // PortableMind root has no analogous path concept.
            // Persists per-connector via UserDefaults.
            if level == 0, node.connector.id == "local" {
                Divider()
                Button(viewModel.rootShowsPath
                       ? "Hide Path in Tree"
                       : "Show Path in Tree") {
                    viewModel.toggleRootShowsPath()
                }
            }

            // D23 phase 4 + 5 — Rename + Move (PM file rows only).
            // Connector protocol's renameFile + moveFile are
            // implemented for PortableMind (PATCH llm_files/:id) and
            // Local (FileManager.moveItem). v1 surfaces them for PM
            // files first since that's the dogfood-blocking case;
            // Local surfacing is in the deferred-follow-ups list.
            // Disabled when canWrite returns false.
            if node.kind == .file, node.connector is PortableMindConnector {
                Divider()
                Button("Rename…") {
                    WorkspaceStore.shared.requestRename(for: node)
                }
                .disabled(!node.connector.canWrite(node))
                .accessibilityIdentifier(
                    AccessibilityIdentifiers.folderTreeRowRename(id: node.id))
                Button("Move to…") {
                    WorkspaceStore.shared.requestMove(for: node)
                }
                .disabled(!node.connector.canWrite(node))
                .accessibilityIdentifier(
                    AccessibilityIdentifiers.folderTreeRowMove(id: node.id))
                // D23.1 — Delete file (PM only in v1).
                Button("Delete…") {
                    confirmAndDeleteFile(node)
                }
                .disabled(!node.connector.canWrite(node))
                .accessibilityIdentifier(
                    AccessibilityIdentifiers.folderTreeRowDelete(id: node.id))
            }
            // D23.1 — New Folder + Delete on PM directory rows.
            // Local directories surface only in the deferred-follow-ups
            // list (filesystem create/delete already work via the
            // connector but the UX needs Trash/confirmation thinking).
            if node.kind == .directory, node.connector is PortableMindConnector {
                Divider()
                Button("New Folder…") {
                    WorkspaceStore.shared.requestCreateDirectory(in: node)
                }
                .accessibilityIdentifier(
                    AccessibilityIdentifiers.folderTreeRowNewFolder(id: node.id))
                // Don't surface Delete on the connector's own root row
                // (level == 0); deleting the root would be nonsensical
                // and the server probably 404's it anyway. Just guard.
                if level > 0 {
                    Button("Delete…") {
                        confirmAndDeleteDirectory(node)
                    }
                    .accessibilityIdentifier(
                        AccessibilityIdentifiers.folderTreeRowDelete(id: node.id))
                }
            }
        }
    }

    /// D23.1 — confirmation NSAlert + delete file. Q1: stock NSAlert
    /// (modal, accessible, no custom UI work). Q2: hard delete; the
    /// server already deletes hard so the model matches.
    private func confirmAndDeleteFile(_ node: ConnectorNode) {
        let alert = NSAlert()
        alert.messageText = "Delete '\(node.name)'?"
        alert.informativeText = "This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")
        let response = alert.runModal()
        guard response == .alertSecondButtonReturn else { return }
        Task { @MainActor in
            do {
                try await PMFileOperations.delete(
                    node: node,
                    store: WorkspaceStore.shared)
            } catch {
                // Surface the error in a follow-up alert. v1 keeps it
                // simple; future polish can make this an inline banner.
                let err = NSAlert()
                err.messageText = "Delete failed"
                err.informativeText = "\(error)"
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    /// D23.1 — confirmation NSAlert + delete directory. Surfaces the
    /// child count from already-loaded data when available (Q4).
    private func confirmAndDeleteDirectory(_ node: ConnectorNode) {
        let alert = NSAlert()
        alert.messageText = "Delete '\(node.name)'?"
        let count = childCountIfKnown(for: node)
        if let count, count > 0 {
            alert.informativeText =
                "This will also delete \(count) item(s) inside. This can't be undone."
        } else {
            alert.informativeText = "This can't be undone."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")
        let response = alert.runModal()
        guard response == .alertSecondButtonReturn else { return }
        Task { @MainActor in
            do {
                try await PMFileOperations.delete(
                    node: node,
                    store: WorkspaceStore.shared)
            } catch {
                let err = NSAlert()
                err.messageText = "Delete failed"
                err.informativeText = "\(error)"
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    /// Best-effort child count for the delete-directory confirmation.
    /// Reads from the cached children if loaded; returns nil otherwise.
    /// Q4 says we may fall back to a server count fetch — v1 just
    /// uses the cached value or omits the count from the message.
    private func childCountIfKnown(for node: ConnectorNode) -> Int? {
        if let count = node.fileCount, count > 0 { return count }
        if let kids = viewModel.childrenIfLoaded(at: node.path) {
            return kids.count
        }
        return nil
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

    /// D21 — what to display as the row's name. Local root rows can
    /// be toggled to show the full home-relative path instead of just
    /// the directory's last component (per `viewModel.rootShowsPath`).
    /// Everything else shows `node.name` unchanged.
    private var displayedName: String {
        if level == 0,
           node.connector.id == "local",
           viewModel.rootShowsPath {
            return PathFormatting.displayLocalPath(node.path)
        }
        return node.name
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
