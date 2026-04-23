import Foundation

/// Watches a directory for file-system events (add, delete, rename,
/// write) and invokes a debounced callback. Used by the workspace to
/// refresh the sidebar tree when an agent or external tool changes
/// the workspace contents.
///
/// Folder-level only — per-open-file reconcile is handled by
/// `ExternalEditWatcher` attached to each `EditorDocument`.
final class FolderTreeWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private var debounceWorkItem: DispatchWorkItem?

    init?(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.fileDescriptor = fd
        self.url = url
        self.onChange = onChange

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // Debounce bursts of writes into a single refresh.
            self.debounceWorkItem?.cancel()
            let item = DispatchWorkItem { self.onChange() }
            self.debounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        src.resume()
        self.source = src
    }

    deinit {
        debounceWorkItem?.cancel()
        source?.cancel()
    }
}
