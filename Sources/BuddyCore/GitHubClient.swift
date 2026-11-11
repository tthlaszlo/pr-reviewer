import Foundation

public protocol GitHubServing: Sendable {
    func user(token: String) async throws -> GitHubUser
    func inbox(token: String, login: String, page: PRPage) async throws -> Inbox
}
public struct GitHubClient: GitHubServing {
    let transport: any HTTPTransport
    let pageSize: Int
    let maximumPages: Int
    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport; pageSize = 100; maximumPages = 100
    }
    // Small limits make pagination edge cases independently testable.
    init(transport: any HTTPTransport, pageSize: Int, maximumPages: Int) {
        self.transport = transport; self.pageSize = pageSize; self.maximumPages = maximumPages
    }
    private func request<T: Decodable & Sendable>(_ path: String, token: String) async throws -> T {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: "https://api.github.com\(path)"), url.host == "api.github.com" else {
            throw BuddyError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        try checkStatus(response)
        return try decode(T.self, response.data)
    }
    public func user(token: String) async throws -> GitHubUser {
        let user: GitHubUser = try await request("/user", token: token)
        guard user.id > 0, !user.login.isEmpty else { throw BuddyError.invalidResponse }
        return user
    }
    private func list<T: Decodable & Sendable>(_ path: String, token: String) async throws -> ([T], Bool) {
        var result: [T] = []
        for page in 1...maximumPages {
            let batch: [T] = try await request("\(path)\(path.contains("?") ? "&" : "?")per_page=\(pageSize)&page=\(page)", token: token)
            result += batch
            if batch.count < pageSize { return (result, false) }
        }
        return (result, true)
    }
    public func inbox(token: String, login: String, page: PRPage) async throws -> Inbox {
        var warnings: Set<String> = []
        var accessIssues: [GitHubAccessIssue] = []
        var teams: [Team] = []
        if page == .reviews {
            do {
                let (items, partial): ([Team], Bool) = try await list("/user/teams", token: token)
                teams = items
                if partial { warnings.insert("Team membership is incomplete; some requests may be missing.") }
            } catch BuddyError.permissions {
                accessIssues.append(.teamMembership)
            }
        }
        struct SearchItem: Decodable, Sendable { let number: Int; let repository_url: URL }
        struct Search: Decodable, Sendable {
            let total_count: Int; let incomplete_results: Bool; let items: [SearchItem]
        }
        let queries = page == .authored ? ["is:pr is:open author:\(login)"] :
            ["is:pr is:open review-requested:\(login)", "is:pr is:open reviewed-by:\(login)"] +
            teams.map { "is:pr is:open team-review-requested:\($0.organization.login)/\($0.slug)" }
        var candidates: [String: SearchItem] = [:]
        for query in queries {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            for index in 1...10 {
                let result: Search = try await request("/search/issues?\(components.percentEncodedQuery!)&per_page=100&page=\(index)", token: token)
                if result.incomplete_results || result.total_count > 1000 {
                    warnings.insert("GitHub search returned partial results. Some pull requests may be missing.")
                }
                for item in result.items { candidates["\(item.repository_url)/\(item.number)"] = item }
                if index * 100 >= result.total_count || result.items.count < 100 { break }
            }
        }
        var pulls: [PullRequest] = []
        // Bounded, sequential detail requests avoid bursts against GitHub's secondary rate limits.
        for item in candidates.values.sorted(by: { $0.repository_url.absoluteString < $1.repository_url.absoluteString }) {
            let url = item.repository_url
            let parts = url.path.split(separator: "/")
            let valid = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
            guard url.scheme == "https", url.host == "api.github.com", url.port == nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  parts.count == 3, parts[0] == "repos", item.number > 0,
                  parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(valid.contains) }) else {
                throw BuddyError.invalidResponse
            }
            let repository = "\(parts[1])/\(parts[2])"
            let path = "/repos/\(repository)"
            do {
                let pull: Pull = try await request("\(path)/pulls/\(item.number)", token: token)
                guard pull.html_url.scheme == "https", pull.html_url.host == "github.com",
                      pull.html_url.user == nil, pull.html_url.password == nil else { throw BuddyError.invalidResponse }
                if page == .authored {
                    if pull.state == "open", pull.user.login.lowercased() == login.lowercased() {
                        pulls.append(Classification.authored(pull, repository: repository))
                    }
                } else {
                    let (reviews, partialReviews): ([Review], Bool) = try await list("\(path)/pulls/\(item.number)/reviews", token: token)
                    let (events, partialEvents): ([TimelineEvent], Bool) = try await list("\(path)/issues/\(item.number)/timeline", token: token)
                    if partialReviews || partialEvents { warnings.insert("History for \(repository)#\(item.number) is incomplete; classification may be uncertain.") }
                    if var classified = Classification.classify(pull, reviews: reviews, events: events, login: login, teams: teams, repository: repository) {
                        classified.uncertain = classified.uncertain || partialReviews || partialEvents
                        pulls.append(classified)
                    }
                }
            } catch BuddyError.permissions {
                accessIssues.append(.repository("\(repository)#\(item.number)"))
            }
        }
        return Inbox(pulls: pulls.sorted { $0.updatedAt > $1.updatedAt }, warnings: warnings.sorted(), accessIssues: accessIssues)
    }
}
