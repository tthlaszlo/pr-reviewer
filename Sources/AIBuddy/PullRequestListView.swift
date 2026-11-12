import SwiftUI
import AppKit
import BuddyCore

struct PullRequestListView: View {
    @ObservedObject var workspace: Workspace
    let page: PRPage
    @Binding var group: ReviewGroup
    @Binding var query: String
    @FocusState private var searchFocused: Bool
    private var inbox: Inbox? { workspace.inboxes[page] }
    private var snapshot: PullRequestListSnapshot { .init(page: page, group: group, query: query, inbox: inbox) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if workspace.starting && workspace.user == nil {
                state("Opening your workspace", detail: "Checking the GitHub connection stored on this Mac.", symbol: "hourglass")
            } else if workspace.user == nil || workspace.needsReconnection || workspace.connecting {
                ScrollView { GitHubConnectionView(workspace: workspace) }
            } else if workspace.restrictedPages.contains(page) {
                ScrollView { GitHubPermissionView(workspace: workspace, page: page, issues: [], fullPage: true) }
            } else {
                connectedContent
            }
            Spacer(minLength: 0)
            footer
        }.padding(28).frame(maxWidth: 1180)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("WORKSPACE / PULL REQUESTS").font(Focus.font(10, weight: .semibold))
                .tracking(1.3).foregroundStyle(Focus.muted)
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Focus.soft)
                    Image(systemName: page == .reviews ? "tray" : "arrow.triangle.pull")
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(Focus.accentText)
                }.frame(width: 48, height: 48).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(page.title).font(Focus.font(26, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(page == .reviews ? "Personal and team reviews, in one focused queue." : "Your work in progress, ready for the next step.")
                        .font(Focus.font(13)).foregroundStyle(Focus.muted)
                }
                Spacer(minLength: 0)
                if workspace.user != nil && !workspace.needsReconnection && !workspace.connecting && !workspace.restrictedPages.contains(page) {
                    Button { workspace.requestRefresh(page) } label: {
                        Label(workspace.refreshing.contains(page) ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                    }.buttonStyle(FocusButtonStyle()).disabled(workspace.refreshing.contains(page))
                        .accessibilityIdentifier("refresh")
                }
            }
        }
    }
    @ViewBuilder private var connectedContent: some View {
        if page == .reviews { reviewTabs }
        else {
            HStack(spacing: 12) {
                Label(snapshot.countLabel, systemImage: "arrow.triangle.pull")
                    .foregroundStyle(Focus.success)
                Rectangle().fill(Focus.border).frame(width: 1, height: 14)
                Label(snapshot.draftCount.map { "\($0) draft\($0 == 1 ? "" : "s")" } ?? "— drafts", systemImage: "doc.text")
                    .foregroundStyle(Focus.muted)
            }.font(Focus.font(12, weight: .medium)).accessibilityElement(children: .contain)
                .accessibilityIdentifier("authored-summary")
        }
        if let message = workspace.connectionError { warning(message) }
        if let message = workspace.errors[page] { warning(message) }
        if let inbox, !inbox.accessIssues.isEmpty {
            GitHubPermissionView(workspace: workspace, page: page, issues: inbox.accessIssues, fullPage: false)
        }
        if workspace.stale.contains(page) { warning("Showing saved data. This list may be out of date.") }
        ForEach(inbox?.warnings ?? [], id: \.self) { warning($0) }
        listSurface
    }
    private var reviewTabs: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(ReviewGroup.allCases, id: \.self) { tab in
                        Button { group = tab } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text(tab.title)
                                    Text(snapshot.count(in: tab).map(String.init) ?? "—")
                                        .monospacedDigit().padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(group == tab ? Focus.soft : Focus.sidebar)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }.font(Focus.font(12, weight: group == tab ? .semibold : .regular))
                                Rectangle().fill(group == tab ? Focus.accent : .clear).frame(height: 2)
                            }.foregroundStyle(group == tab ? Focus.accentText : Focus.muted)
                        }.buttonStyle(.plain).accessibilityIdentifier("group-\(tab.rawValue)")
                            .accessibilityAddTraits(group == tab ? [.isSelected] : [])
                    }
                }
            }.frame(height: 40)
            Rectangle().fill(Focus.border).frame(height: 1)
        }
    }
    private var listSurface: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { sectionHeading; Spacer(minLength: 12); search.frame(width: 270) }
                VStack(alignment: .leading, spacing: 12) { sectionHeading; search }
            }.padding(16)
            Rectangle().fill(Focus.border).frame(height: 1)
            if inbox == nil && workspace.refreshing.contains(page) {
                state("Loading pull requests", detail: "Reading your repositories and review history from GitHub.", symbol: "hourglass")
            } else if inbox == nil {
                state("Pull requests could not be loaded", detail: "Use Refresh to try again.", symbol: "exclamationmark.triangle")
            } else if snapshot.rows.isEmpty { emptyState }
            else {
                HStack {
                    Text("PULL REQUEST")
                    Spacer()
                    Text("UPDATED").frame(width: 108, alignment: .trailing)
                    Color.clear.frame(width: 16, height: 1)
                }.font(Focus.font(10, weight: .semibold)).tracking(1).foregroundStyle(Focus.muted)
                    .padding(.horizontal, 20).padding(.vertical, 10).background(Focus.background)
                    .accessibilityHidden(true)
                Rectangle().fill(Focus.border).frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.rows) { pull in
                            PullRequestListRow(pull: pull, page: page) {
                                if page == .authored { workspace.openReviews(pull) }
                                else { NSWorkspace.shared.open(pull.url) }
                            }
                        }
                    }
                }.accessibilityIdentifier("pr-list")
            }
        }.frame(maxWidth: .infinity).background(Focus.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Focus.border))
    }
    private var sectionHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.sectionTitle).font(Focus.font(14, weight: .semibold)).fixedSize()
            Text(snapshot.resultsLabel).font(Focus.font(12)).foregroundStyle(Focus.muted)
                .accessibilityIdentifier("list-result-count")
        }
    }
    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Focus.muted)
            TextField("Filter pull requests…", text: $query)
                .textFieldStyle(.plain).font(Focus.font(12)).focused($searchFocused)
                .accessibilityLabel("Filter by title, repository or author").accessibilityIdentifier("pr-filter")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Focus.muted).accessibilityLabel("Clear filter")
            }
        }.padding(10).background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocused ? Focus.accentText : Focus.border, lineWidth: searchFocused ? 2 : 1))
    }
    private var emptyState: some View {
        let missingAccess = !(inbox?.accessIssues.isEmpty ?? true)
        return state(query.isEmpty ? (missingAccess ? "No accessible pull requests in this view" : "You're all caught up") : "No matching pull requests",
                     detail: query.isEmpty ? (missingAccess ? "Some requests may be missing until GitHub access is restored." : "There are no open pull requests in this view.") : "Try a different title, repository or author.",
                     symbol: missingAccess && query.isEmpty ? "lock.shield" : "checkmark.circle")
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "internaldrive")
            if let inbox { Text("Last synced \(inbox.syncedAt.formatted(date: .abbreviated, time: .shortened))") }
            else { Text("Local workspace") }
            Spacer()
            Label("Stored on this Mac", systemImage: "lock")
        }.font(Focus.font(12)).foregroundStyle(Focus.muted)
    }
    private func state(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Focus.accentText)
                .frame(width: 56, height: 56).background(Focus.soft).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title).font(Focus.font(17, weight: .semibold))
            Text(detail).font(Focus.font(13)).foregroundStyle(Focus.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(32).padding(.vertical, 20)
    }
    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle").font(Focus.font(12)).foregroundStyle(Focus.warning)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(Focus.warningSurface).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct PullRequestListRow: View {
    let pull: PullRequest
    let page: PRPage
    let open: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pull.draft ? "doc.text" : "arrow.triangle.pull")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(pull.draft ? Focus.muted : Focus.success)
                    .frame(width: 32, height: 32).background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 8) {
                    Text(pull.title).font(Focus.font(14, weight: .medium)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(pull.repository)  #\(pull.number)  ·  \(pull.author)")
                        .font(Focus.font(12)).foregroundStyle(Focus.muted).multilineTextAlignment(.leading)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { badges }
                        VStack(alignment: .leading, spacing: 6) { badges }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(pull.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(Focus.font(12)).foregroundStyle(Focus.muted)
                    Text(page == .authored ? "View feedback" : "Open on GitHub")
                        .font(Focus.font(12)).foregroundStyle(Focus.accentText)
                }.frame(width: 108, alignment: .trailing)
                Image(systemName: page == .authored ? "chevron.right" : "arrow.up.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Focus.muted).frame(width: 16).padding(.top, 3)
            }.padding(.horizontal, 20).padding(.vertical, 16).contentShape(Rectangle())
                .background(hovered ? Focus.soft.opacity(0.6) : Focus.surface)
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityIdentifier("pr-\(pull.number)").accessibilityLabel(pull.title)
            .accessibilityHint("\(pull.repository), pull request \(pull.number), by \(pull.author). \(page == .authored ? "View received reviews." : "Open on GitHub.")")
        Rectangle().fill(Focus.border).frame(height: 1).padding(.leading, 64)
    }
    @ViewBuilder private var badges: some View {
        if pull.personal { badge("Personal request", color: Focus.accentText, background: Focus.soft) }
        ForEach(pull.teams, id: \.self) { badge("Team · \($0)") }
        if pull.draft { badge("Draft") }
        if let review = pull.reviewState {
            badge(review.replacingOccurrences(of: "_", with: " ").capitalized,
                  color: review == "APPROVED" ? Focus.success : review == "CHANGES_REQUESTED" ? Focus.warning : Focus.muted,
                  background: review == "CHANGES_REQUESTED" ? Focus.warningSurface : Focus.sidebar)
        }
        if pull.changedSinceReview { badge("New commits", color: Focus.accentText, background: Focus.soft) }
        if pull.uncertain { badge("Request timing uncertain", color: Focus.warning, background: Focus.warningSurface) }
        if page == .authored && !pull.draft { badge("Open", color: Focus.success) }
    }
    private func badge(_ title: String, color: Color = Focus.muted, background: Color = Focus.sidebar) -> some View {
        Text(title).font(Focus.font(12)).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
            .background(background).clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
