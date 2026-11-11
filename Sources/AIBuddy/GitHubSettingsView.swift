import SwiftUI
import AppKit
import BuddyCore

struct GitHubSettingsView: View {
    @ObservedObject var workspace: Workspace
    @State private var confirmingRemoval = false
    private var busy: Bool { workspace.starting || workspace.disconnecting || workspace.connecting }
    private var statusColor: Color {
        switch workspace.connectionStatus {
        case .connected: Focus.success
        case .limited, .reconnectRequired, .attentionRequired, .removalIncomplete, .notConfigured: Focus.warning
        default: Focus.muted
        }
    }
    private var problems: [String] {
        var messages: [String] = []
        if let error = workspace.connectionError { messages.append(error) }
        for page in PRPage.allCases {
            if let error = workspace.errors[page] { messages.append("\(page.title): \(error)") }
            for issue in workspace.inboxes[page]?.accessIssues ?? [] {
                if !messages.contains(issue.explanation) { messages.append(issue.explanation) }
            }
        }
        return messages
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings").font(Focus.font(26, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("settings-heading")
                    Text("Connections and access for this Mac.").font(Focus.font(13)).foregroundStyle(Focus.muted)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("GitHub", systemImage: "arrow.triangle.pull").font(Focus.font(20, weight: .semibold))
                        Spacer()
                        Text(workspace.connectionStatus.title).font(Focus.font(12, weight: .medium))
                            .foregroundStyle(statusColor).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel("GitHub connection status")
                            .accessibilityValue(workspace.connectionStatus.title).accessibilityIdentifier("github-status")
                    }
                    Text(workspace.connectionStatus.detail).font(Focus.font(13)).foregroundStyle(Focus.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let user = workspace.user {
                        LabeledContent("Account") {
                            Text("@\(user.login)").textSelection(.enabled).accessibilityIdentifier("github-account")
                        }.font(Focus.font(13))
                    }
                    if let date = workspace.inboxes.values.map(\.syncedAt).max() {
                        LabeledContent("Last successful sync") {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                        }.font(Focus.font(12)).foregroundStyle(Focus.muted)
                    }
                    if workspace.user != nil && !workspace.connecting {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { connectionActions }
                            VStack(alignment: .leading, spacing: 8) { connectionActions }
                        }
                    }
                    Button { NSWorkspace.shared.open(workspace.applicationSettingsURL) } label: {
                        Label("Manage authorization on GitHub", systemImage: "arrow.up.right")
                    }.buttonStyle(FocusButtonStyle()).accessibilityIdentifier("settings-manage-github")
                    if workspace.connectionStatus == .limited {
                        Text("Use GitHub's authorization settings to request organization access. For SSO, sign in to the organization in your browser, then reconnect AI Buddy.")
                            .font(Focus.font(12)).foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(Focus.font(12)).foregroundStyle(Focus.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Focus.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Focus.border))

                if !workspace.removalIncomplete && (workspace.user == nil || workspace.needsReconnection || workspace.connecting) {
                    GitHubConnectionView(workspace: workspace)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Remove local connection").font(Focus.font(15, weight: .semibold))
                    Text("Remove the GitHub token from this Mac's Keychain and delete all cached pull requests. To revoke AI Buddy's authorization on GitHub as well, use Manage authorization on GitHub above.")
                        .font(Focus.font(12)).foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
                    Button(workspace.removalIncomplete ? "Retry removal" : workspace.disconnecting ? "Removing…" : "Remove GitHub connection", role: .destructive) {
                        confirmingRemoval = true
                    }.buttonStyle(FocusButtonStyle())
                        .disabled(!workspace.canRemoveConnection || workspace.starting || workspace.disconnecting)
                        .accessibilityIdentifier("settings-remove-github")
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Focus.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Focus.border))
            }.padding(24)
        }
        .frame(width: 680, height: 640)
        .font(Focus.font(14)).foregroundStyle(Focus.text).background(Focus.background)
        .alert("Remove GitHub connection?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { Task { await workspace.disconnect() } }
        } message: {
            Text("This removes the saved GitHub token and all cached pull requests from this Mac. The authorization on GitHub is managed separately.")
        }
    }
    @ViewBuilder private var connectionActions: some View {
        Button(!workspace.refreshing.isEmpty ? "Checking…" : "Check connection") {
            Task { await workspace.refreshAll() }
        }.buttonStyle(FocusButtonStyle()).accessibilityIdentifier("settings-check-github")
            .disabled(busy || workspace.needsReconnection || !workspace.refreshing.isEmpty)
        if !workspace.needsReconnection {
            Button("Reconnect GitHub") { workspace.reconnect() }
                .buttonStyle(FocusButtonStyle()).accessibilityIdentifier("settings-reconnect-github")
                .disabled(busy || !workspace.configured)
        }
    }
}
