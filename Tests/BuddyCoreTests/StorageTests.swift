import Foundation
import Testing
@testable import BuddyCore

struct StorageTests {
    @Test func roundTripIsolationAndClear() async throws {
        let store = SQLiteInboxStore(path: ":memory:")
        #expect(try await store.load(accountID: 1, page: .reviews) == nil)
        let inbox = sampleInbox()
        try await store.save(inbox, accountID: 1, page: .reviews)
        #expect(try await store.load(accountID: 1, page: .reviews) == inbox)
        #expect(try await store.load(accountID: 2, page: .reviews) == nil)
        #expect(try await store.load(accountID: 1, page: .authored) == nil)
        let replacement = sampleInbox("Replacement")
        try await store.save(replacement, accountID: 1, page: .reviews)
        #expect(try await store.load(accountID: 1, page: .reviews) == replacement)
        try await store.clear()
        #expect(try await store.load(accountID: 1, page: .reviews) == nil)
    }
    @Test func persistsBetweenInstancesAndHandlesUnicode() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("inbox.sqlite").path
        let first = SQLiteInboxStore(path: path)
        let inbox = sampleInbox("Árvíztűrő tükörfúrógép ' 🦊")
        try await first.save(inbox, accountID: 1, page: .authored)
        let second = SQLiteInboxStore(path: path)
        #expect(try await second.load(accountID: 1, page: .authored) == inbox)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("access_token"))
    }
    @Test func invalidDatabasePathReportsFailure() async {
        let store = SQLiteInboxStore(path: "/dev/null/inbox.sqlite")
        await #expect(throws: (any Error).self) { try await store.load(accountID: 1, page: .reviews) }
    }
    @Test func corruptedPayloadDoesNotCrash() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("bad.sqlite").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: URL(fileURLWithPath: path))
        let store = SQLiteInboxStore(path: path)
        await #expect(throws: BuddyError.storage) { try await store.load(accountID: 1, page: .reviews) }
    }
}
