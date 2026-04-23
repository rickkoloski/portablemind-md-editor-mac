import AppKit
import Foundation

/// Watches a single file for external changes via NSFilePresenter.
/// When the file's mtime/contents change on disk, reads the new content
/// and invokes the `onChange` callback on the main thread.
///
/// Spike-level reconciliation: we deliver the raw new text; the caller
/// decides whether to replace the buffer (preserving caret if possible)
/// or prompt the user. No three-way merge logic here.
final class ExternalEditWatcher: NSObject, NSFilePresenter {

    // MARK: - NSFilePresenter

    var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main

    // MARK: - Callback

    var onChange: ((String) -> Void)?

    // MARK: - Lifecycle

    /// Register to watch `url`. If already watching another URL, stops
    /// that watcher first.
    func watch(url: URL) {
        stop()
        presentedItemURL = url
        NSFileCoordinator.addFilePresenter(self)
    }

    /// Deregister.
    func stop() {
        if presentedItemURL != nil {
            NSFileCoordinator.removeFilePresenter(self)
            presentedItemURL = nil
        }
    }

    deinit {
        stop()
    }

    // MARK: - NSFilePresenter callbacks

    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        // Coordinate the read so we don't race another writer.
        let coordinator = NSFileCoordinator(filePresenter: self)
        var readError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
            guard let text = try? String(contentsOf: coordinatedURL, encoding: .utf8) else {
                return
            }
            onChange?(text)
        }
        if let readError {
            NSLog("ExternalEditWatcher: coordinated read failed: \(readError)")
        }
    }

    // Move or delete — stop watching, but tell the caller by sending
    // an empty string. The caller can surface this however it wants.
    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        stop()
        completionHandler(nil)
    }
}
