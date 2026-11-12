import Foundation

public struct SubmittedReview: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let user: GitHubUserReference?
    public let state: String
    public let body: String?
    public let submittedAt: Date?
    public var reviewer: String { user?.login ?? "Deleted user" }
    public var status: String {
        switch state {
        case "APPROVED": "Approved"
        case "CHANGES_REQUESTED": "Changes requested"
        case "COMMENTED": "Commented"
        case "DISMISSED": "Dismissed"
        default: state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    enum CodingKeys: String, CodingKey {
        case id, user, state, body
        case submittedAt = "submitted_at"
    }
}
public struct GitHubUserReference: Decodable, Equatable, Sendable {
    public let login: String
}
public struct ReviewComment: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let user: GitHubUserReference?
    public let body: String
    public let path: String
    public let line: Int?
    public let originalLine: Int?
    public let createdAt: Date
    public var author: String { user?.login ?? "Deleted user" }
    public var location: String {
        if let line { return "\(path):\(line)" }
        if let originalLine { return "\(path):\(originalLine) · Outdated" }
        return path
    }
    enum CodingKeys: String, CodingKey {
        case id, user, body, path, line
        case originalLine = "original_line"
        case createdAt = "created_at"
    }
}
public struct ReviewHistory: Equatable, Sendable {
    public let reviews: [SubmittedReview]
    public let comments: [ReviewComment]
    public let partial: Bool
    public init(reviews: [SubmittedReview] = [], comments: [ReviewComment] = [], partial: Bool = false) {
        self.reviews = reviews.sorted { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }
        self.comments = comments.sorted { $0.createdAt < $1.createdAt }
        self.partial = partial
    }
}
