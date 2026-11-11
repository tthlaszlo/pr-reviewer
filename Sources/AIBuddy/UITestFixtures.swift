#if DEBUG
import Foundation
import BuddyCore

// Explicit UI-test-only dependency graph: never touches production Keychain or disk.
enum UITestFixtures {
    @MainActor static func workspace(scenario: String) -> Workspace {
        Workspace(configured: scenario != "unconfigured", github: FixtureGitHub(scenario: scenario),
                  authorization: FixtureAuthorization(),
                  credentials: FixtureCredentials(connected: scenario != "disconnected" && scenario != "unconfigured",
                                                  failDelete: scenario == "removal-error"),
                  cache: SQLiteInboxStore(path: ":memory:"))
    }
}
private actor FixtureCredentials: CredentialStoring {
    var value: Credential?
    let failDelete: Bool
    init(connected: Bool, failDelete: Bool) {
        self.failDelete = failDelete
        value = connected ? Credential(user: GitHubUser(id: 1, login: "local-developer"), token: "fixture") : nil
    }
    func load() -> Credential? { value }
    func save(_ credential: Credential) { value = credential }
    func delete() throws {
        if failDelete { throw BuddyError.keychain(-1) }
        value = nil
    }
}
private struct FixtureGitHub: GitHubServing {
    let scenario: String
    func user(token: String) async throws -> GitHubUser {
        if scenario == "expired" { throw BuddyError.unauthorized }
        return GitHubUser(id: 1, login: "local-developer")
    }
    func inbox(token: String, login: String, page: PRPage) async throws -> Inbox {
        if scenario == "error" || (scenario == "reviews-restricted" && page == .reviews) { throw BuddyError.permissions }
        if scenario == "empty" { return Inbox(pulls: []) }
        if scenario == "network-error" { throw BuddyError.unavailable }
        if scenario == "partial-empty" { return Inbox(pulls: [], accessIssues: [.teamMembership]) }
        let titles = page == .reviews ? ["Improve GitHub synchronization", "Update local storage", "Fix review request timing"] : ["My native macOS feature"]
        let pulls = titles.enumerated().map { index, title in
            PullRequest(id: Int64(index + 1), number: index + 10, title: title,
                        url: URL(string: "https://github.com/example/project/pull/\(index + 10)")!,
                        repository: "example/project", author: "local-developer", updatedAt: Date(),
                        group: page == .reviews ? ReviewGroup.allCases[index] : nil,
                        personal: page == .reviews, changedSinceReview: index == 2)
        }
        return Inbox(pulls: pulls, accessIssues: scenario == "partial" ? [.teamMembership, .repository("example/private#42")] : [])
    }
}
private struct FixtureAuthorization: GitHubAuthorization {
    func begin() async throws -> DeviceCode {
        try JSONDecoder().decode(DeviceCode.self, from: Data(#"{"device_code":"fixture","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.utf8))
    }
    func finish(_ code: DeviceCode) async throws -> String {
        try await Task.sleep(for: .seconds(3600))
        return "fixture"
    }
}
#endif
