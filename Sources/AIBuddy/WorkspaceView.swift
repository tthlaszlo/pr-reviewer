import SwiftUI
import AppKit
import BuddyCore

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    @State private var page: PRPage = .reviews
    @State private var group: ReviewGroup = .awaiting
    @State private var query = ""
    @State private var confirmDisconnect = false
    @State private var showingSettings = false
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
        .focusedSceneValue(\.showBuddySettings, { showingSettings = true })
        .alert("Disconnect GitHub?", isPresented: $confirmDisconnect) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) { Task { await workspace.disconnect() } }
        } message: { Text("This removes the GitHub token and cached pull requests from this Mac. It does not revoke the app on GitHub.") }
        .onChange(of: page) { _, _ in query = ""; workspace.closeReviews() }
        .onChange(of: showingSettings) { _, _ in workspace.closeReviews() }
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
                Button { workspace.closeReviews(); page = destination; showingSettings = false } label: {
                    Text(destination.title).font(Focus.font(12, weight: page == destination && !showingSettings ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 10)
                        .foregroundStyle(page == destination && !showingSettings ? Focus.accentText : Focus.muted)
                        .background(page == destination && !showingSettings ? Focus.soft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nav-\(destination.rawValue)")
                .accessibilityAddTraits(page == destination && !showingSettings ? [.isSelected] : [])
            }
            Spacer()
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(Focus.font(12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .foregroundStyle(showingSettings ? Focus.accentText : Focus.muted)
                    .background(showingSettings ? Focus.soft : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).accessibilityIdentifier("nav-settings")
                .accessibilityAddTraits(showingSettings ? [.isSelected] : [])
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
    @ViewBuilder private var content: some View {
        if showingSettings { GitHubSettingsView(workspace: workspace) }
        else if let pull = workspace.selectedPull { PullReviewsView(workspace: workspace, pull: pull) }
        else { pullRequestsContent }
    }
    private var pullRequestsContent: some View {
        PullRequestListView(workspace: workspace, page: page, group: $group, query: $query)
    }
}
