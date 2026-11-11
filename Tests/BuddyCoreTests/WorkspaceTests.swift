import Foundation
import Testing
@testable import BuddyCore

@MainActor
struct WorkspaceTests {
    let saved = Credential(user: GitHubUser(id: 1, login: "lacko"), token: "token")
    func model(credentials: any CredentialStoring = MemoryCredentials(), github: any GitHubServing = FakeGitHub(),
               authorization: any GitHubAuthorization = FixedAuthorization(),
               cache: any InboxStoring = SQLiteInboxStore(path: ":memory:"), configured: Bool = true) -> Workspace {
        Workspace(configured: configured, github: github, authorization: authorization, credentials: credentials, cache: cache)
    }
    @Test func noAppLoginAndMissingConfiguration() async {
        let workspace = model(configured: false)
        await workspace.start()
        #expect(workspace.user == nil); #expect(!workspace.starting)
        workspace.connect()
        #expect(workspace.connectionError == BuddyError.configuration.localizedDescription)
    }
    @Test func restoresCredentialAndLoadsBothPages() async {
        let credentials = MemoryCredentials(saved)
        let workspace = model(credentials: credentials)
        await workspace.start()
        #expect(workspace.user?.id == 1)
        #expect(workspace.inboxes[.reviews]?.pulls.count == 1)
        #expect(workspace.inboxes[.authored]?.pulls.first?.group == .awaiting)
        #expect(workspace.refreshing.isEmpty); #expect(workspace.stale.isEmpty)
    }
    @Test func failedRefreshRetainsCacheAndMarksStale() async throws {
        let cache = SQLiteInboxStore(path: ":memory:")
        let old = sampleInbox("Saved list")
        try await cache.save(old, accountID: 1, page: .reviews)
        let github = FakeGitHub()
        await github.setError(.unavailable)
        let workspace = model(credentials: MemoryCredentials(saved), github: github, cache: cache)
        await workspace.start()
        #expect(workspace.inboxes[.reviews] == old)
        #expect(workspace.stale.contains(.reviews))
        #expect(workspace.errors[.reviews] == BuddyError.unavailable.localizedDescription)
        await github.setError(nil)
        await workspace.refresh(.reviews)
        #expect(!workspace.stale.contains(.reviews)); #expect(workspace.errors[.reviews] == nil)
    }
    @Test func connectStoresCredentialAndDisconnectClearsEverything() async throws {
        let credentials = MemoryCredentials()
        let cache = SQLiteInboxStore(path: ":memory:")
        let workspace = model(credentials: credentials, cache: cache)
        await workspace.start()
        workspace.connect()
        await workspace.waitForConnection()
        #expect(workspace.user?.login == "lacko")
        #expect(await credentials.load()?.token == "token")
        #expect(try await cache.load(accountID: 1, page: .reviews) != nil)
        await workspace.disconnect()
        #expect(workspace.user == nil); #expect(workspace.inboxes.isEmpty)
        #expect(await credentials.load() == nil)
        #expect(try await cache.load(accountID: 1, page: .reviews) == nil)
    }
    @Test func connectionDenialStaysInWorkspace() async {
        let workspace = model(authorization: FixedAuthorization(error: .denied))
        await workspace.start()
        workspace.connect()
        await workspace.waitForConnection()
        #expect(workspace.user == nil); #expect(!workspace.connecting)
        #expect(workspace.connectionError == BuddyError.denied.localizedDescription)
    }
    @Test func changedIdentityCannotLoadAnotherAccount() async {
        let github = FakeGitHub()
        await github.setIdentity(GitHubUser(id: 2, login: "someone-else"))
        let workspace = model(credentials: MemoryCredentials(saved), github: github)
        await workspace.start()
        #expect(workspace.inboxes.isEmpty)
        #expect(workspace.errors[.reviews] == BuddyError.unauthorized.localizedDescription)
        #expect(await github.inboxCalls.isEmpty)
    }
    @Test func oldAccountCacheNotRestoredForNewConnection() async throws {
        let cache = SQLiteInboxStore(path: ":memory:")
        try await cache.save(sampleInbox("Private old account"), accountID: 77, page: .reviews)
        let workspace = model(cache: cache)
        await workspace.start(); workspace.connect(); await workspace.waitForConnection()
        #expect(try await cache.load(accountID: 77, page: .reviews) == nil)
        #expect(workspace.inboxes[.reviews]?.pulls[0].title != "Private old account")
    }
    @Test func lateRefreshCannotRepopulateDisconnectedWorkspace() async throws {
        let github = FakeGitHub()
        let cache = SQLiteInboxStore(path: ":memory:")
        let workspace = model(credentials: MemoryCredentials(saved), github: github, cache: cache)
        await workspace.start()
        await github.suspend()
        let refresh = Task { await workspace.refresh(.reviews) }
        for _ in 0..<1000 {
            if await github.continuation != nil { break }
            await Task.yield()
        }
        #expect(await github.continuation != nil)
        await workspace.disconnect()
        await github.resume()
        await refresh.value
        #expect(workspace.user == nil); #expect(workspace.inboxes.isEmpty)
        #expect(try await cache.load(accountID: 1, page: .reviews) == nil)
    }
    @Test func cancellationClearsCodeAndAllowsRetry() async {
        struct WaitingAuthorization: GitHubAuthorization {
            func begin() throws -> DeviceCode { try decode(DeviceCode.self, Data(deviceJSON.utf8)) }
            func finish(_ code: DeviceCode) async throws -> String {
                try await Task.sleep(for: .seconds(3600)); return "token"
            }
        }
        let credentials = MemoryCredentials()
        let workspace = model(credentials: credentials, authorization: WaitingAuthorization())
        await workspace.start(); workspace.connect()
        for _ in 0..<1000 {
            if workspace.deviceCode != nil { break }
            await Task.yield()
        }
        #expect(workspace.deviceCode != nil)
        await workspace.cancelConnection()
        #expect(workspace.deviceCode == nil); #expect(!workspace.connecting)
        #expect(await credentials.load() == nil)
    }
    @Test func keychainFailureIsVisible() async {
        let credentials = MemoryCredentials(saved)
        let workspace = model(credentials: credentials)
        await workspace.start()
        await credentials.setFailDelete()
        await workspace.disconnect()
        #expect(workspace.connectionError == BuddyError.keychain(-1).localizedDescription)
        #expect(workspace.user == nil)
    }
}
