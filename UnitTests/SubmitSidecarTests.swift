// D30 phase 1 — SubmitSidecar wire-format + atomic-write invariants.
//
// Spec: docs/current_work/specs/d30_submit_handoff_spec.md (D14-D19 +
//       acceptance criteria § "Sidecar emission").
// Atomic-write test: spawn a tight-loop reader against the session dir
// while writes happen concurrently. Reader must see only fully-decoded
// payloads — never a partial JSON. Verifies the rename-into-place
// guarantee that CC sessions' fs.watch consumers rely on.

import Foundation
import XCTest
@testable import MdEditor

final class SubmitSidecarTests: XCTestCase {

    // MARK: - Wire format

    func testPayloadRoundTripsThroughJSON() throws {
        let payload = SubmitPayload(
            docPath: "/tmp/foo.md",
            docOrigin: "local",
            docID: "abc123def4567890abc123def4567890abc123def4567890abc123def4567890",
            sessionID: "cc1",
            submittedAt: "2026-05-11T15:22:33.421Z",
            submitter: "Rick K",
            message: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let decoded = try JSONDecoder().decode(SubmitPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testPayloadJSONKeysUseSnakeCase() throws {
        let payload = SubmitPayload(
            docPath: "/tmp/foo.md",
            docOrigin: "local",
            docID: "abc",
            sessionID: "cc1",
            submittedAt: "now",
            submitter: "me",
            message: "hello")

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["doc_path"])
        XCTAssertNotNil(json["doc_origin"])
        XCTAssertNotNil(json["doc_id"])
        XCTAssertNotNil(json["session_id"])
        XCTAssertNotNil(json["submitted_at"])
        XCTAssertNotNil(json["submitter"])
        XCTAssertNotNil(json["message"])
    }

    func testMessageNullEncodesCorrectly() throws {
        let payload = makePayload(sessionID: "cc1", message: nil)
        let data = try JSONEncoder().encode(payload)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"message\":null"))
    }

    // MARK: - Sidecar write

    func testWriteProducesFileAtExpectedPath() throws {
        let sessionID = uniqueSessionID()
        defer { cleanupSession(sessionID) }

        let payload = makePayload(sessionID: sessionID)
        let url = try SubmitSidecar.write(payload)

        let dir = try SubmitSidecar.directory(forSession: sessionID)
        XCTAssertTrue(url.path.hasPrefix(dir.path),
                      "Sidecar landed at \(url.path), expected prefix \(dir.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"))
    }

    func testWriteCreatesSessionDirIfMissing() throws {
        let sessionID = uniqueSessionID()
        defer { cleanupSession(sessionID) }

        let dir = try SubmitSidecar.directory(forSession: sessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))

        _ = try SubmitSidecar.write(makePayload(sessionID: sessionID))

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testWrittenFileDecodesAsOriginalPayload() throws {
        let sessionID = uniqueSessionID()
        defer { cleanupSession(sessionID) }

        let payload = makePayload(sessionID: sessionID)
        let url = try SubmitSidecar.write(payload)

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(SubmitPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testConcurrentWritesProduceDistinctFiles() throws {
        let sessionID = uniqueSessionID()
        defer { cleanupSession(sessionID) }

        let count = 10
        let urls = ConcurrentBag<URL>()
        let group = DispatchGroup()
        for i in 0..<count {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                let payload = self.makePayload(sessionID: sessionID, docID: "abcdef\(i)0000")
                if let url = try? SubmitSidecar.write(payload) {
                    urls.append(url)
                }
            }
        }
        group.wait()

        let collected = urls.snapshot()
        XCTAssertEqual(collected.count, count)
        XCTAssertEqual(Set(collected.map { $0.lastPathComponent }).count, count,
                       "Concurrent writes produced duplicate filenames")
    }

    func testAtomicWriteNoPartialReads() throws {
        let sessionID = uniqueSessionID()
        defer { cleanupSession(sessionID) }

        let dir = try SubmitSidecar.directory(forSession: sessionID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stop = AtomicFlag()
        let partialReads = AtomicCounter()
        let goodReads = AtomicCounter()

        let readerGroup = DispatchGroup()
        readerGroup.enter()
        DispatchQueue.global().async {
            defer { readerGroup.leave() }
            while !stop.isSet {
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil) else { continue }
                for fileURL in contents where fileURL.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: fileURL) else {
                        partialReads.increment()
                        continue
                    }
                    do {
                        _ = try JSONDecoder().decode(SubmitPayload.self, from: data)
                        goodReads.increment()
                    } catch {
                        partialReads.increment()
                    }
                }
            }
        }

        let writerGroup = DispatchGroup()
        let writeCount = 50
        for i in 0..<writeCount {
            writerGroup.enter()
            DispatchQueue.global().async {
                defer { writerGroup.leave() }
                let payload = self.makePayload(sessionID: sessionID, docID: "writer\(i)0000")
                _ = try? SubmitSidecar.write(payload)
            }
        }
        writerGroup.wait()

        Thread.sleep(forTimeInterval: 0.2)
        stop.set()
        readerGroup.wait()

        XCTAssertEqual(partialReads.value, 0,
                       "Reader saw partial/corrupt JSON \(partialReads.value) time(s)")
        XCTAssertGreaterThan(goodReads.value, 0,
                             "Reader didn't see any successful reads")
    }

    // MARK: - docID derivation (D17)

    func testDocIDForLocalIsStable() {
        let url = URL(fileURLWithPath: "/tmp/foo.md")
        let id1 = SubmitSidecar.docID(forLocal: url)
        let id2 = SubmitSidecar.docID(forLocal: url)
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id1.count, 64, "Expected 64 hex chars from SHA-256")
    }

    func testDocIDForLocalDiffersByPath() {
        let id1 = SubmitSidecar.docID(forLocal: URL(fileURLWithPath: "/tmp/foo.md"))
        let id2 = SubmitSidecar.docID(forLocal: URL(fileURLWithPath: "/tmp/bar.md"))
        XCTAssertNotEqual(id1, id2)
    }

    func testDocIDForLocalCanonicalizes() {
        let a = SubmitSidecar.docID(forLocal: URL(fileURLWithPath: "/tmp/./foo.md"))
        let b = SubmitSidecar.docID(forLocal: URL(fileURLWithPath: "/tmp/foo.md"))
        XCTAssertEqual(a, b)
    }

    // MARK: - Heartbeat path

    func testHeartbeatURLResolvesUnderSessionDir() throws {
        let url = try SubmitSidecar.heartbeatURL(forSession: "cc1")
        XCTAssertTrue(url.lastPathComponent == "heartbeat.json")
        XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent == "cc1")
    }

    // MARK: - Helpers

    private func uniqueSessionID() -> String {
        "test-\(UUID().uuidString)"
    }

    private func cleanupSession(_ sessionID: String) {
        guard let dir = try? SubmitSidecar.directory(forSession: sessionID) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private func makePayload(
        sessionID: String,
        docID: String = "deadbeef00000000",
        message: String? = nil
    ) -> SubmitPayload {
        SubmitPayload(
            docPath: "/tmp/foo.md",
            docOrigin: "local",
            docID: docID,
            sessionID: sessionID,
            submittedAt: ISO8601DateFormatter().string(from: Date()),
            submitter: "test",
            message: message)
    }
}

// MARK: - Test concurrency helpers

private final class AtomicFlag {
    private let lock = NSLock()
    private var flag = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}

private final class AtomicCounter {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private final class ConcurrentBag<T> {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    func snapshot() -> [T] { lock.lock(); defer { lock.unlock() }; return items }
}
