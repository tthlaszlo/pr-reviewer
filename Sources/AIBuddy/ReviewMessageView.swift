import SwiftUI
import BuddyCore

struct ReviewMessageView: View {
    private let blocks: [ReviewMessageBlock]
    init(_ source: String) { blocks = ReviewMessage.parse(source) }
    var body: some View {
        MessageBlocks(blocks: blocks)
            .accessibilityElement(children: .contain)
            .font(Focus.font(14)).lineSpacing(5)
            .environment(\.openURL, OpenURLAction { url in
                ReviewMessage.safeURL(url.absoluteString) == nil ? .discarded : .systemAction
            })
    }
}
private struct MessageBlocks: View {
    let blocks: [ReviewMessageBlock]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MessageBlock(block: block)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct MessageBlock: View {
    let block: ReviewMessageBlock
    @ViewBuilder var body: some View {
        switch block {
        case .paragraph(let text): richText(text)
        case .heading(let level, let text):
            richText(text).font(Focus.font(level == 1 ? 21 : level == 2 ? 18 : 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader).padding(.top, 4)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language.uppercased()).font(Focus.font(10, weight: .semibold)).tracking(1)
                        .foregroundStyle(Focus.muted).padding(.horizontal, 12).padding(.vertical, 8)
                    Rectangle().fill(Focus.border).frame(height: 1)
                }
                ScrollView(.horizontal) {
                    Text(text.trimmingCharacters(in: .newlines))
                        .font(.system(size: 12, design: .monospaced)).lineSpacing(4)
                        .textSelection(.enabled).padding(12).accessibilityIdentifier("review-code-text")
                }
            }.background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Focus.border))
        case .list(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.marker).foregroundStyle(Focus.muted).frame(minWidth: 16, alignment: .trailing)
                        MessageBlocks(blocks: item.blocks)
                    }
                }
            }
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Focus.accent.opacity(0.45)).frame(width: 3)
                MessageBlocks(blocks: blocks).foregroundStyle(Focus.muted)
            }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        case .table(let header, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, cell in richText(cell).fontWeight(.semibold) } }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in richText(cell) } }
                    }
                }.padding(12)
            }.background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 6))
        case .disclosure(let title, let blocks):
            MessageDisclosure(title: title, blocks: blocks)
                .padding(12).background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 6))
        case .divider: Rectangle().fill(Focus.border).frame(height: 1)
        }
    }
    private func richText(_ source: AttributedString) -> some View {
        var text = source
        for run in source.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].font = .system(size: 12, design: .monospaced)
            text[run.range].backgroundColor = Focus.soft
            text[run.range].foregroundColor = Focus.accentText
        }
        return Text(text).textSelection(.enabled).tint(Focus.accentText)
            .accessibilityIdentifier("review-message-text")
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MessageDisclosure: View {
    let title: String
    let blocks: [ReviewMessageBlock]
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Label(title, systemImage: "text.alignleft").font(Focus.font(12, weight: .medium))
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Focus.accentText)
                .accessibilityIdentifier("review-details-toggle")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { MessageBlocks(blocks: blocks).padding(.top, 12) }
        }
    }
}
