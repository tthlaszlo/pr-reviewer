import Foundation
import Testing
@testable import BuddyCore

struct PullRequestListTests {
    private var inbox: Inbox {
        var awaiting = sampleInbox().pulls[0]
        awaiting.title = "Handle authorization"; awaiting.personal = true
        var waiting = awaiting; waiting.id = 2; waiting.number = 11; waiting.group = .waiting
        waiting.title = "Update storage"; waiting.draft = true
        var again = awaiting; again.id = 3; again.number = 12; again.group = .requestedAgain
        again.title = "Fix retry"; again.teams = ["acme/backend"]
        return Inbox(pulls: [awaiting, waiting, again])
    }
    @Test func unknownAndEmptyCountsAreDistinct() {
        let unknown = PullRequestListSnapshot(page: .reviews, group: .awaiting, query: "", inbox: nil)
        #expect(unknown.count(in: .awaiting) == nil)
        #expect(unknown.countLabel == "—")
        #expect(unknown.draftCount == nil)
        #expect(unknown.resultsLabel == "Waiting for GitHub")
        let empty = PullRequestListSnapshot(page: .authored, group: .awaiting, query: "", inbox: Inbox(pulls: []))
        #expect(empty.countLabel == "0 open pull requests")
        #expect(empty.draftCount == 0)
        #expect(empty.resultsLabel == "0 shown")
    }
    @Test func reviewTabsKeepUnfilteredCounts() {
        let view = PullRequestListSnapshot(page: .reviews, group: .waiting, query: "storage", inbox: inbox)
        #expect(view.rows.map(\.number) == [11])
        #expect(ReviewGroup.allCases.map { view.count(in: $0) } == [1, 1, 1])
        #expect(view.countLabel == "3 open pull requests")
        #expect(view.resultsLabel == "1 shown")
        #expect(view.sectionTitle == ReviewGroup.waiting.title)
        let absent = PullRequestListSnapshot(page: .reviews, group: .waiting, query: "retry", inbox: inbox)
        #expect(absent.rows.isEmpty)
        #expect(absent.count(in: .requestedAgain) == 1)
    }
    @Test func authoredShowsAllGroupsAndPreservesOrder() {
        let all = PullRequestListSnapshot(page: .authored, group: .waiting, query: "", inbox: inbox)
        #expect(all.rows.map(\.number) == [10, 11, 12])
        #expect(all.draftCount == 1)
        #expect(all.sectionTitle == "Your open pull requests")
        let filtered = PullRequestListSnapshot(page: .authored, group: .awaiting, query: "backend", inbox: inbox)
        #expect(filtered.rows.map(\.number) == [12])
        #expect(filtered.draftCount == 1)
    }
    @Test func partialResultsAreLabelledAvailable() {
        var partial = inbox; partial.accessIssues = [.teamMembership]
        #expect(PullRequestListSnapshot(page: .reviews, group: .awaiting, query: "", inbox: partial).countLabel == "3 available pull requests")
        partial.accessIssues = []; partial.warnings = ["Search results are incomplete"]
        #expect(PullRequestListSnapshot(page: .authored, group: .awaiting, query: "", inbox: partial).countLabel == "3 available pull requests")
    }
    @Test func singularCountAndMetadataFiltering() {
        let one = sampleInbox()
        let view = PullRequestListSnapshot(page: .authored, group: .waiting, query: "#10", inbox: one)
        #expect(view.rows.count == 1)
        #expect(view.countLabel == "1 open pull request")
        #expect(PullRequestListSnapshot(page: .reviews, group: .awaiting, query: "LACKO", inbox: one).rows.count == 1)
    }
}
