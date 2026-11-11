import Foundation
import Testing
@testable import BuddyCore

struct TimelineTests {
    @Test func nonRequestEventsNeedNotHaveCreatedAt() throws {
        // GitHub commit timeline events use author.date instead of created_at.
        let data = Data(#"[{"event":"committed","sha":"abc","author":{"date":"2026-11-11T12:00:00Z"}},{"event":"review_requested","requested_reviewer":{"login":"lacko"}}]"#.utf8)
        let events = try decode([TimelineEvent].self, data)
        let pull = try decode(Pull.self, Data(pullJSON.utf8))
        let review = try decode(Review.self, Data(reviewJSON.utf8))
        let result = Classification.classify(pull, reviews: [review], events: events, login: "lacko", teams: [], repository: "acme/api")
        #expect(result?.group == .waiting)
        #expect(result?.uncertain == true)
    }
}
