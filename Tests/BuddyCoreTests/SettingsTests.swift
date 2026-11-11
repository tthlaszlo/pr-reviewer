import Foundation
import Testing
@testable import BuddyCore

@MainActor
struct SettingsTests {
    let credential = Credential(user: GitHubUser(id: 1, login: "lacko"), token: "token")
    private func workspace(github: any GitHubServing = FakeGitHub(),
                           credentials: (any CredentialStoring)? = nil,
                           cache: any InboxStoring = SQLiteInboxStore(path: ":memory:"),
                           configured: Bool = true) -> Workspace {
        Workspace(configured: configured, github: github, authorization: FixedAuthorization(),
                  credentials: credentials ?? MemoryCredentials(credential), cache: cache)
    }
    @Test func connectedStatusAndConfirmedRemoval() async throws {
        let vault = MemoryCredentials(credential)
        let cache = SQLiteInboxStore(path: ":memory:")
        let model = workspace(credentials: vault, cache: cache)
        #expect(model.connectionStatus == .checking)
        await model.start()
        #expect(model.connectionStatus == .connected)
        #expect(model.canRemoveConnection)
        await model.disconnect()
        #expect(model.connectionStatus == .disconnected)
        #expect(!model.canRemoveConnection)
        #expect(await vault.load() == nil)
        #expect(try await cache.load(accountID: 1, page: .reviews) == nil)
        #expect(try await cache.load(accountID: 1, page: .authored) == nil)
    }
    @Test(arguments: [true, false]) func disconnectedAndUnconfigured(configured: Bool) async {
        let model = workspace(credentials: MemoryCredentials(), configured: configured)
        await model.start()
        #expect(model.connectionStatus == (configured ? .disconnected : .notConfigured))
        #expect(!model.canRemoveConnection)
    }
    @Test func expiredAndNetworkErrorHaveDifferentStatuses() async {
        let github = FakeGitHub()
        let model = workspace(github: github)
        await model.start()
        await github.setError(.unavailable)
        await model.refresh(.reviews)
        #expect(model.connectionStatus == .attentionRequired)
        await github.setError(.unauthorized)
        await model.refresh(.reviews)
        #expect(model.connectionStatus == .reconnectRequired)
    }
    @Test func permissionRestrictionShowsLimitedAccess() async {
        let github = FakeGitHub()
        await github.setError(.permissions)
        let model = workspace(github: github)
        await model.start()
        #expect(model.connectionStatus == .limited)
    }
    @Test func partialAccessShowsLimitedStatusWithoutHardError() async {
        struct Partial: GitHubServing {
            func user(token: String) async throws -> GitHubUser { GitHubUser(id: 1, login: "lacko") }
            func inbox(token: String, login: String, page: PRPage) async throws -> Inbox {
                Inbox(pulls: [], accessIssues: [.teamMembership])
            }
        }
        let model = workspace(github: Partial())
        await model.start()
        #expect(model.errors.isEmpty)
        #expect(model.restrictedPages.isEmpty)
        #expect(model.connectionStatus == .limited)
    }
    @Test func keychainDeletionFailureIsNotReportedAsDisconnectedAndCanRetry() async {
        let vault = MemoryCredentials(credential)
        let model = workspace(credentials: vault)
        await model.start()
        await vault.setFailDelete()
        await model.disconnect()
        #expect(model.user == nil)
        #expect(model.connectionStatus == .removalIncomplete)
        #expect(model.canRemoveConnection)
        #expect(model.removalIncomplete)
        #expect(await vault.load() == credential)
        await vault.setFailDelete(false)
        await model.disconnect()
        #expect(model.connectionStatus == .disconnected)
        #expect(!model.removalIncomplete)
        #expect(model.connectionError == nil)
        #expect(await vault.load() == nil)
    }
    @Test func cacheDeletionFailureAlsoNeedsRetry() async throws {
        actor Cache: InboxStoring {
            var fail = true
            func load(accountID: Int64, page: PRPage) -> Inbox? { nil }
            func save(_ inbox: Inbox, accountID: Int64, page: PRPage) { }
            func clear() throws { if fail { throw BuddyError.storage } }
            func allowClear() { fail = false }
        }
        let vault = MemoryCredentials(credential)
        let cache = Cache()
        let model = workspace(credentials: vault, cache: cache)
        await model.start()
        await model.disconnect()
        #expect(await vault.load() == nil)
        #expect(model.connectionStatus == .removalIncomplete)
        #expect(model.connectionError == BuddyError.storage.localizedDescription)
        await cache.allowClear()
        await model.disconnect()
        #expect(model.connectionStatus == .disconnected)
    }
}
