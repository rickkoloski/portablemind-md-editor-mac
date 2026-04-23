import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single-window macOS app entry point. D5 extends D2's toolbar with
/// the formatting buttons and adds a View menu with Show/Hide Toolbar.
@main
struct MdEditorApp: App {
    @State private var fileURL: URL?
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            EditorContainer(fileURL: $fileURL)
                .frame(minWidth: 700, minHeight: 500)
                .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
                .toolbar {
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
                .background(WindowAccessor { window in
                    // Toggle the toolbar row via AppKit's native
                    // NSWindow.toolbar.isVisible. SwiftUI's
                    // .toolbar(.hidden, for: .windowToolbar) hides the
                    // whole toolbar region (title bar + traffic lights
                    // included) even under .expanded style. NSWindow
                    // makes the distinction natively.
                    window.toolbar?.isVisible = settings.toolbarVisible
                })
        }
        .windowResizability(.contentSize)
        // Expanded toolbar style puts the title bar and toolbar in
        // separate rows so hiding the toolbar doesn't take the window
        // chrome (traffic lights, title) with it. Matches the Apple
        // best practice Rick called out during D5 validation.
        .windowToolbarStyle(.expanded)
        .commands {
            // Slot the toggle into the existing (system-provided) View
            // menu at the toolbar-command placement, rather than
            // creating a second "View" menu with CommandMenu.
            CommandGroup(replacing: .toolbar) {
                Button(settings.toolbarVisible ? "Hide Toolbar" : "Show Toolbar") {
                    settings.toolbarVisible.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .accessibilityIdentifier(AccessibilityIdentifiers.viewMenuToggleToolbar)
            }
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
        if panel.runModal() == .OK {
            fileURL = panel.url
        }
    }
}
