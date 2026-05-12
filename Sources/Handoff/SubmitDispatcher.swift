import AppKit
import Foundation

/// D30 phase 5 — Submit verb dispatcher.
///
/// One entry point: `SubmitDispatcher.submit(document:message:)`.
/// Save-then-Submit semantics (D14): if the document is dirty, save
/// first; on save failure (incl. D19 PM conflict-detection modal
/// returning cancel/error) the sidecar is NOT written and the caller
/// re-runs after the user resolves. On sidecar write failure (D16)
/// the error propagates to the caller, which presents NSAlert.
///
/// Origin routing (D7): both `.local` and `.portableMind` write
/// sidecars in v1. Connected-mode (PM `StatusApplication` transition)
/// deferred to the D20-era follow-up.
@MainActor
enum SubmitDispatcher {

    enum DispatchError: LocalizedError {
        case noInterestedSession
        case saveBeforeSubmitFailed(underlying: Error)
        case sidecarWriteFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noInterestedSession:
                return "No session is waiting on this document."
            case .saveBeforeSubmitFailed(let underlying):
                return underlying.localizedDescription
            case .sidecarWriteFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    /// Submit the document. Saves first if dirty; writes the sidecar
    /// on save success. Returns the sidecar URL.
    @discardableResult
    static func submit(document: EditorDocument,
                       message: String? = nil) async throws -> URL {
        guard let interest = document.interestedSessions.first else {
            throw DispatchError.noInterestedSession
        }

        if document.dirty {
            do {
                try await document.save(force: false)
            } catch {
                throw DispatchError.saveBeforeSubmitFailed(underlying: error)
            }
        }

        let payload = makePayload(for: document, session: interest, message: message)
        do {
            return try SubmitSidecar.write(payload)
        } catch {
            throw DispatchError.sidecarWriteFailed(underlying: error)
        }
    }

    private static func makePayload(
        for document: EditorDocument,
        session: SessionInterest,
        message: String?
    ) -> SubmitPayload {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let docOrigin: String
        let docID: String
        let docPath: String
        switch document.origin {
        case .local:
            docOrigin = "local"
            if let url = document.url {
                docPath = url.standardizedFileURL.path
                docID = SubmitSidecar.docID(forLocal: url)
            } else {
                // Untitled local. Submit affordance shouldn't be reachable
                // (no session_id can have been passed via CLI for an
                // untitled doc), but encode defensively.
                docPath = ""
                docID = "untitled"
            }
        case .portableMind(let connectorID, let fileID, let displayPath):
            docOrigin = "portableMind"
            docPath = displayPath
            docID = "\(connectorID):file:\(fileID)"
        }

        return SubmitPayload(
            docPath: docPath,
            docOrigin: docOrigin,
            docID: docID,
            sessionID: session.sessionID,
            submittedAt: iso.string(from: Date()),
            submitter: NSFullUserName(),
            message: message)
    }
}
