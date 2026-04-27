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
                    // TEST-HARNESS: start the debug command-file poller
                    // so external drivers can inspect / drive editor
                    // state. Compiled out of release builds.
                    #if DEBUG
                    HarnessCommandPoller.shared.start()
                    #endif
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
                    if settings.debugHUDVisible {
                        ToolbarItemGroup(placement: .primaryAction) {
                            DebugProbeHUD()
                        }
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

                Button(settings.lineNumbersVisible ? "Hide Line Numbers" : "Show Line Numbers") {
                    settings.lineNumbersVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .accessibilityIdentifier(AccessibilityIdentifiers.viewMenuToggleLineNumbers)

                Button(settings.debugHUDVisible ? "Hide Debug HUD" : "Show Debug HUD") {
                    settings.debugHUDVisible.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { openFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            // D14: Save / Save As. Operates on the focused document.
            CommandGroup(replacing: .saveItem) {
                Button("Save") { saveFocused() }
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuSave)
                Button("Save As…") { saveAsFocused() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .accessibilityIdentifier(AccessibilityIdentifiers.fileMenuSaveAs)
            }
#if DEBUG
            // D18 phase 2: dev-only "Set PortableMind Token…" menu
            // entry. Replaced by D19's connection-management UX once
            // sign-in is real.
            CommandMenu("Debug") {
                Button("Set PortableMind Token…") { setPortableMindToken() }
                Button("Clear PortableMind Token") { clearPortableMindToken() }
            }
#endif
        }
    }

#if DEBUG
    private func setPortableMindToken() {
        let alert = NSAlert()
        alert.messageText = "Set PortableMind Token"
        alert.informativeText = "Paste the bearer token. Lives in the macOS Keychain under service ai.portablemind.md-editor.harmoniq-token."
        alert.alertStyle = .informational
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        if let existing = try? KeychainTokenStore.shared.load() {
            field.stringValue = existing ?? ""
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try KeychainTokenStore.shared.save(token: token)
        } catch {
            let err = NSAlert(error: error)
            err.runModal()
        }
    }

    private func clearPortableMindToken() {
        do {
            try KeychainTokenStore.shared.clear()
        } catch {
            let err = NSAlert(error: error)
            err.runModal()
        }
    }
#endif

    private func saveFocused() {
        guard let doc = workspace.tabs.focused else { return }
        if doc.url == nil {
            // Untitled — Save behaves like Save As.
            saveAsFocused()
            return
        }
        do {
            try doc.save()
        } catch {
            presentSaveError(error)
        }
    }

    private func saveAsFocused() {
        guard let doc = workspace.tabs.focused else { return }
        let panel = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") {
            types.insert(md, at: 0)
        }
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = doc.url?.lastPathComponent ?? "Untitled.md"
        if let parent = doc.url?.deletingLastPathComponent() {
            panel.directoryURL = parent
        }
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        do {
            try doc.saveAs(to: chosen)
        } catch {
            presentSaveError(error)
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Save Failed"
        alert.runModal()
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
