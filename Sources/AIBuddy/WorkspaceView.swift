import SwiftUI
import AppKit
import BuddyCore

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    @State private var page: PRPage = .reviews
    @State private var group: ReviewGroup = .awaiting
    @State private var query = ""
    @State private var confirmDisconnect = false
    @FocusState private var searchFocused: Bool
    private var inbox: Inbox? { workspace.inboxes[page] }
    private var rows: [PullRequest] {
        (inbox?.pulls ?? []).filter { (page == .authored || $0.group == group) && $0.matches(query) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Focus.border).frame(width: 1)
            content
        }
        .font(Focus.font(14)).foregroundStyle(Focus.text)
        .background(Focus.background)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .navigationTitle("AI Buddy")
        .alert("Disconnect GitHub?", isPresented: $confirmDisconnect) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) { Task { await workspace.disconnect() } }
        } message: { Text("This removes the GitHub token and cached pull requests from this Mac. It does not revoke the app on GitHub.") }
        .onChange(of: page) { _, _ in query = "" }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Focus.accentText)
                Text("AI Buddy").font(Focus.font(19, weight: .semibold))
            }.padding(.bottom, 8)
            Text("DEVELOPER TOOLS").font(Focus.font(10, weight: .semibold)).tracking(1.5).foregroundStyle(Focus.muted)
            Rectangle().fill(Focus.border).frame(height: 1).padding(.vertical, 24)
            Label("Pull requests", systemImage: "arrow.triangle.pull").font(Focus.font(13, weight: .semibold))
                .padding(.bottom, 12)
            ForEach(PRPage.allCases, id: \.self) { destination in
                Button { page = destination } label: {
                    Text(destination.title).font(Focus.font(12, weight: page == destination ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 10)
                        .foregroundStyle(page == destination ? Focus.accentText : Focus.muted)
                        .background(page == destination ? Focus.soft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nav-\(destination.rawValue)")
                .accessibilityAddTraits(page == destination ? [.isSelected] : [])
            }
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(Focus.font(12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            }.buttonStyle(.plain).accessibilityIdentifier("nav-settings")
            Rectangle().fill(Focus.border).frame(height: 1).padding(.vertical, 16)
            if let user = workspace.user {
                Label(user.login, systemImage: "person.crop.circle").font(Focus.font(12, weight: .medium))
                Text(workspace.needsReconnection ? "Reconnect required" : "Connected to GitHub").font(Focus.font(11)).foregroundStyle(Focus.muted).padding(.top, 5)
                Button("Disconnect GitHub") { confirmDisconnect = true }
                    .font(Focus.font(11)).foregroundStyle(Focus.accentText).buttonStyle(.plain).padding(.top, 10)
                    .disabled(workspace.disconnecting)
                    .accessibilityIdentifier("disconnect")
            } else {
                Label("Local workspace", systemImage: "desktopcomputer").font(Focus.font(12))
                Text("Your data stays on this Mac.").font(Focus.font(11)).foregroundStyle(Focus.muted).padding(.top, 6)
            }
        }
        .padding(20).frame(width: 216).background(Focus.sidebar)
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pull requests / \(page.title)").font(Focus.font(12)).foregroundStyle(Focus.muted).padding(.bottom, 18)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(page.title).font(Focus.font(26, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(page == .reviews ? "Your review queue, in one place." : "Keep track of the pull requests you have opened.")
                        .font(Focus.font(13)).foregroundStyle(Focus.muted)
                }
                Spacer(minLength: 12)
                if workspace.user != nil && !workspace.needsReconnection && !workspace.connecting && !workspace.restrictedPages.contains(page) {
                    Button { workspace.requestRefresh(page) } label: {
                        Label(workspace.refreshing.contains(page) ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                    }.buttonStyle(FocusButtonStyle()).disabled(workspace.refreshing.contains(page))
                        .accessibilityIdentifier("refresh")
                }
            }.padding(.bottom, 26)
            if workspace.starting && workspace.user == nil {
                statePanel("Opening your workspace", detail: "Checking the GitHub connection stored on this Mac.", symbol: "hourglass")
            } else if workspace.user == nil || workspace.needsReconnection || workspace.connecting {
                ScrollView { GitHubConnectionView(workspace: workspace) }
            } else if workspace.restrictedPages.contains(page) {
                ScrollView {
                    GitHubPermissionView(workspace: workspace, page: page, issues: [], fullPage: true)
                }
            } else {
                connectedContent
            }
            Spacer(minLength: 0)
            footer
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    @ViewBuilder private var connectedContent: some View {
        if page == .reviews {
            HStack(spacing: 20) {
                ForEach(ReviewGroup.allCases, id: \.self) { tab in
                    Button { group = tab } label: {
                        VStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Text(tab.title)
                                Text(inbox.map { String($0.pulls.filter { $0.group == tab }.count) } ?? "—")
                                    .monospacedDigit().padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(group == tab ? Focus.soft : Focus.sidebar).clipShape(RoundedRectangle(cornerRadius: 4))
                            }.font(Focus.font(11, weight: group == tab ? .semibold : .regular))
                            Rectangle().fill(group == tab ? Focus.accent : .clear).frame(height: 2)
                        }.foregroundStyle(group == tab ? Focus.accentText : Focus.muted)
                    }.buttonStyle(.plain).accessibilityIdentifier("group-\(tab.rawValue)")
                        .accessibilityAddTraits(group == tab ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Focus.border).frame(height: 1)
        }
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Focus.muted)
            TextField("Filter by title, repository or author", text: $query)
                .textFieldStyle(.plain).font(Focus.font(13)).focused($searchFocused)
                .accessibilityIdentifier("pr-filter")
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear filter") }
        }.padding(10).background(Focus.surface).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Focus.border)).padding(.vertical, 18)
        if let error = workspace.connectionError { banner(error, warning: true).padding(.bottom, 12) }
        if let error = workspace.errors[page] { banner(error, warning: true).padding(.bottom, 12) }
        if let inbox, !inbox.accessIssues.isEmpty {
            GitHubPermissionView(workspace: workspace, page: page, issues: inbox.accessIssues, fullPage: false)
                .padding(.bottom, 16)
        }
        if workspace.stale.contains(page) {
            banner("Showing saved data. This list may be out of date.", warning: true).padding(.bottom, 12)
        }
        ForEach(inbox?.warnings ?? [], id: \.self) { warning in banner(warning, warning: true).padding(.bottom, 8) }
        if inbox == nil && workspace.refreshing.contains(page) {
            statePanel("Loading pull requests", detail: "Reading your repositories and review history from GitHub.", symbol: "hourglass")
        } else if inbox == nil {
            statePanel("Pull requests could not be loaded", detail: "Use Refresh to try again.", symbol: "exclamationmark.triangle")
        } else if rows.isEmpty {
            let missingAccess = !(inbox?.accessIssues.isEmpty ?? true)
            statePanel(query.isEmpty ? (missingAccess ? "No accessible pull requests in this view" : "You're all caught up") : "No matching pull requests",
                       detail: query.isEmpty ? (missingAccess ? "Some requests may be missing until GitHub access is restored." : "There are no open pull requests in this view.") : "Try a different title, repository or author.",
                       symbol: missingAccess && query.isEmpty ? "lock.shield" : "checkmark.circle")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { pull in PRRow(pull: pull) }
                }
            }.accessibilityIdentifier("pr-list")
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Focus.border).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                if let inbox {
                    Text("Last synced \(inbox.syncedAt.formatted(date: .abbreviated, time: .shortened))")
                } else { Text("Local workspace") }
                Spacer()
                Text("AI Buddy · macOS")
            }.font(Focus.font(11)).foregroundStyle(Focus.muted)
        }.padding(.top, 16)
    }
    private func statePanel(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Focus.accentText)
            Text(title).font(Focus.font(17, weight: .semibold))
            Text(detail).font(Focus.font(13)).foregroundStyle(Focus.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 56)
    }
    private func banner(_ message: String, warning: Bool) -> some View {
        Label(message, systemImage: warning ? "exclamationmark.triangle" : "info.circle")
            .font(Focus.font(12)).foregroundStyle(Focus.warning)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(Focus.warningSurface).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct PRRow: View {
    let pull: PullRequest
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pull.draft ? "doc.text" : "arrow.triangle.pull")
                    .font(.system(size: 16)).foregroundStyle(pull.draft ? Focus.muted : Focus.success).padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Button { NSWorkspace.shared.open(pull.url) } label: {
                        Text(pull.title).font(Focus.font(14, weight: .medium)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.plain).accessibilityIdentifier("pr-\(pull.number)")
                    Text("\(pull.repository)  #\(pull.number)  ·  \(pull.author)")
                        .font(Focus.font(12)).foregroundStyle(Focus.muted).textSelection(.enabled)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { badges }
                        VStack(alignment: .leading, spacing: 6) { badges }
                    }
                }
                Spacer(minLength: 8)
                Text(pull.updatedAt, style: .relative).font(Focus.font(11)).foregroundStyle(Focus.muted)
                    .frame(width: 80, alignment: .trailing).accessibilityLabel("Last updated \(pull.updatedAt.formatted())")
            }.padding(.vertical, 18)
            Rectangle().fill(Focus.border).frame(height: 1)
        }
    }
    @ViewBuilder private var badges: some View {
        if pull.personal { badge("Personal request") }
        ForEach(pull.teams, id: \.self) { badge("Team · \($0)") }
        if pull.draft { badge("Draft") }
        if let review = pull.reviewState { badge(review.replacingOccurrences(of: "_", with: " ").capitalized) }
        if pull.changedSinceReview { badge("New commits") }
        if pull.uncertain { badge("Request timing uncertain") }
    }
    private func badge(_ text: String) -> some View {
        Text(text).font(Focus.font(11)).foregroundStyle(Focus.muted)
            .padding(.horizontal, 6).padding(.vertical, 3).background(Focus.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
