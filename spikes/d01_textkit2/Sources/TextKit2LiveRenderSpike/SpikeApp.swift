import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single-window macOS app. Open… button in the toolbar lets you pick a
/// `.md` file; the selected URL is piped into EditorContainer. No other
/// chrome — this is a spike.
@main
struct TextKit2LiveRenderSpikeApp: App {
    @State private var fileURL: URL?

    var body: some Scene {
        WindowGroup {
            EditorContainer(fileURL: $fileURL)
                .frame(minWidth: 700, minHeight: 500)
                .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open…") { openFile() }
                            .keyboardShortcut("o", modifiers: .command)
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
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [md, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        if panel.runModal() == .OK {
            fileURL = panel.url
        }
    }
}
