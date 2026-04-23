import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single-window macOS app entry point. D6 rewires the scene to host
/// the workspace (sidebar + tabs + editor) instead of a single-file
/// editor container.
@main
struct MdEditorApp: App {
    @ObservedObject private var workspace = WorkspaceStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            WorkspaceView(workspace: workspace, settings: settings)
                .frame(minWidth: 900, minHeight: 560)
                .background(WindowAccessor { window in
                    window.toolbar?.isVisible = settings.toolbarVisible
                })
                .onAppear {
                    workspace.restoreFromBookmarks()
                }
                .onOpenURL { url in
                    URLSchemeHandler.handle(url, workspace: workspace)
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: openFolder) { Text("Open Folder…") }
                            .keyboardShortcut("o", modifiers: [.command, .shift])
                            .accessibilityIdentifier(AccessibilityIdentifiers.openFolderMenuItem)
                    }
                    ToolbarItem(placement: .navigation) {
                        Button(action: openFile) { Text("Open…") }
                            .keyboardShortcut("o", modifiers: .command)
                            .accessibilityIdentifier(AccessibilityIdentifiers.openFileButton)
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        ToolbarButton(action: .bold)
                        ToolbarButton(action: .italic)
                        ToolbarButton(action: .inlineCode)
                        ToolbarButton(action: .link)
                        HeadingToolbarMenu()
                        ToolbarButton(action: .bulletList)
                        ToolbarButton(action: .numberedList)
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.expanded)
        .commands {
            CommandGroup(replacing: .toolbar) {
                Button(settings.toolbarVisible ? "Hide Toolbar" : "Show Toolbar") {
                    settings.toolbarVisible.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .accessibilityIdentifier(AccessibilityIdentifiers.viewMenuToggleToolbar)
            }
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { openFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            workspace.setRoot(url: url, stopAccessing: {
                url.stopAccessingSecurityScopedResource()
            })
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") {
            types.insert(md, at: 0)
        }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            _ = workspace.tabs.open(fileURL: url)
        }
    }
}
