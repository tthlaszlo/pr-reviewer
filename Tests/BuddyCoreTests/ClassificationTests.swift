import Foundation
import Testing
@testable import BuddyCore

struct ClassificationTests {
    func classify(pull: String = pullJSON, reviews: String = "[]", events: String = "[]") throws -> PullRequest? {
        Classification.classify(try decode(Pull.self, Data(pull.utf8)),
            reviews: try decode([Review].self, Data(reviews.utf8)),
            events: try decode([TimelineEvent].self, Data(events.utf8)), login: "lacko",
            teams: [try decode(Team.self, Data(teamJSON.utf8))], repository: "acme/api")
    }
    @Test func personalAndTeamRequests() throws {
        let personal = try classify(pull: pullJSON.replacingOccurrences(of: "lacko", with: "LACKO"))
        #expect(personal?.group == .awaiting); #expect(personal?.personal == true)
        let team = try classify(pull: pullJSON.replacingOccurrences(of: #""requested_reviewers":[{"login":"lacko"}]"#, with: #""requested_reviewers":[]"#).replacingOccurrences(of: #""requested_teams":[]"#, with: #""requested_teams":[{"id":42}]"#))
        #expect(team?.teams == ["acme/backend"]); #expect(team?.personal == false)
    }
    @Test func onlySubmittedOwnReviewsCount() throws {
        let other = reviewJSON.replacingOccurrences(of: "lacko", with: "other")
        let pending = reviewJSON.replacingOccurrences(of: "APPROVED", with: "PENDING")
        #expect(try classify(reviews: "[\(other),\(pending)]")?.group == .awaiting)
        #expect(try classify(reviews: "[\(reviewJSON.replacingOccurrences(of: #""2026-11-10T12:00:00Z""#, with: "null"))]")?.group == .awaiting)
    }
    @Test func reviewedWaitingAndCommitChanges() throws {
        let noRequest = pullJSON.replacingOccurrences(of: #""requested_reviewers":[{"login":"lacko"}]"#, with: #""requested_reviewers":[]"#)
        #expect(try classify(pull: noRequest, reviews: "[\(reviewJSON)]")?.group == .waiting)
        #expect(try classify(reviews: "[\(reviewJSON)]")?.changedSinceReview == true)
        #expect(try classify(pull: pullJSON.replacingOccurrences(of: #""sha":"new""#, with: #""sha":"old""#), reviews: "[\(reviewJSON)]")?.changedSinceReview == false)
    }
    @Test func latestReviewAndReRequests() throws {
        #expect(try classify(reviews: "[\(reviewJSON)]", events: "[\(eventJSON)]")?.group == .requestedAgain)
        let later = reviewJSON.replacingOccurrences(of: "2026-11-10", with: "2026-11-12")
        #expect(try classify(reviews: "[\(later),\(reviewJSON)]", events: "[\(eventJSON)]")?.group == .waiting)
        #expect(try classify(reviews: "[\(reviewJSON)]")?.uncertain == true)
    }
    @Test func teamReRequestsAndIrrelevantHistory() throws {
        let teamPull = pullJSON.replacingOccurrences(of: #""requested_reviewers":[{"login":"lacko"}]"#, with: #""requested_reviewers":[]"#).replacingOccurrences(of: #""requested_teams":[]"#, with: #""requested_teams":[{"id":42}]"#)
        let teamEvent = eventJSON.replacingOccurrences(of: #""requested_reviewer":{"login":"lacko"}"#, with: #""requested_team":{"id":42}"#)
        #expect(try classify(pull: teamPull, reviews: "[\(reviewJSON)]", events: "[\(teamEvent)]")?.group == .requestedAgain)
        #expect(try classify(pull: teamPull, reviews: "[\(reviewJSON)]", events: "[\(eventJSON)]")?.uncertain == true)
        #expect(try classify(reviews: "[\(reviewJSON)]", events: "[\(eventJSON.replacingOccurrences(of: "review_requested", with: "committed"))]")?.group == .waiting)
    }
    @Test func closedAndIrrelevantExcluded() throws {
        #expect(try classify(pull: pullJSON.replacingOccurrences(of: #""state":"open""#, with: #""state":"closed""#)) == nil)
        #expect(try classify(pull: pullJSON.replacingOccurrences(of: "lacko", with: "other")) == nil)
    }
    @Test func searchMatchesMetadata() {
        let pull = sampleInbox().pulls[0]
        #expect(pull.matches("NATIVE")); #expect(pull.matches("acme/api"))
        #expect(pull.matches("#10")); #expect(pull.matches("lacko"))
        #expect(pull.matches("")); #expect(!pull.matches("not present"))
    }
}
