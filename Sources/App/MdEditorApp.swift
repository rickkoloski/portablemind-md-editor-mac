import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single-window macOS app entry point. Open… button in the toolbar
/// lets the user pick a `.md` file; the selected URL binds into
/// EditorContainer.
///
/// No chrome beyond window + toolbar Open button at D2. Further
/// UI (formatting toolbar, folder tree, preferences) arrives in
/// subsequent deliverables per `docs/roadmap_ref.md`.
@main
struct MdEditorApp: App {
    @State private var fileURL: URL?

    var body: some Scene {
        WindowGroup {
            EditorContainer(fileURL: $fileURL)
                .frame(minWidth: 700, minHeight: 500)
                .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: openFile) {
                            Text("Open…")
                        }
                        .keyboardShortcut("o", modifiers: .command)
                        .accessibilityIdentifier(AccessibilityIdentifiers.openFileButton)
                    }
                }
        }
        .windowResizability(.contentSize)
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
