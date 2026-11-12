import Foundation

/// Counts always describe the available snapshot; filtering never changes tab totals.
public struct PullRequestListSnapshot: Sendable {
    public let page: PRPage
    public let group: ReviewGroup
    public let query: String
    public let inbox: Inbox?
    public init(page: PRPage, group: ReviewGroup, query: String, inbox: Inbox?) {
        self.page = page; self.group = group; self.query = query; self.inbox = inbox
    }
    public var rows: [PullRequest] {
        (inbox?.pulls ?? []).filter { (page == .authored || $0.group == group) && $0.matches(query) }
    }
    public func count(in group: ReviewGroup) -> Int? {
        inbox.map { $0.pulls.filter { $0.group == group }.count }
    }
    public var countLabel: String {
        guard let inbox else { return "—" }
        let count = inbox.pulls.count
        return "\(count) \(inbox.accessIssues.isEmpty && inbox.warnings.isEmpty ? "open" : "available") pull request\(count == 1 ? "" : "s")"
    }
    public var resultsLabel: String {
        guard inbox != nil else { return "Waiting for GitHub" }
        return "\(rows.count) shown"
    }
    public var draftCount: Int? { inbox.map { $0.pulls.filter(\.draft).count } }
    public var sectionTitle: String { page == .reviews ? group.title : "Your open pull requests" }
}
