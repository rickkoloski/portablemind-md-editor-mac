import CryptoKit
import Foundation

/// D30 — Submit sidecar wire format + on-disk emission.
///
/// One sidecar file per Submit event. Per-session sidecar directory
/// under the editor's Application Support container so each CC session
/// `fs.watch`es exactly one path. Atomic write (write-to-sibling-tmp
/// + rename) ensures concurrent watchers never observe a partial file.

struct SubmitPayload: Codable, Equatable {
    let docPath: String
    let docOrigin: String
    let docID: String
    let sessionID: String
    let submittedAt: String
    let submitter: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case docPath = "doc_path"
        case docOrigin = "doc_origin"
        case docID = "doc_id"
        case sessionID = "session_id"
        case submittedAt = "submitted_at"
        case submitter
        case message
    }

    // Emit `"message": null` rather than omitting the key when nil —
    // wire-format stability across the v1→v1.1 boundary (v1.1 adds
    // Submit-with-message UI; agents shouldn't need to distinguish
    // absent-key from null-value).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(docPath, forKey: .docPath)
        try container.encode(docOrigin, forKey: .docOrigin)
        try container.encode(docID, forKey: .docID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(submittedAt, forKey: .submittedAt)
        try container.encode(submitter, forKey: .submitter)
        if let message {
            try container.encode(message, forKey: .message)
        } else {
            try container.encodeNil(forKey: .message)
        }
    }
}

enum SubmitSidecarError: LocalizedError {
    case sidecarBaseUnavailable
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .sidecarBaseUnavailable:
            return "Could not resolve the Application Support directory for the editor."
        case .writeFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

enum SubmitSidecar {
    static let bundleIdentifier = "ai.portablemind.md-editor"

    /// `~/Library/Application Support/ai.portablemind.md-editor/submits/`.
    static func sidecarBase() throws -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let support = urls.first else {
            throw SubmitSidecarError.sidecarBaseUnavailable
        }
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("submits", isDirectory: true)
    }

    static func directory(forSession sessionID: String) throws -> URL {
        try sidecarBase().appendingPathComponent(sessionID, isDirectory: true)
    }

    static func heartbeatURL(forSession sessionID: String) throws -> URL {
        try directory(forSession: sessionID).appendingPathComponent("heartbeat.json")
    }

    /// Atomic write of a Submit payload. Filename is
    /// `<unix-ms>-<short-doc-hash>.json`. Returns the URL where the
    /// file landed.
    @discardableResult
    static func write(_ payload: SubmitPayload) throws -> URL {
        let sessionDir: URL
        do {
            sessionDir = try directory(forSession: payload.sessionID)
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch let err as SubmitSidecarError {
            throw err
        } catch {
            throw SubmitSidecarError.writeFailed(underlying: error)
        }

        let unixMs = Int(Date().timeIntervalSince1970 * 1000)
        let shortHash = String(payload.docID.prefix(8))
        let filename = "\(unixMs)-\(shortHash).json"
        let finalURL = sessionDir.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw SubmitSidecarError.writeFailed(underlying: error)
        }

        // Data.write(options: .atomic) writes to a sibling tmp and
        // renames atomically — the wire-format guarantee that no
        // watcher reads a partial JSON file.
        do {
            try data.write(to: finalURL, options: .atomic)
        } catch {
            throw SubmitSidecarError.writeFailed(underlying: error)
        }

        return finalURL
    }

    /// D17 — SHA-256 hex of a Local URL's canonical path.
    static func docID(forLocal url: URL) -> String {
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
