import Foundation

public enum PRPage: String, Codable, CaseIterable, Sendable {
    case reviews, authored
    public var title: String { self == .reviews ? "Review requests" : "My pull requests" }
}

public enum ReviewGroup: String, Codable, CaseIterable, Sendable {
    case awaiting, waiting, requestedAgain
    public var title: String {
        switch self {
        case .awaiting: "Awaiting my review"
        case .waiting: "Reviewed · waiting"
        case .requestedAgain: "Review requested again"
        }
    }
}

public struct GitHubUser: Codable, Equatable, Sendable {
    public let id: Int64
    public let login: String
    public init(id: Int64, login: String) { self.id = id; self.login = login }
}

public struct PullRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64
    public var number: Int
    public var title: String
    public var url: URL
    public var repository: String
    public var author: String
    public var updatedAt: Date
    public var draft: Bool
    public var group: ReviewGroup?
    public var personal: Bool
    public var teams: [String]
    public var reviewState: String?
    public var changedSinceReview: Bool
    public var uncertain: Bool
    public init(id: Int64, number: Int, title: String, url: URL, repository: String,
                author: String, updatedAt: Date, draft: Bool = false, group: ReviewGroup? = nil,
                personal: Bool = false, teams: [String] = [], reviewState: String? = nil,
                changedSinceReview: Bool = false, uncertain: Bool = false) {
        self.id = id; self.number = number; self.title = title; self.url = url
        self.repository = repository; self.author = author; self.updatedAt = updatedAt
        self.draft = draft; self.group = group; self.personal = personal; self.teams = teams
        self.reviewState = reviewState; self.changedSinceReview = changedSinceReview; self.uncertain = uncertain
    }
    public func matches(_ query: String) -> Bool {
        query.isEmpty || "\(title) \(repository) #\(number) \(author) \(teams.joined(separator: " "))"
            .localizedCaseInsensitiveContains(query)
    }
}

public enum GitHubAccessIssue: Codable, Equatable, Hashable, Sendable {
    case teamMembership
    case repository(String)

    public var explanation: String {
        switch self {
        case .teamMembership: "Team requests may be missing because GitHub did not allow access to your teams."
        case .repository(let name): "GitHub did not allow access to \(name). It may be restricted or no longer available."
        }
    }
}

public enum GitHubAccessHelp {
    public static let applicationsURL = URL(string: "https://github.com/settings/applications")!
    public static let organizationURL = URL(string: "https://docs.github.com/en/account-and-profile/how-tos/organization-membership/requesting-organization-approval-for-oauth-apps")!
    public static let ssoURL = URL(string: "https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/authorizing-an-app-for-single-sign-on")!

    public static func settingsURL(clientID: String) -> URL {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !id.isEmpty, id.unicodeScalars.allSatisfy(allowed.contains) else { return applicationsURL }
        return URL(string: "https://github.com/settings/connections/applications/\(id)")!
    }
}

public struct Inbox: Codable, Equatable, Sendable {
    public var pulls: [PullRequest]
    public var warnings: [String]
    public var syncedAt: Date
    public var accessIssues: [GitHubAccessIssue]
    public init(pulls: [PullRequest], warnings: [String] = [], syncedAt: Date = Date(),
                accessIssues: [GitHubAccessIssue] = []) {
        self.pulls = pulls; self.warnings = warnings; self.syncedAt = syncedAt; self.accessIssues = accessIssues
    }
    private enum CodingKeys: String, CodingKey { case pulls, warnings, syncedAt, accessIssues }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pulls = try values.decode([PullRequest].self, forKey: .pulls)
        warnings = try values.decode([String].self, forKey: .warnings)
        syncedAt = try values.decode(Date.self, forKey: .syncedAt)
        // Snapshots from the first native version have no structured access metadata.
        accessIssues = try values.decodeIfPresent([GitHubAccessIssue].self, forKey: .accessIssues) ?? []
    }
}

public enum BuddyError: Error, Equatable, LocalizedError, Sendable {
    case unavailable, unauthorized, permissions, rateLimited, invalidResponse
    case configuration, denied, expired, storage, keychain(Int32)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "GitHub is unavailable. Check your connection and try again."
        case .unauthorized: "Your GitHub authorization is no longer valid. Reconnect GitHub to restore access."
        case .permissions: "GitHub access is restricted. Check repository access, organization approval and SSO authorization."
        case .rateLimited: "GitHub's rate limit was reached. Please try again later."
        case .invalidResponse: "GitHub returned an unexpected response. Please try again."
        case .configuration: "This build cannot connect to GitHub yet. Please use a build configured by the app developer."
        case .denied: "GitHub authorization was declined. You can try connecting again."
        case .expired: "The connection code expired. Please start again."
        case .storage: "Local data could not be read or saved. Please check available disk space and file permissions."
        case .keychain: "Your GitHub credential could not be accessed in Keychain. Please try again."
        }
    }
}

// GitHub wire types are separate from persisted UI models.
struct UserRef: Codable, Sendable { let login: String }
struct TeamRef: Codable, Sendable { let id: Int64 }
struct Team: Codable, Sendable {
    let id: Int64
    let slug: String
    let organization: UserRef
}
struct Pull: Codable, Sendable {
    let id: Int64
    let number: Int
    let title: String
    let html_url: URL
    let user: UserRef
    let updated_at: Date
    let draft: Bool
    let state: String
    struct Head: Codable, Sendable { let sha: String }
    let head: Head
    let requested_reviewers: [UserRef]
    let requested_teams: [TeamRef]
}
struct Review: Codable, Sendable {
    let user: UserRef
    let state: String
    let submitted_at: Date?
    let commit_id: String
}
struct TimelineEvent: Codable, Sendable {
    let event: String
    let created_at: Date?
    let requested_reviewer: UserRef?
    let requested_team: TeamRef?
}

enum Classification {
    static func classify(_ pull: Pull, reviews: [Review], events: [TimelineEvent],
                         login: String, teams: [Team], repository: String) -> PullRequest? {
        guard pull.state == "open" else { return nil }
        let personal = pull.requested_reviewers.contains { $0.login.lowercased() == login.lowercased() }
        let requestedTeams = teams.filter { team in pull.requested_teams.contains { $0.id == team.id } }
        let review = reviews.filter {
            $0.user.login.lowercased() == login.lowercased() && $0.state != "PENDING" && $0.submitted_at != nil
        }.max { $0.submitted_at! < $1.submitted_at! }
        let requested = personal || !requestedTeams.isEmpty
        guard review != nil || requested else { return nil }
        let relevant = events.filter { event in
            event.event == "review_requested" && event.created_at != nil &&
            ((personal && event.requested_reviewer?.login.lowercased() == login.lowercased()) ||
             requestedTeams.contains { $0.id == event.requested_team?.id })
        }
        let newRequest = relevant.contains { ($0.created_at ?? .distantPast) > (review?.submitted_at ?? .distantPast) }
        var result = authored(pull, repository: repository)
        result.group = review == nil ? .awaiting : requested && newRequest ? .requestedAgain : .waiting
        result.personal = personal
        result.teams = requestedTeams.map { "\($0.organization.login)/\($0.slug)" }
        result.reviewState = review?.state
        result.changedSinceReview = review.map { $0.commit_id != pull.head.sha } ?? false
        result.uncertain = review != nil && requested && relevant.isEmpty
        return result
    }
    static func authored(_ pull: Pull, repository: String) -> PullRequest {
        PullRequest(id: pull.id, number: pull.number, title: pull.title, url: pull.html_url,
                    repository: repository, author: pull.user.login, updatedAt: pull.updated_at, draft: pull.draft)
    }
}
