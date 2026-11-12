import Foundation
import Testing
@testable import BuddyCore

private let submittedJSON = #"{"id":1,"user":{"login":"reviewer"},"state":"APPROVED","body":"Looks good","submitted_at":"2026-11-11T10:00:00Z"}"#
private let codeCommentJSON = #"{"id":3,"user":null,"body":"Handle this error","path":"Client.swift","line":null,"original_line":42,"created_at":"2026-11-11T11:00:00Z"}"#

struct ReviewHistoryTests {
    @Test func loadsAllPagesAndExcludesUnsubmittedReviews() async throws {
        let http = MockHTTP { request, _ in
            let url = request.url!
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            #expect(request.httpMethod == "GET")
            if url.path.hasSuffix("/reviews") {
                if page == "1" { return json("[\(submittedJSON)]") }
                if page == "2" {
                    return json(#"[{"id":2,"user":null,"state":"PENDING","body":"private draft"}]"#)
                }
                return json("[]")
            }
            #expect(url.path == "/repos/acme/api/pulls/10/comments")
            return json(page == "1" ? "[\(codeCommentJSON)]" : "[]")
        }
        let history = try await GitHubClient(transport: http, pageSize: 1, maximumPages: 10)
            .reviews(token: "token", pull: sampleInbox().pulls[0])
        #expect(history.reviews.count == 1)
        #expect(history.reviews[0].reviewer == "reviewer")
        #expect(history.reviews[0].status == "Approved")
        #expect(history.reviews[0].body == "Looks good")
        #expect(history.comments[0].author == "Deleted user")
        #expect(history.comments[0].location == "Client.swift:42 · Outdated")
        #expect(!history.partial)
        #expect(await http.requests.count == 5)
    }
    @Test func paginationLimitIsVisible() async throws {
        let http = MockHTTP { request, _ in json(request.url!.path.hasSuffix("/reviews") ? "[\(submittedJSON)]" : "[]") }
        let history = try await GitHubClient(transport: http, pageSize: 1, maximumPages: 1)
            .reviews(token: "token", pull: sampleInbox().pulls[0])
        #expect(history.partial)
        #expect(history.reviews.count == 1)
    }
    @Test func emptyHistory() async throws {
        let history = try await GitHubClient(transport: MockHTTP { _, _ in json("[]") })
            .reviews(token: "token", pull: sampleInbox().pulls[0])
        #expect(history == ReviewHistory())
    }
    @Test(arguments: [401, 403, 429, 500]) func propagatesErrors(status: Int) async {
        let expected: BuddyError = switch status {
        case 401: .unauthorized
        case 403: .permissions
        case 429: .rateLimited
        default: .unavailable
        }
        await #expect(throws: expected) {
            try await GitHubClient(transport: MockHTTP { _, _ in json("{}", status: status) })
                .reviews(token: "token", pull: sampleInbox().pulls[0])
        }
    }
    @Test func rejectsInvalidResponseAndCommentFailure() async {
        await #expect(throws: (any Error).self) {
            try await GitHubClient(transport: MockHTTP { _, _ in json("{}") })
                .reviews(token: "token", pull: sampleInbox().pulls[0])
        }
        await #expect(throws: BuddyError.permissions) {
            try await GitHubClient(transport: MockHTTP { request, _ in
                json(request.url!.path.hasSuffix("/reviews") ? "[\(submittedJSON)]" : "{}",
                     status: request.url!.path.hasSuffix("/reviews") ? 200 : 403)
            }).reviews(token: "token", pull: sampleInbox().pulls[0])
        }
    }
    @Test(arguments: ["../repo", "owner/repo?x=1", "owner/repo/extra", "owner/", "//evil.test"])
    func rejectsUnsafeRepository(repository: String) async {
        let http = MockHTTP { _, _ in Issue.record("No request should be made"); return json("[]") }
        var pull = sampleInbox().pulls[0]; pull.repository = repository
        await #expect(throws: BuddyError.invalidResponse) {
            try await GitHubClient(transport: http).reviews(token: "token", pull: pull)
        }
    }
    @Test func reviewStatusesAndChronology() throws {
        var reviews: [SubmittedReview] = []
        for (index, state) in ["APPROVED", "CHANGES_REQUESTED", "COMMENTED", "DISMISSED", "FUTURE_STATE"].enumerated() {
            let value = submittedJSON.replacingOccurrences(of: "APPROVED", with: state)
                .replacingOccurrences(of: "\"id\":1", with: "\"id\":\(index + 1)")
            reviews.append(try decode(SubmittedReview.self, Data(value.utf8)))
        }
        #expect(reviews.map(\.status) == ["Approved", "Changes requested", "Commented", "Dismissed", "Future State"])
        let deleted = try decode(SubmittedReview.self, Data(submittedJSON.replacingOccurrences(of: #"{"login":"reviewer"}"#, with: "null").utf8))
        #expect(deleted.reviewer == "Deleted user")
        let earlier = try decode(SubmittedReview.self, Data(submittedJSON.replacingOccurrences(of: "2026-11-11", with: "2026-11-10").utf8))
        #expect(ReviewHistory(reviews: [reviews[0], earlier]).reviews.first == earlier)
    }
}

private actor DetailGitHub: GitHubServing {
    var error: BuddyError?
    var calls = 0
    var blocked = false
    var continuation: CheckedContinuation<Void, Never>?
    func user(token: String) -> GitHubUser { GitHubUser(id: 1, login: "lacko") }
    func inbox(token: String, login: String, page: PRPage) -> Inbox { sampleInbox() }
    func reviews(token: String, pull: PullRequest) async throws -> ReviewHistory {
        calls += 1
        if blocked && calls == 1 { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        return ReviewHistory(reviews: [try decode(SubmittedReview.self, Data(submittedJSON.utf8))])
    }
    func setError(_ value: BuddyError?) { error = value }
    func block() { blocked = true }
    func resume() { blocked = false; continuation?.resume(); continuation = nil }
}

@MainActor
struct ReviewWorkspaceTests {
    private func workspace(_ github: DetailGitHub, connected: Bool = true) -> Workspace {
        Workspace(configured: true, github: github, authorization: FixedAuthorization(),
                  credentials: MemoryCredentials(connected ? Credential(user: GitHubUser(id: 1, login: "lacko"), token: "token") : nil),
                  cache: SQLiteInboxStore(path: ":memory:"))
    }
    @Test func loadRetryAndClose() async {
        let github = DetailGitHub(); let model = workspace(github)
        await model.start()
        await github.setError(.unavailable)
        let pull = sampleInbox().pulls[0]
        model.openReviews(pull)
        #expect(model.reviewsLoading)
        await model.waitForReviews()
        #expect(model.reviewsError == BuddyError.unavailable.localizedDescription)
        #expect(model.reviewHistory == nil)
        #expect(!model.reviewsLoading)
        await github.setError(nil)
        model.openReviews(pull); await model.waitForReviews()
        #expect(model.reviewHistory?.reviews.count == 1)
        #expect(model.reviewsError == nil)
        model.closeReviews()
        #expect(model.selectedPull == nil && model.reviewHistory == nil)
    }
    @Test func cannotLoadWithoutConnection() async {
        let github = DetailGitHub(); let model = workspace(github, connected: false)
        await model.start(); model.openReviews(sampleInbox().pulls[0]); await model.waitForReviews()
        #expect(await github.calls == 0)
        #expect(model.selectedPull == nil)
    }
    @Test func expiredAuthorizationReturnsToConnectionGuide() async {
        let github = DetailGitHub(); let model = workspace(github)
        await model.start(); await github.setError(.unauthorized)
        model.openReviews(sampleInbox().pulls[0]); await model.waitForReviews()
        #expect(model.needsReconnection)
        #expect(model.selectedPull == nil && model.reviewHistory == nil)
        #expect(model.stale == Set(PRPage.allCases))
    }
    @Test func selectingAnotherPullIgnoresPreviousResponse() async {
        let github = DetailGitHub(); let model = workspace(github)
        await model.start(); await github.block()
        let first = sampleInbox().pulls[0]
        model.openReviews(first)
        for _ in 0..<1000 {
            if await github.continuation != nil { break }
            await Task.yield()
        }
        #expect(await github.continuation != nil)
        let waiting = Task { await model.waitForReviews() }
        await Task.yield()
        var second = first; second.id = 2; second.number = 11
        model.openReviews(second); await model.waitForReviews()
        #expect(model.selectedPull == second)
        let history = model.reviewHistory
        await github.resume(); await waiting.value
        #expect(model.selectedPull == second && model.reviewHistory == history)
        #expect(!model.reviewsLoading)
    }
    @Test(arguments: [false, true]) func lateResponseCannotRestoreClosedOrDisconnectedDetail(disconnect: Bool) async {
        let github = DetailGitHub(); let model = workspace(github)
        await model.start(); await github.block()
        model.openReviews(sampleInbox().pulls[0])
        for _ in 0..<1000 {
            if await github.continuation != nil { break }
            await Task.yield()
        }
        #expect(await github.continuation != nil)
        let waiting = Task { await model.waitForReviews() }
        await Task.yield()
        if disconnect { await model.disconnect() } else { model.closeReviews() }
        await github.resume(); await waiting.value
        #expect(model.selectedPull == nil && model.reviewHistory == nil)
        #expect(!model.reviewsLoading && model.reviewsError == nil)
    }
}
