import Foundation
import Testing
@testable import BuddyCore

struct GitHubTests {
    @Test func authoredDoesNotFetchTeamsOrHistory() async throws {
        let http = MockHTTP { request, _ in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            #expect(request.httpMethod == "GET")
            if request.url!.path == "/search/issues" {
                #expect(request.url!.query!.contains("author"))
                return json(#"{"total_count":1,"incomplete_results":false,"items":[{"number":10,"repository_url":"https://api.github.com/repos/acme/api"}]}"#)
            }
            #expect(request.url!.path == "/repos/acme/api/pulls/10")
            return json(pullJSON.replacingOccurrences(of: #""login":"author""#, with: #""login":"LACKO""#))
        }
        let result = try await GitHubClient(transport: http).inbox(token: "token", login: "lacko", page: .authored)
        #expect(result.pulls.count == 1); #expect(result.pulls[0].group == nil)
        #expect(await http.requests.count == 2)
    }
    @Test func personalAndTeamSearchesDeduplicateAndClassify() async throws {
        let http = MockHTTP { request, _ in
            switch request.url!.path {
            case "/user/teams": return json("[\(teamJSON)]")
            case "/search/issues": return json(#"{"total_count":1,"incomplete_results":false,"items":[{"number":10,"repository_url":"https://api.github.com/repos/acme/api"}]}"#)
            case "/repos/acme/api/pulls/10": return json(pullJSON)
            case "/repos/acme/api/pulls/10/reviews": return json("[\(reviewJSON)]")
            case "/repos/acme/api/issues/10/timeline": return json("[\(eventJSON)]")
            default: Issue.record("Unexpected endpoint"); return json("{}")
            }
        }
        let result = try await GitHubClient(transport: http).inbox(token: "token", login: "lacko", page: .reviews)
        #expect(result.pulls.count == 1); #expect(result.pulls[0].group == .requestedAgain)
        let requests = await http.requests
        #expect(requests.filter { $0.url?.path == "/search/issues" }.count == 3)
        #expect(requests.filter { $0.url?.path == "/repos/acme/api/pulls/10" }.count == 1)
    }
    @Test func historyPaginationAndLimitAreVisible() async throws {
        let http = MockHTTP { request, _ in
            switch request.url!.path {
            case "/user/teams": return json("[]")
            case "/search/issues": return json(#"{"total_count":1001,"incomplete_results":true,"items":[{"number":10,"repository_url":"https://api.github.com/repos/acme/api"}]}"#)
            case "/repos/acme/api/pulls/10": return json(pullJSON)
            case "/repos/acme/api/pulls/10/reviews": return json("[\(reviewJSON)]")
            case "/repos/acme/api/issues/10/timeline": return json("[\(eventJSON)]")
            default: throw BuddyError.invalidResponse
            }
        }
        let result = try await GitHubClient(transport: http, pageSize: 1, maximumPages: 2).inbox(token: "token", login: "lacko", page: .reviews)
        #expect(result.pulls[0].uncertain)
        #expect(result.warnings.count == 2)
        #expect(await http.requests.contains { $0.url?.query?.contains("page=2") == true })
    }
    @Test func teamPermissionFailureDoesNotHidePersonalRequests() async throws {
        let http = MockHTTP { request, _ in
            switch request.url!.path {
            case "/user/teams": return json("{}", status: 403)
            case "/search/issues": return json(#"{"total_count":1,"incomplete_results":false,"items":[{"number":10,"repository_url":"https://api.github.com/repos/acme/api"}]}"#)
            case "/repos/acme/api/pulls/10": return json(pullJSON)
            default: return json("[]")
            }
        }
        let result = try await GitHubClient(transport: http).inbox(token: "t", login: "lacko", page: .reviews)
        #expect(result.pulls.count == 1); #expect(result.warnings.count == 1)
    }
    @Test func inaccessibleRepositoryIsPartialResult() async throws {
        let http = MockHTTP { request, _ in
            if request.url!.path == "/search/issues" {
                return json(#"{"total_count":1,"incomplete_results":false,"items":[{"number":10,"repository_url":"https://api.github.com/repos/acme/api"}]}"#)
            }
            return json("{}", status: 404)
        }
        let result = try await GitHubClient(transport: http).inbox(token: "t", login: "lacko", page: .authored)
        #expect(result.pulls.isEmpty); #expect(result.warnings.count == 1)
    }
    @Test(arguments: [(401, BuddyError.unauthorized), (403, .permissions), (429, .rateLimited), (500, .unavailable), (302, .unavailable)])
    func errors(status: Int, expected: BuddyError) async {
        let client = GitHubClient(transport: MockHTTP { _, _ in json("{}", status: status) })
        await #expect(throws: expected) { try await client.user(token: "token") }
    }
    @Test func secondaryRateLimitAndMalformedData() async {
        let limited = GitHubClient(transport: MockHTTP { _, _ in json("{}", status: 403, headers: ["Retry-After": "10"]) })
        await #expect(throws: BuddyError.rateLimited) { try await limited.user(token: "t") }
        let malformed = GitHubClient(transport: MockHTTP { _, _ in json("not json") })
        await #expect(throws: BuddyError.invalidResponse) { try await malformed.user(token: "t") }
        let identity = GitHubClient(transport: MockHTTP { _, _ in json(#"{"id":0,"login":""}"#) })
        await #expect(throws: BuddyError.invalidResponse) { try await identity.user(token: "t") }
    }
    @Test func rejectsExternalRepositoryURLsWithoutSendingToken() async throws {
        let http = MockHTTP { request, _ in
            #expect(request.url?.host == "api.github.com")
            return json(#"{"total_count":1,"incomplete_results":false,"items":[{"number":10,"repository_url":"https://evil.example/repos/acme/api"}]}"#)
        }
        await #expect(throws: BuddyError.invalidResponse) {
            try await GitHubClient(transport: http).inbox(token: "secret", login: "lacko", page: .authored)
        }
        #expect(await http.requests.count == 1)
    }
    @Test func authoredExcludesClosedAndOtherAuthors() async throws {
        let http = MockHTTP { request, _ in
            if request.url!.path == "/search/issues" {
                return json(#"{"total_count":1,"incomplete_results":false,"items":[{"number":10,"repository_url":"https://api.github.com/repos/acme/api"}]}"#)
            }
            return json(pullJSON)
        }
        #expect(try await GitHubClient(transport: http).inbox(token: "t", login: "lacko", page: .authored).pulls.isEmpty)
    }
}
