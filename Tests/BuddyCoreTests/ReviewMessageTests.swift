import Foundation
import Testing
@testable import BuddyCore

struct ReviewMessageTests {
    @Test func markdownStructureAndFormatting() throws {
        let blocks = ReviewMessage.parse("## Feedback\n\n**Important**: use `currentUser` and [docs](https://example.com).\n\n- First\n- Second\n\n> Be careful\n\n---")
        #expect(blocks.count == 5)
        guard case .heading(2, let title) = blocks[0], case .paragraph(let text) = blocks[1],
              case .list(let items) = blocks[2], case .quote = blocks[3], case .divider = blocks[4] else {
            Issue.record("Expected native heading, paragraph, list, quote and divider"); return
        }
        #expect(String(title.characters) == "Feedback")
        #expect(String(text.characters) == "Important: use currentUser and docs.")
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        #expect(text.runs.contains { $0.link?.absoluteString == "https://example.com" })
        #expect(items.count == 2)
    }
    @Test func greptileHTMLBadgeAndDisclosureRegression() {
        let source = #"""
        <a href="#"><img alt="P1" src="https://example.com/p1.svg" align="top"></a> **Fresh accounts still wait**

        `responsible_user` checks the failed run's user.

        <details><summary>Prompt To Fix With AI</summary>

        ```markdown
        This is a comment left during a code review.
        Path: server/retry.ts
        Line: 55-58
        Preserve <User> and **literal** markup.
        ```

        </details>
        """#
        let blocks = ReviewMessage.parse(source)
        #expect(blocks.count == 3)
        guard case .paragraph(let heading) = blocks.first,
              case .disclosure(let title, let contents) = blocks.last else {
            Issue.record("Expected formatted badge/title and collapsible prompt"); return
        }
        #expect(String(heading.characters) == "P1 Fresh accounts still wait")
        #expect(title == "Prompt To Fix With AI")
        guard case .code(let language, let code) = contents.first else { Issue.record("Missing code block"); return }
        #expect(language == "markdown")
        #expect(code.contains("Preserve <User> and **literal** markup."))
        #expect(!code.contains("</details>"))
    }
    @Test func nestedAndUnclosedDisclosuresKeepContent() {
        let blocks = ReviewMessage.parse("<details><summary>Outer</summary>\n\nText\n\n<details><summary>Inner</summary>\n\nMore text\n\n</details>")
        guard case .disclosure(let title, let contents) = blocks.first else { Issue.record("Missing outer"); return }
        #expect(title == "Outer")
        #expect(contents.count == 2)
        guard case .disclosure(let nestedTitle, _) = contents.last else { Issue.record("Missing inner"); return }
        #expect(nestedTitle == "Inner")
    }
    @Test func codeNeverInterpretsHTMLOrMarkdown() {
        let source = "```html\n<details><summary>Not a control</summary></details>\n<img alt=\"P1\" src=\"x\">\n```"
        let blocks = ReviewMessage.parse(source)
        #expect(blocks.count == 1)
        guard case .code(_, let code) = blocks[0] else { Issue.record("Expected literal code"); return }
        #expect(code.contains("<details>"))
        #expect(code.contains("<img"))
    }
    @Test func tablesTaskListsAndOrderedLists() {
        let blocks = ReviewMessage.parse("| File | Status |\n| --- | --- |\n| API | OK |\n\n- [x] Done\n- [ ] Pending\n\n3. Third\n4. Fourth")
        #expect(blocks.count == 3)
        guard case .table(let header, let rows) = blocks[0], case .list(let tasks) = blocks[1],
              case .list(let ordered) = blocks[2] else { Issue.record("Missing structured content"); return }
        #expect(header.map { String($0.characters) } == ["File", "Status"])
        #expect(rows.count == 1)
        #expect(tasks.map(\.marker) == ["☑", "☐"])
        #expect(ordered.map(\.marker) == ["3.", "4."])
    }
    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,test", "https://user:secret@example.com", "//example.com", "#anchor"])
    func unsafeLinksAreNotInteractive(destination: String) {
        #expect(ReviewMessage.safeURL(destination) == nil)
        let blocks = ReviewMessage.parse("[link](\(destination))")
        if case .paragraph(let text) = blocks.first { #expect(text.runs.allSatisfy { $0.link == nil }) }
    }
    @Test func imagesScriptsAndEntities() {
        let blocks = ReviewMessage.parse("<script>alert('x')</script>\n\n<!-- hidden -->\n\n<img alt='P2' src='https://example.com/tracker'>\n\nHello &amp; **world**\n\n![Diagram](https://example.com/image.png)")
        #expect(blocks.count == 3)
        guard case .paragraph(let badge) = blocks[0], case .paragraph(let body) = blocks[1], case .paragraph(let image) = blocks[2] else {
            Issue.record("Missing readable content"); return
        }
        #expect(String(badge.characters) == "P2")
        #expect(String(body.characters) == "Hello & world")
        #expect(String(image.characters) == "Diagram")
    }
    @Test func imageAlternativeKeepsQuotedText() {
        let blocks = ReviewMessage.parse("<img alt=\"Bob's feedback\" src=\"https://example.com/image\">")
        guard case .paragraph(let text) = blocks.first else { Issue.record("Missing image alternative"); return }
        #expect(String(text.characters) == "Bob's feedback")
    }
    @Test func emptyUnicodeAndNestedInlineStyles() {
        #expect(ReviewMessage.parse("").isEmpty)
        let blocks = ReviewMessage.parse("**Use `árvíz` safely**")
        guard case .paragraph(let text) = blocks.first else { Issue.record("Missing paragraph"); return }
        #expect(String(text.characters) == "Use árvíz safely")
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains([.code, .stronglyEmphasized]) == true })
    }
    @Test func groupAuthorsCaseInsensitivelyAndRetainStandaloneBotComments() throws {
        let review = try decode(SubmittedReview.self, Data(#"{"id":1,"user":{"login":"Reviewer"},"state":"APPROVED","submitted_at":"2026-11-11T10:00:00Z"}"#.utf8))
        let comments = try decode([ReviewComment].self, Data(#"[{"id":1,"user":{"login":"reviewer"},"body":"Follow-up","path":"a.swift","created_at":"2026-11-11T11:00:00Z"},{"id":2,"user":{"login":"greptile-apps[bot]"},"body":"Feedback","path":"a.swift","created_at":"2026-11-11T12:00:00Z"}]"#.utf8))
        let groups = ReviewHistory(reviews: [review], comments: comments).feedbackGroups
        #expect(groups.count == 2)
        #expect(groups[0].reviews.count == 1 && groups[0].comments.count == 1)
        #expect(groups[0].summary == "1 review · 1 code comment")
        #expect(ReviewHistory(reviews: [review], comments: comments).feedbackSummary == "2 reviewers · 1 review · 2 code comments")
        #expect(groups[0].author == "Reviewer" && groups[0].initials == "RE")
        #expect(!groups[0].isBot)
        #expect(groups[1].isBot && groups[1].reviews.isEmpty && groups[1].comments.count == 1)
        #expect(ReviewHistory().feedbackGroups.isEmpty)
    }
}
