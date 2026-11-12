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
    func reviews(token: String, pull: PullRequest) async throws -> ReviewHistory {
        if scenario == "reviews-error" { throw BuddyError.unavailable }
        if scenario == "reviews-empty" { return ReviewHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if scenario == "reviews-design" {
            let message = #"""
            <a href="#"><img alt="P1" src="https://example.com/p1.svg" align="top"></a> **Fresh accounts still wait**

            `responsible_user` checks the failed run's user, not the new run's user. When Alice hits a limit and Bob starts work with a fresh grant, Alice's unchanged default keeps Bob's work waiting.

            Pass the new run's responsible user into the check:

            - Compare the selected grant with the recorded grant.
            - Keep the existing retry behavior for the same account.

            <details><summary>Prompt To Fix With AI</summary>

            ```markdown
            This is a comment left during a code review.
            Path: server/src/services/native-runtime/native-startup-retry.ts
            Line: 55-58

            Use the new run's responsible user when selecting the grant.
            Preserve the existing behavior for same-account retries.
            ```

            </details>
            """#
            let reviewData = try JSONSerialization.data(withJSONObject: [
                ["id": 1, "user": ["login": "greptile-apps[bot]"], "state": "COMMENTED",
                 "body": "## Review summary\nFound **one issue** in the account-switch retry path. The inline feedback below includes a suggested fix.",
                 "submitted_at": "2026-11-11T10:00:00Z"],
                ["id": 2, "user": ["login": "anna-dev"], "state": "APPROVED",
                 "body": "Looks good overall. The **error handling** and `retry` tests are clear.",
                 "submitted_at": "2026-11-11T11:00:00Z"]
            ])
            let commentData = try JSONSerialization.data(withJSONObject: [
                ["id": 3, "user": ["login": "greptile-apps[bot]"], "body": message,
                 "path": "server/src/services/native-runtime/native-startup-retry.ts", "line": 58,
                 "created_at": "2026-11-11T10:00:00Z"]
            ])
            return ReviewHistory(reviews: try decoder.decode([SubmittedReview].self, from: reviewData),
                                 comments: try decoder.decode([ReviewComment].self, from: commentData))
        }
        let reviews = try decoder.decode([SubmittedReview].self, from: Data(#"[{"id":1,"user":{"login":"reviewer"},"state":"APPROVED","body":"Looks good to me!","submitted_at":"2026-11-11T10:00:00Z"},{"id":2,"user":{"login":"teammate"},"state":"CHANGES_REQUESTED","body":"Please handle the error case.","submitted_at":"2026-11-11T11:00:00Z"}]"#.utf8))
        let comments = try decoder.decode([ReviewComment].self, from: Data(#"[{"id":3,"user":{"login":"teammate"},"body":"This can fail when offline.","path":"Sources/Client.swift","line":42,"created_at":"2026-11-11T11:00:00Z"}]"#.utf8))
        return ReviewHistory(reviews: reviews, comments: comments, partial: scenario == "reviews-partial")
    }
    func inbox(token: String, login: String, page: PRPage) async throws -> Inbox {
        if scenario == "error" || (scenario == "reviews-restricted" && page == .reviews) { throw BuddyError.permissions }
        if scenario == "empty" { return Inbox(pulls: []) }
        if scenario == "network-error" { throw BuddyError.unavailable }
        if scenario == "partial-empty" { return Inbox(pulls: [], accessIssues: [.teamMembership]) }
        if scenario == "lists-design" {
            let titles = ["Improve GitHub synchronization", "Handle organization SSO access without hiding accessible pull requests", "Update dependency cache", "Refine workspace keyboard shortcuts", "Add pagination to repository discovery", "Fix review request timing"]
            var pulls: [PullRequest] = []
            let count = page == .reviews ? 6 : 4
            for index in 0..<count {
                let number = index + 1147
                let group: ReviewGroup? = page == .authored ? nil : index < 3 ? .awaiting : index < 5 ? .waiting : .requestedAgain
                let author = page == .authored ? "local-developer" : ["anna-dev", "martin", "sara"][index % 3]
                let teams = page == .reviews && index % 2 == 1 ? ["example/backend"] : []
                let review: String? = page == .reviews && index >= 3 ? "APPROVED" : nil
                pulls.append(PullRequest(id: Int64(number), number: number, title: titles[index],
                                         url: URL(string: "https://github.com/example/project/pull/\(number)")!,
                                         repository: index == 2 ? "example/design-system" : "example/platform",
                                         author: author, updatedAt: Date().addingTimeInterval(-Double(index + 1) * 1800),
                                         draft: index == 2, group: group,
                                         personal: page == .reviews && index % 2 == 0, teams: teams,
                                         reviewState: review, changedSinceReview: page == .reviews && index == 5))
            }
            return Inbox(pulls: pulls)
        }
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
