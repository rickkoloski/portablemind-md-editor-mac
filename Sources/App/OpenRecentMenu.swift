import SwiftUI

/// D31 — File → Open Recent submenu contents. Renders MRU files first,
/// then a "Recent Folders" sub-section, then a "Clear Menu" item. Empty
/// state shows a single disabled `(No Recent Files)` placeholder.
///
/// Unavailable entries (missing file / unloaded PM connector) stay
/// listed but disabled, so the user can see that the entry existed
/// recently and what's keeping it from opening.
@MainActor
struct OpenRecentMenu: View {
    @ObservedObject var recents: RecentItemsStore
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Group {
            if recents.entries.isEmpty && recents.folders.isEmpty {
                // SwiftUI Text inside Menu doesn't reliably propagate
                // accessibilityIdentifier through the NSMenu AX bridge;
                // a disabled Button does, which keeps the placeholder
                // targetable from XCUITest.
                Button("(No Recent Files)") { }
                    .disabled(true)
                    .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuOpenRecentEmpty)
            } else {
                fileItems
                if !recents.folders.isEmpty {
                    Divider()
                    Button("Recent Folders") { }
                        .disabled(true)
                        .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuOpenRecentFoldersHeader)
                    folderItems
                }
                Divider()
                Button("Clear Menu") { recents.clear() }
                    .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuOpenRecentClear)
            }
        }
    }

    @ViewBuilder
    private var fileItems: some View {
        ForEach(Array(recents.entries.enumerated()), id: \.element.id) { index, entry in
            let available = entry.isAvailable(connectors: workspace.connectors)
            Button(menuTitle(for: entry, available: available)) {
                workspace.openRecentEntry(entry)
            }
            .help(entry.tooltip)
            .disabled(!available)
            .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuOpenRecentItem(index: index))
        }
    }

    @ViewBuilder
    private var folderItems: some View {
        ForEach(Array(recents.folders.enumerated()), id: \.element.path) { index, folder in
            let available = folder.isAvailable
            Button(folder.displayName + (available ? "" : "  (unavailable)")) {
                workspace.openRecentFolder(folder)
            }
            .help(folder.tooltip)
            .disabled(!available)
            .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuOpenRecentFolder(index: index))
        }
    }

    private func menuTitle(for entry: RecentEntry, available: Bool) -> String {
        if available { return entry.displayName }
        return entry.displayName + "  (unavailable)"
    }
}
