// D31 Phase 1 — RecentItemsStore foundation.
//
// Spec: docs/current_work/specs/d31_mru_and_session_restore_spec.md
// Plan: docs/current_work/planning/d31_mru_and_session_restore_plan.md §Phase 1
//
// All tests use a dedicated UserDefaults suite per test to keep the
// user's real prefs intact and to start every case from a known-empty
// state. The fixture helper `makeStore()` returns a fresh store wired
// to a fresh suite.

import Foundation
import XCTest
@testable import MdEditor

@MainActor
final class RecentItemsStoreTests: XCTestCase {

    // MARK: - Fixture

    private func makeStore(suiteName: String = UUID().uuidString) -> (RecentItemsStore, UserDefaults) {
        let suite = UserDefaults(suiteName: suiteName)!
        // Belt + braces — even a fresh suite name can persist between
        // test runs if a prior crash left bytes on disk.
        suite.removePersistentDomain(forName: suiteName)
        return (RecentItemsStore(defaults: suite), suite)
    }

    // MARK: - Empty defaults

    func testEmptyDefaultsYieldsEmptyState() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertEqual(store.sessionState, SessionState())
    }

    // MARK: - Recording

    func testRecordLocalNewestFirst() {
        let (store, _) = makeStore()
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/b.md"))
        XCTAssertEqual(store.entries.map(\.displayName), ["b.md", "a.md"])
    }

    func testRecordLocalDedupAndPromote() {
        let (store, _) = makeStore()
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/b.md"))
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.map(\.displayName), ["a.md", "b.md"])
    }

    func testRecordLocalLRUCap() {
        let (store, _) = makeStore()
        for i in 0..<20 {
            store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/file\(i).md"))
        }
        XCTAssertEqual(store.entries.count, RecentItemsStore.maxEntries)
        XCTAssertEqual(store.entries.first?.displayName, "file19.md")
        XCTAssertEqual(store.entries.last?.displayName, "file5.md")
    }

    func testRecordPMIdentityByConnectorAndFileID() {
        let (store, _) = makeStore()
        store.recordOpen(connectorID: "portablemind", fileID: 916,
                         displayPath: "rick/test-sample.md", name: "test-sample.md",
                         lastSeenUpdatedAt: nil)
        store.recordOpen(connectorID: "portablemind", fileID: 917,
                         displayPath: "rick/other.md", name: "other.md",
                         lastSeenUpdatedAt: nil)
        // Re-record the first PM file — should de-dup, not duplicate.
        store.recordOpen(connectorID: "portablemind", fileID: 916,
                         displayPath: "rick/test-sample.md", name: "test-sample.md",
                         lastSeenUpdatedAt: nil)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.displayName, "test-sample.md")
    }

    func testRecordPMRefreshesDisplayFields() {
        let (store, _) = makeStore()
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordOpen(connectorID: "portablemind", fileID: 916,
                         displayPath: "rick/old-path.md", name: "old-path.md",
                         lastSeenUpdatedAt: originalDate)
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        store.recordOpen(connectorID: "portablemind", fileID: 916,
                         displayPath: "rick/new-path.md", name: "new-path.md",
                         lastSeenUpdatedAt: newDate)
        XCTAssertEqual(store.entries.count, 1)
        guard case let .portableMind(_, _, displayPath, name, lastSeen) = store.entries[0].kind else {
            return XCTFail("expected PM kind")
        }
        XCTAssertEqual(displayPath, "rick/new-path.md")
        XCTAssertEqual(name, "new-path.md")
        XCTAssertEqual(lastSeen, newDate)
    }

    func testLocalAndPMAreDistinctEntries() {
        let (store, _) = makeStore()
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/test-sample.md"))
        store.recordOpen(connectorID: "portablemind", fileID: 916,
                         displayPath: "rick/test-sample.md", name: "test-sample.md",
                         lastSeenUpdatedAt: nil)
        XCTAssertEqual(store.entries.count, 2)
    }

    // MARK: - Folders

    func testRecordFolderLRUCap() {
        let (store, _) = makeStore()
        for i in 0..<8 {
            store.recordFolder(URL(fileURLWithPath: "/tmp/folder\(i)"))
        }
        XCTAssertEqual(store.folders.count, RecentItemsStore.maxFolders)
        XCTAssertEqual(store.folders.first?.displayName, "folder7")
    }

    func testRecordFolderDedupAndPromote() {
        let (store, _) = makeStore()
        store.recordFolder(URL(fileURLWithPath: "/tmp/a"))
        store.recordFolder(URL(fileURLWithPath: "/tmp/b"))
        store.recordFolder(URL(fileURLWithPath: "/tmp/a"))
        XCTAssertEqual(store.folders.map(\.displayName), ["a", "b"])
    }

    // MARK: - Lookup

    func testEntryIDForLocalURL() {
        let (store, _) = makeStore()
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        let id = store.entryID(forLocalURL: URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertNotNil(id)
        XCTAssertEqual(store.entry(for: id!)?.displayName, "a.md")
        XCTAssertNil(store.entryID(forLocalURL: URL(fileURLWithPath: "/tmp/missing.md")))
    }

    func testEntryIDForPM() {
        let (store, _) = makeStore()
        store.recordOpen(connectorID: "portablemind", fileID: 42,
                         displayPath: "p", name: "p.md", lastSeenUpdatedAt: nil)
        XCTAssertNotNil(store.entryID(forPMConnectorID: "portablemind", fileID: 42))
        XCTAssertNil(store.entryID(forPMConnectorID: "portablemind", fileID: 99))
        XCTAssertNil(store.entryID(forPMConnectorID: "other", fileID: 42))
    }

    // MARK: - Persistence round-trip

    func testRoundTripThroughDefaults() {
        let suiteName = "round-trip-\(UUID().uuidString)"
        let (store, defaults) = makeStore(suiteName: suiteName)
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        store.recordOpen(connectorID: "portablemind", fileID: 916,
                         displayPath: "rick/test.md", name: "test.md",
                         lastSeenUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        store.recordFolder(URL(fileURLWithPath: "/tmp/workspace"))
        store.updateSessionState(openTabIDs: store.entries.map(\.id),
                                 focusedTabID: store.entries.first?.id)
        store.recordScrollLine(42, for: store.entries[1].id)

        let reloaded = RecentItemsStore(defaults: defaults)
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries.map(\.displayName), ["test.md", "a.md"])
        XCTAssertEqual(reloaded.folders.count, 1)
        XCTAssertEqual(reloaded.folders.first?.displayName, "workspace")
        XCTAssertEqual(reloaded.sessionState.openTabs.count, 2)
        XCTAssertEqual(reloaded.sessionState.focusedTab, reloaded.entries.first?.id)
        XCTAssertEqual(reloaded.sessionState.scrollLines[reloaded.entries[1].id], 42)
    }

    // MARK: - Schema version

    func testForwardSchemaVersionIsIgnored() throws {
        let suiteName = "forward-schema-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var future = SessionState()
        future.schemaVersion = 999
        future.openTabs = [UUID()]
        let data = try encoder.encode(future)
        defaults.set(data, forKey: "ai.portablemind.md-editor.session.state.v1")

        let store = RecentItemsStore(defaults: defaults)
        XCTAssertEqual(store.sessionState, SessionState(), "forward schemaVersion should reset, not crash")
    }

    // MARK: - Session state pruning

    func testUpdateSessionPrunesOrphanedScrollLines() {
        let (store, _) = makeStore()
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/b.md"))
        let aID = store.entries[1].id
        let bID = store.entries[0].id
        store.updateSessionState(openTabIDs: [aID, bID], focusedTabID: bID)
        store.recordScrollLine(10, for: aID)
        store.recordScrollLine(20, for: bID)

        // b is closed; only a stays open.
        store.updateSessionState(openTabIDs: [aID], focusedTabID: aID)
        XCTAssertEqual(store.sessionState.scrollLines[aID], 10)
        XCTAssertNil(store.sessionState.scrollLines[bID], "scroll line for closed tab should be pruned")
    }

    func testScrollLineClampedToOne() {
        let (store, _) = makeStore()
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        let id = store.entries[0].id
        store.recordScrollLine(-5, for: id)
        XCTAssertEqual(store.sessionState.scrollLines[id], 1)
        store.recordScrollLine(0, for: id)
        XCTAssertEqual(store.sessionState.scrollLines[id], 1)
    }

    // MARK: - Clear

    func testClearWipesAllThreeStores() {
        let suiteName = "clear-\(UUID().uuidString)"
        let (store, defaults) = makeStore(suiteName: suiteName)
        store.recordOpen(localURL: URL(fileURLWithPath: "/tmp/a.md"))
        store.recordFolder(URL(fileURLWithPath: "/tmp/ws"))
        store.updateSessionState(openTabIDs: [store.entries[0].id],
                                 focusedTabID: store.entries[0].id)

        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertEqual(store.sessionState, SessionState())

        // Round-trip: a freshly-built store on the same defaults stays empty.
        let reloaded = RecentItemsStore(defaults: defaults)
        XCTAssertTrue(reloaded.entries.isEmpty)
        XCTAssertTrue(reloaded.folders.isEmpty)
        XCTAssertEqual(reloaded.sessionState, SessionState())
    }

    // MARK: - Migration

    func testMigrationFromLegacyKeys() throws {
        let suiteName = "legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Seed legacy keys: two paths, only one of which actually exists.
        let existing = NSTemporaryDirectory() + "d31-legacy-\(UUID().uuidString).md"
        try "hello".write(toFile: existing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: existing) }
        let missing = "/tmp/d31-legacy-missing-\(UUID().uuidString).md"
        defaults.set([missing, existing], forKey: "openTabs")
        defaults.set(1, forKey: "focusedTabIndex")

        let store = RecentItemsStore(defaults: defaults)

        // The missing file should have been silently dropped; only the
        // existing file becomes an entry.
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.displayName, (existing as NSString).lastPathComponent)
        XCTAssertEqual(store.sessionState.openTabs.count, 1)
        XCTAssertEqual(store.sessionState.focusedTab, store.entries.first?.id,
                       "legacy focusedTabIndex=1 mapped to the only surviving tab")

        // Legacy keys are deleted.
        XCTAssertNil(defaults.object(forKey: "openTabs"))
        XCTAssertNil(defaults.object(forKey: "focusedTabIndex"))

        // Second init does nothing extra.
        let reloaded = RecentItemsStore(defaults: defaults)
        XCTAssertEqual(reloaded.entries.count, 1)
    }

    func testMigrationLegacyFocusOutOfRangeBecomesNil() throws {
        let suiteName = "legacy-oor-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let existing = NSTemporaryDirectory() + "d31-legacy-oor-\(UUID().uuidString).md"
        try "hello".write(toFile: existing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: existing) }
        defaults.set([existing], forKey: "openTabs")
        defaults.set(-1, forKey: "focusedTabIndex")

        let store = RecentItemsStore(defaults: defaults)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.sessionState.focusedTab)
    }

    func testMigrationFocusOnDroppedTabBecomesNil() throws {
        let suiteName = "legacy-focus-dropped-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Focused tab was the missing one — don't silently jump focus
        // to a different surviving tab.
        let existing = NSTemporaryDirectory() + "d31-focus-drop-\(UUID().uuidString).md"
        try "x".write(toFile: existing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: existing) }
        let missing = "/tmp/d31-focus-drop-missing-\(UUID().uuidString).md"
        defaults.set([existing, missing], forKey: "openTabs")  // missing at index 1
        defaults.set(1, forKey: "focusedTabIndex")             // focus was on the missing one

        let store = RecentItemsStore(defaults: defaults)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNil(store.sessionState.focusedTab,
                     "focus on a dropped tab should become nil, not jump to a sibling")
    }

    func testMigrationAllMissingFilesYieldsEmptySession() {
        let suiteName = "legacy-allmissing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(["/tmp/nope-\(UUID().uuidString).md"], forKey: "openTabs")
        defaults.set(0, forKey: "focusedTabIndex")

        let store = RecentItemsStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.sessionState.openTabs.isEmpty)
        // Legacy keys still cleaned up.
        XCTAssertNil(defaults.object(forKey: "openTabs"))
        XCTAssertNil(defaults.object(forKey: "focusedTabIndex"))
    }
}
