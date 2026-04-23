import AppKit
import Foundation

/// Watches a single file for external changes via NSFilePresenter.
/// When the file's contents change on disk, reads the new content and
/// invokes `onChange` on the main thread.
///
/// Spike-quality reconciliation is sufficient for D2: we deliver raw
/// new text; the caller decides whether to replace the buffer
/// (preserving caret where possible) or prompt the user. Level 2
/// agent-aware behaviors (diff view, actor attribution) are future
/// work — see `docs/vision.md` Principle 1 and the roadmap.
final class ExternalEditWatcher: NSObject, NSFilePresenter {

    // MARK: - NSFilePresenter

    var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main

    // MARK: - Callback

    var onChange: ((String) -> Void)?

    // MARK: - Lifecycle

    func watch(url: URL) {
        stop()
        presentedItemURL = url
        NSFileCoordinator.addFilePresenter(self)
    }

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
        let coordinator = NSFileCoordinator(filePresenter: self)
        var readError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
            guard let text = try? String(contentsOf: coordinatedURL, encoding: .utf8) else { return }
            onChange?(text)
        }
        if let readError {
            NSLog("ExternalEditWatcher: coordinated read failed: \(readError)")
        }
    }

    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        stop()
        completionHandler(nil)
    }
}
