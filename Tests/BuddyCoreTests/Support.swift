import Foundation
@testable import BuddyCore

actor MockHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    let handler: @Sendable (URLRequest, Int) throws -> HTTPResponse
    init(_ handler: @escaping @Sendable (URLRequest, Int) throws -> HTTPResponse) { self.handler = handler }
    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        return try handler(request, requests.count)
    }
}
func json(_ string: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(data: Data(string.utf8), status: status, headers: headers)
}
let pullJSON = #"{"id":1,"number":10,"title":"Fix authorization","html_url":"https://github.com/acme/api/pull/10","user":{"login":"author"},"updated_at":"2026-11-11T12:00:00Z","draft":false,"state":"open","head":{"sha":"new"},"requested_reviewers":[{"login":"lacko"}],"requested_teams":[]}"#
let reviewJSON = #"{"user":{"login":"lacko"},"state":"APPROVED","submitted_at":"2026-11-10T12:00:00Z","commit_id":"old"}"#
let eventJSON = #"{"event":"review_requested","created_at":"2026-11-11T12:00:00Z","requested_reviewer":{"login":"lacko"}}"#
let teamJSON = #"{"id":42,"slug":"backend","organization":{"login":"acme"}}"#
let deviceJSON = #"{"device_code":"secret-device","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
func sampleInbox(_ title: String = "Native app") -> Inbox {
    Inbox(pulls: [PullRequest(id: 1, number: 10, title: title, url: URL(string: "https://github.com/acme/api/pull/10")!,
                             repository: "acme/api", author: "lacko", updatedAt: Date(timeIntervalSince1970: 100), group: .awaiting)])
}
actor TestClock: DeviceClock {
    var date = Date(timeIntervalSince1970: 0)
    var waits: [Int] = []
    func now() -> Date { date }
    func sleep(seconds: Int) throws {
        try Task.checkCancellation()
        waits.append(seconds); date += TimeInterval(seconds)
    }
}
actor MemoryCredentials: CredentialStoring {
    var value: Credential?
    var failDelete = false
    init(_ value: Credential? = nil) { self.value = value }
    func load() -> Credential? { value }
    func save(_ credential: Credential) { value = credential }
    func delete() throws { if failDelete { throw BuddyError.keychain(-1) }; value = nil }
    func setFailDelete(_ value: Bool = true) { failDelete = value }
}
struct FixedAuthorization: GitHubAuthorization {
    var error: BuddyError?
    func begin() throws -> DeviceCode { try decode(DeviceCode.self, Data(deviceJSON.utf8)) }
    func finish(_ code: DeviceCode) throws -> String {
        if let error { throw error }; return "token"
    }
}
actor FakeGitHub: GitHubServing {
    var identity = GitHubUser(id: 1, login: "lacko")
    var error: BuddyError?
    var inboxCalls: [PRPage] = []
    var suspended = false
    var continuation: CheckedContinuation<Void, Never>?
    func user(token: String) -> GitHubUser { identity }
    func reviews(token: String, pull: PullRequest) async throws -> ReviewHistory { ReviewHistory() }
    func inbox(token: String, login: String, page: PRPage) async throws -> Inbox {
        inboxCalls.append(page)
        if suspended { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        return sampleInbox(page.title)
    }
    func setError(_ value: BuddyError?) { error = value }
    func setIdentity(_ value: GitHubUser) { identity = value }
    func suspend() { suspended = true }
    func resume() { suspended = false; continuation?.resume(); continuation = nil }
}
