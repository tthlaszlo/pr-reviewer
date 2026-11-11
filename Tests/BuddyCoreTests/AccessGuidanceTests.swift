import Foundation
import Testing
@testable import BuddyCore

private actor AccessGitHub: GitHubServing {
    var userError: BuddyError?
    var pageErrors: [PRPage: BuddyError] = [:]
    var identity = GitHubUser(id: 1, login: "lacko")
    var calls = 0
    func user(token: String) throws -> GitHubUser {
        if let userError { throw userError }
        return identity
    }
    func inbox(token: String, login: String, page: PRPage) throws -> Inbox {
        calls += 1
        if let error = pageErrors[page] { throw error }
        return sampleInbox(page.title)
    }
    func setUserError(_ value: BuddyError?) { userError = value }
    func restrict(_ page: PRPage, error: BuddyError?) { pageErrors[page] = error }
    func setIdentity(_ value: GitHubUser) { identity = value }
}

@MainActor
struct AccessGuidanceTests {
    let original = Credential(user: GitHubUser(id: 1, login: "lacko"), token: "old-token")
    private func make(_ github: AccessGitHub, vault: MemoryCredentials? = nil,
              auth: any GitHubAuthorization = FixedAuthorization(), cache: any InboxStoring = SQLiteInboxStore(path: ":memory:")) -> Workspace {
        Workspace(configured: true, github: github, authorization: auth,
                  credentials: vault ?? MemoryCredentials(original), cache: cache)
    }
    @Test func unauthorizedGatesAllPagesAndStopsRetries() async {
        let github = AccessGitHub()
        let workspace = make(github)
        await workspace.start()
        let cached = workspace.inboxes
        await github.setUserError(.unauthorized)
        await workspace.refresh(.reviews)
        #expect(workspace.needsReconnection)
        #expect(workspace.inboxes == cached)
        #expect(workspace.refreshing.isEmpty)
        #expect(workspace.errors[.authored] == BuddyError.unauthorized.localizedDescription)
        let previousCalls = await github.calls
        await workspace.refreshAll()
        #expect(await github.calls == previousCalls)
    }
    @Test func forbiddenAffectsOnlyItsPageAndSuccessfulRetryClearsIt() async {
        let github = AccessGitHub()
        await github.restrict(.reviews, error: .permissions)
        let workspace = make(github)
        await workspace.start()
        #expect(!workspace.needsReconnection)
        #expect(workspace.restrictedPages == [.reviews])
        #expect(workspace.inboxes[.authored] != nil)
        await github.restrict(.reviews, error: nil)
        await workspace.refresh(.reviews)
        #expect(workspace.restrictedPages.isEmpty)
        #expect(workspace.errors[.reviews] == nil)
        #expect(workspace.inboxes[.reviews] != nil)
    }
    @Test func networkFailureDoesNotBecomePermissionGate() async {
        let github = AccessGitHub()
        await github.restrict(.reviews, error: .unavailable)
        let workspace = make(github)
        await workspace.start()
        #expect(workspace.restrictedPages.isEmpty)
        #expect(!workspace.needsReconnection)
    }
    @Test func revokedAccessCanReconnectWithoutManualDisconnect() async {
        let github = AccessGitHub()
        await github.setUserError(.unauthorized)
        let vault = MemoryCredentials(original)
        let workspace = make(github, vault: vault)
        await workspace.start()
        #expect(workspace.needsReconnection)
        await github.setUserError(nil)
        workspace.connect()
        await workspace.waitForConnection()
        #expect(!workspace.needsReconnection)
        #expect(workspace.inboxes.count == 2)
        #expect(await vault.load()?.token == "token")
    }
    @Test func deniedReconnectKeepsGuidanceAndOriginalCredential() async {
        let github = AccessGitHub()
        await github.setUserError(.unauthorized)
        let vault = MemoryCredentials(original)
        let workspace = make(github, vault: vault, auth: FixedAuthorization(error: .denied))
        await workspace.start()
        workspace.reconnect()
        await workspace.waitForConnection()
        #expect(workspace.needsReconnection)
        #expect(workspace.connectionError == BuddyError.denied.localizedDescription)
        #expect(await vault.load() == original)
    }
    @Test func reconnectToDifferentAccountDoesNotExposeOldSnapshots() async throws {
        let github = AccessGitHub()
        let cache = SQLiteInboxStore(path: ":memory:")
        let workspace = make(github, cache: cache)
        await workspace.start()
        await github.setIdentity(GitHubUser(id: 99, login: "new-account"))
        workspace.reconnect()
        await workspace.waitForConnection()
        #expect(workspace.user?.id == 99)
        #expect(try await cache.load(accountID: 1, page: .reviews) == nil)
        #expect(try await cache.load(accountID: 99, page: .reviews) != nil)
    }
    @Test func cancellingOptionalReauthorizationPreservesUsableConnection() async {
        struct Waiting: GitHubAuthorization {
            func begin() throws -> DeviceCode { try decode(DeviceCode.self, Data(deviceJSON.utf8)) }
            func finish(_ code: DeviceCode) async throws -> String {
                try await Task.sleep(for: .seconds(3600)); return "token"
            }
        }
        let github = AccessGitHub()
        let vault = MemoryCredentials(original)
        let workspace = make(github, vault: vault, auth: Waiting())
        await workspace.start()
        let previous = workspace.inboxes
        workspace.reconnect()
        for _ in 0..<1000 {
            if workspace.deviceCode != nil { break }
            await Task.yield()
        }
        #expect(workspace.deviceCode != nil)
        await workspace.cancelConnection()
        #expect(!workspace.connecting)
        #expect(!workspace.needsReconnection)
        #expect(workspace.inboxes == previous)
        #expect(await vault.load() == original)
    }
    @Test func cancellingDuringCredentialReplacementRestoresOriginalCredential() async {
        actor PausedCredentials: CredentialStoring {
            var value: Credential?
            var saving = false
            init(_ value: Credential) { self.value = value }
            func load() -> Credential? { value }
            func save(_ credential: Credential) async {
                if !saving {
                    saving = true
                    while !Task.isCancelled { await Task.yield() }
                }
                value = credential
            }
            func delete() { value = nil }
        }
        let github = AccessGitHub()
        let vault = PausedCredentials(original)
        let workspace = Workspace(configured: true, github: github, authorization: FixedAuthorization(),
                                  credentials: vault, cache: SQLiteInboxStore(path: ":memory:"))
        await workspace.start()
        workspace.reconnect()
        for _ in 0..<1000 {
            if await vault.saving { break }
            await Task.yield()
        }
        #expect(await vault.saving)
        await workspace.cancelConnection()
        #expect(await vault.load() == original)
        #expect(workspace.user == original.user)
        #expect(!workspace.connecting)
    }
    @Test func accessMetadataPersistsAndLegacySnapshotsRemainReadable() async throws {
        let store = SQLiteInboxStore(path: ":memory:")
        var inbox = sampleInbox()
        inbox.accessIssues = [.teamMembership, .repository("acme/private#42")]
        try await store.save(inbox, accountID: 1, page: .reviews)
        #expect(try await store.load(accountID: 1, page: .reviews)?.accessIssues == inbox.accessIssues)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(inbox)) as! [String: Any]
        legacy.removeValue(forKey: "accessIssues")
        let restored = try JSONDecoder().decode(Inbox.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.accessIssues.isEmpty)
        #expect(restored.pulls == inbox.pulls)
    }
    @Test func settingsLinksOnlyUseGitHubAndFallBackForMissingConfiguration() {
        #expect(GitHubAccessHelp.settingsURL(clientID: "public-id").absoluteString == "https://github.com/settings/connections/applications/public-id")
        #expect(GitHubAccessHelp.settingsURL(clientID: "").absoluteString == "https://github.com/settings/applications")
        #expect(GitHubAccessHelp.settingsURL(clientID: "$(GITHUB_CLIENT_ID)") == GitHubAccessHelp.applicationsURL)
        #expect(GitHubAccessHelp.settingsURL(clientID: "../outside") == GitHubAccessHelp.applicationsURL)
    }
}
