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
        // Use `Window` (single-window) rather than `WindowGroup`:
        // WindowGroup spawns a new window on every external event
        // (URL scheme, document-open), which doesn't match our
        // single-window workspace model. D6 finding surfaced during
        // CLI dogfood — three `./scripts/md-editor …` invocations
        // produced three windows on one process.
        Window("MdEditor", id: "main") {
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
                    // All icons in one ToolbarItemGroup with an explicit
                    // vertical Rectangle as a visual divider between
                    // the file-mgmt group and the formatting group.
                    // (SwiftUI's Divider() renders horizontally in
                    // this context — needed an explicit shape.)
                    ToolbarItemGroup(placement: .automatic) {
                        Button(action: openFolder) {
                            Label("Open Folder…", systemImage: "folder")
                                .labelStyle(.iconOnly)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color(red: 222/255, green: 222/255, blue: 222/255))
                        }
                        .help("Open Folder… (⇧⌘O)")
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                        .accessibilityIdentifier(AccessibilityIdentifiers.openFolderMenuItem)
                        .accessibilityLabel("Open Folder…")

                        Button(action: openFile) {
                            Label("Open…", systemImage: "doc.text")
                                .labelStyle(.iconOnly)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color(red: 222/255, green: 222/255, blue: 222/255))
                        }
                        .help("Open… (⌘O)")
                        .keyboardShortcut("o", modifiers: .command)
                        .accessibilityIdentifier(AccessibilityIdentifiers.openFileButton)
                        .accessibilityLabel("Open…")

                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 16)
                            .padding(.horizontal, 4)

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
