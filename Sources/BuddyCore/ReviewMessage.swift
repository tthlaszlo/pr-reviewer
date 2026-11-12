import Foundation
import Markdown

public indirect enum ReviewMessageBlock: Equatable, Sendable {
    case paragraph(AttributedString)
    case heading(Int, AttributedString)
    case code(language: String?, text: String)
    case list([ReviewMessageListItem])
    case quote([ReviewMessageBlock])
    case table(header: [AttributedString], rows: [[AttributedString]])
    case disclosure(title: String, blocks: [ReviewMessageBlock])
    case divider
}
public struct ReviewMessageListItem: Equatable, Sendable {
    public let marker: String
    public let blocks: [ReviewMessageBlock]
}

/// Parses locally. HTML is converted to native content, never executed or fetched.
public enum ReviewMessage {
    public static func parse(_ source: String) -> [ReviewMessageBlock] {
        blocks(Array(Document(parsing: source, options: [.disableSmartOpts]).children), depth: 0)
    }
    public static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private struct Details {
        var title = "Details"
        var content: [ReviewMessageBlock] = []
    }
    private static func blocks(_ nodes: [any Markup], depth: Int) -> [ReviewMessageBlock] {
        guard depth < 32 else { return [.paragraph(AttributedString(nodes.map { $0.format() }.joined(separator: "\n")))] }
        var result: [ReviewMessageBlock] = []
        var details: [Details] = []
        func append(_ values: [ReviewMessageBlock]) {
            if details.isEmpty { result += values } else { details[details.count - 1].content += values }
        }
        func finishDetails() {
            guard let item = details.popLast() else { return }
            append([.disclosure(title: item.title, blocks: item.content)])
        }
        for node in nodes {
            switch node {
            case let paragraph as Paragraph: append([.paragraph(inline(paragraph))])
            case let heading as Heading: append([.heading(heading.level, inline(heading))])
            case let code as CodeBlock: append([.code(language: code.language, text: code.code)])
            case let quote as BlockQuote: append([.quote(blocks(Array(quote.children), depth: depth + 1))])
            case let list as OrderedList:
                append([.list(list.listItems.enumerated().map { index, item in
                    ReviewMessageListItem(marker: "\(list.startIndex + UInt(index)).", blocks: blocks(Array(item.children), depth: depth + 1))
                })])
            case let list as UnorderedList:
                append([.list(list.listItems.map { item in
                    let marker = item.checkbox.map { $0 == .checked ? "☑" : "☐" } ?? "•"
                    return ReviewMessageListItem(marker: marker, blocks: blocks(Array(item.children), depth: depth + 1))
                })])
            case let table as Markdown.Table:
                append([.table(header: table.head.cells.map { inline($0) },
                               rows: table.body.rows.map { $0.cells.map { inline($0) } })])
            case is ThematicBreak: append([.divider])
            case let html as HTMLBlock:
                let source = removingHiddenHTML(html.rawHTML)
                let pattern = #"(?is)<details\b[^>]*>|</details\s*>|<summary\b[^>]*>(.*?)</summary\s*>"#
                let regex = try! NSRegularExpression(pattern: pattern)
                let ns = source as NSString
                var offset = 0
                func content(_ fragment: String) {
                    // Parse fences before removing HTML, preserving literal tags inside code.
                    for child in Document(parsing: fragment, options: [.disableSmartOpts]).children {
                        if let html = child as? HTMLBlock {
                            let clean = plainHTML(html.rawHTML).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty { append(blocks(Array(Document(parsing: clean, options: [.disableSmartOpts]).children), depth: depth + 1)) }
                        } else { append(blocks([child], depth: depth + 1)) }
                    }
                }
                for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                    content(ns.substring(with: NSRange(location: offset, length: match.range.location - offset)))
                    let token = ns.substring(with: match.range).lowercased()
                    if token.hasPrefix("<details") { details.append(Details()) }
                    else if token.hasPrefix("</details") { finishDetails() }
                    else if !details.isEmpty, match.range(at: 1).location != NSNotFound {
                        let title = plainHTML(ns.substring(with: match.range(at: 1)))
                        details[details.count - 1].title = String(inline(Document(parsing: title, options: [.disableSmartOpts])).characters)
                    }
                    offset = NSMaxRange(match.range)
                }
                content(ns.substring(from: offset))
            default: append(blocks(Array(node.children), depth: depth + 1))
            }
        }
        while !details.isEmpty { finishDetails() }
        return result
    }
    private static func inline(_ node: any Markup) -> AttributedString {
        if let text = node as? Markdown.Text { return AttributedString(text.string) }
        if let code = node as? InlineCode {
            var text = AttributedString(code.code); text.inlinePresentationIntent = .code; return text
        }
        if node is SoftBreak { return AttributedString(" ") }
        if node is LineBreak { return AttributedString("\n") }
        if let html = node as? InlineHTML {
            let clean = plainHTML(html.rawHTML)
            return AttributedString(clean)
        }
        var result = node.children.reduce(into: AttributedString()) { $0 += inline($1) }
        let intent: InlinePresentationIntent? = node is Strong ? .stronglyEmphasized : node is Emphasis ? .emphasized : node is Strikethrough ? .strikethrough : nil
        if let intent {
            for run in Array(result.runs) {
                result[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
            }
        }
        if let link = node as? Markdown.Link, let destination = link.destination, let url = safeURL(destination) { result.link = url }
        return result
    }
    private static func removingHiddenHTML(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?is)<!--.*?-->|<(script|style)\b[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
    }
    private static func plainHTML(_ value: String) -> String {
        var text = removingHiddenHTML(value)
        let images = try! NSRegularExpression(pattern: #"(?is)<img\b[^>]*\balt\s*=\s*(["'])(.*?)\1[^>]*>"#)
        let ns = text as NSString
        for match in images.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: ns.substring(with: match.range(at: 2))) }
        }
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div|li|h[1-6])\s*>"#, with: "\n\n", options: .regularExpression)
        return text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
    }
}

public struct ReviewFeedbackGroup: Identifiable, Equatable, Sendable {
    public var id: String { author.lowercased() }
    public let author: String
    public let reviews: [SubmittedReview]
    public let comments: [ReviewComment]
    public var summary: String { "\(feedbackCount(reviews.count, singular: "review")) · \(feedbackCount(comments.count, singular: "code comment"))" }
    public var isBot: Bool { author.lowercased().hasSuffix("[bot]") }
    public var initials: String { String(author.prefix(2)).uppercased() }
}
private func feedbackCount(_ count: Int, singular: String) -> String { "\(count) \(singular)\(count == 1 ? "" : "s")" }

public extension ReviewHistory {
    var feedbackSummary: String {
        "\(feedbackCount(feedbackGroups.count, singular: "reviewer")) · \(feedbackCount(reviews.count, singular: "review")) · \(feedbackCount(comments.count, singular: "code comment"))"
    }
    var feedbackGroups: [ReviewFeedbackGroup] {
        var authors: [String] = []
        for author in reviews.map(\.reviewer) + comments.map(\.author) {
            if !authors.contains(where: { $0.lowercased() == author.lowercased() }) { authors.append(author) }
        }
        return authors.map { author in
            ReviewFeedbackGroup(author: author,
                                reviews: reviews.filter { $0.reviewer.lowercased() == author.lowercased() },
                                comments: comments.filter { $0.author.lowercased() == author.lowercased() })
        }
    }
}
