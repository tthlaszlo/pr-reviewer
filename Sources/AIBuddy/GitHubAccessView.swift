import SwiftUI
import AppKit
import BuddyCore

/// Used only on pages that require GitHub; navigation and future local tools remain available.
struct GitHubConnectionView: View {
    @ObservedObject var workspace: Workspace
    @State private var copied = false
    private var reconnecting: Bool { workspace.user != nil || workspace.needsReconnection }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: reconnecting ? "arrow.clockwise.circle" : "arrow.triangle.pull")
                .font(.system(size: 30)).foregroundStyle(Focus.accentText)
            VStack(alignment: .leading, spacing: 10) {
                Text(reconnecting ? "Reconnect GitHub to continue" : "Connect GitHub to get started")
                    .font(Focus.font(21, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(reconnecting
                     ? "Your GitHub access has expired, was revoked, or needs to be authorized again. Connect in your browser to restore your pull requests."
                     : "This page needs access to GitHub to show your personal and team review requests and your own open pull requests.")
                    .foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let error = workspace.connectionError { accessNotice(error) }
            if !workspace.configured {
                accessNotice("This build is not configured to connect to GitHub. The app developer needs to configure AI Buddy once; you do not need to create an OAuth app or paste a token.")
            }
            if let code = workspace.deviceCode {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your one-time GitHub code").font(Focus.font(12, weight: .medium))
                    HStack(spacing: 16) {
                        Text(code.user_code).font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled).accessibilityLabel("GitHub device code")
                            .accessibilityValue(code.user_code).accessibilityIdentifier("device-code")
                        Button(copied ? "Copied" : "Copy code") {
                            NSPasteboard.general.clearContents()
                            copied = NSPasteboard.general.setString(code.user_code, forType: .string)
                        }.buttonStyle(FocusButtonStyle()).accessibilityIdentifier("copy-device-code")
                    }
                    HStack {
                        Button { NSWorkspace.shared.open(code.verification_uri) } label: {
                            Label("Open GitHub", systemImage: "arrow.up.right")
                        }.buttonStyle(FocusButtonStyle(primary: true)).accessibilityIdentifier("open-device-github")
                        Button("Cancel") { Task { await workspace.cancelConnection() } }
                            .buttonStyle(FocusButtonStyle()).accessibilityIdentifier("cancel-connection")
                    }
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for GitHub approval…").font(Focus.font(12)).foregroundStyle(Focus.muted)
                    }
                    Text("The code expires after about \(max(1, code.expires_in / 60)) minutes. If it expires, request a new one here.")
                        .font(Focus.font(11)).foregroundStyle(Focus.muted)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Focus.background).clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: code.user_code) { _, _ in copied = false }
            } else {
                HStack(spacing: 12) {
                    Button {
                        if reconnecting { workspace.reconnect() } else { workspace.connect() }
                    } label: {
                        Text(workspace.connecting ? "Requesting code…" : reconnecting ? "Reconnect GitHub" : workspace.connectionError == nil ? "Connect GitHub" : "Try again")
                    }.buttonStyle(FocusButtonStyle(primary: true))
                        .disabled(!workspace.configured || workspace.connecting || workspace.disconnecting)
                        .accessibilityIdentifier("connect-github")
                    if workspace.connecting {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { Task { await workspace.cancelConnection() } }
                            .buttonStyle(FocusButtonStyle()).accessibilityIdentifier("cancel-connection")
                    }
                }
            }
            if workspace.deviceCode == nil {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Get a one-time code", detail: "AI Buddy requests a temporary code from GitHub. No token or password to enter here.")
                step(2, "Approve in your browser", detail: "Copy the code, open GitHub, and approve AI Buddy with the account you want to use.")
                step(3, "Return to your pull requests", detail: "This page updates automatically when GitHub confirms your approval.")
            }
            }
            Text("AI Buddy requests repo and read:org access for private repositories and teams. GitHub's repo scope also permits writes; this version only reads PR data. Your credential is stored in this Mac's Keychain.")
                .font(Focus.font(11)).foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Focus.surface).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Focus.border))
    }
    private func step(_ number: Int, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number)).font(Focus.font(12, weight: .semibold)).foregroundStyle(Focus.accentText)
                .frame(width: 26, height: 26).background(Focus.soft).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Focus.font(13, weight: .medium))
                Text(detail).font(Focus.font(12)).foregroundStyle(Focus.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GitHubPermissionView: View {
    @ObservedObject var workspace: Workspace
    let page: PRPage
    let issues: [GitHubAccessIssue]
    let fullPage: Bool
    @State private var showingHelp = false

    var body: some View {
        Group {
            if fullPage { fullPanel } else { compactPanel }
        }
        .sheet(isPresented: $showingHelp) {
            VStack(alignment: .trailing, spacing: 16) {
                ScrollView {
                    GitHubPermissionView(workspace: workspace, page: page, issues: issues, fullPage: true)
                }
                Button("Done") { showingHelp = false }
                    .buttonStyle(FocusButtonStyle()).keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 640, height: 540).background(Focus.background)
        }
        .onChange(of: workspace.connecting) { _, value in if value { showingHelp = false } }
    }
    private var compactPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Some GitHub access is missing", systemImage: "lock.shield")
                .font(Focus.font(13, weight: .semibold)).foregroundStyle(Focus.accentText)
            Text("This list includes only accessible PRs. Set up organization, repository or team access to see restricted requests.")
                .font(Focus.font(12)).foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Set up access") { showingHelp = true }
                    .buttonStyle(FocusButtonStyle()).accessibilityIdentifier("show-access-help")
                checkAgainButton
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Focus.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Focus.border))
    }
    private var fullPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(fullPage ? "Set up GitHub access" : "Some GitHub access is missing", systemImage: "lock.shield")
                .font(Focus.font(fullPage ? 20 : 15, weight: .semibold)).foregroundStyle(Focus.accentText)
                .accessibilityAddTraits(.isHeader)
            Text(fullPage
                 ? "GitHub could not grant access to this page's data. Check your account and organization permissions, then try again."
                 : "Available pull requests are shown below. Follow these steps to include restricted repositories or team requests.")
                .font(Focus.font(13)).foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(issues, id: \.self) { issue in
                Text(issue.explanation).font(Focus.font(12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Open GitHub access settings and select AI Buddy under Authorized OAuth Apps. Check that you are using the intended GitHub account.")
                Text("2. Request or grant access for the organization you need. An organization owner may need to approve the request; also check that your account can open the repository.")
                Text("3. If your organization uses SSO, sign in to it in the browser first, then reconnect AI Buddy to authorize that organization.")
            }.font(Focus.font(12)).foregroundStyle(Focus.muted).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            HStack(spacing: 16) {
                Link("Organization approval help", destination: GitHubAccessHelp.organizationURL)
                Link("SSO help", destination: GitHubAccessHelp.ssoURL)
            }.font(Focus.font(11))
            if fullPage, let error = workspace.errors[page] { accessNotice(error) }
            if let error = workspace.connectionError { accessNotice(error) }
        }.padding(fullPage ? 24 : 18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Focus.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Focus.border))
    }
    @ViewBuilder private var actions: some View {
        Button { NSWorkspace.shared.open(workspace.applicationSettingsURL) } label: {
            Label("Open GitHub access settings", systemImage: "arrow.up.right")
        }.buttonStyle(FocusButtonStyle(primary: true)).accessibilityIdentifier("open-access-settings")
        checkAgainButton
        Button("Reconnect GitHub") { workspace.reconnect() }
            .buttonStyle(FocusButtonStyle()).disabled(!workspace.configured)
            .accessibilityIdentifier("reauthorize-github")
    }
    private var checkAgainButton: some View {
        Button(workspace.refreshing.contains(page) ? "Checking…" : "Check access again") { workspace.requestRefresh(page) }
            .buttonStyle(FocusButtonStyle()).disabled(workspace.refreshing.contains(page))
            .accessibilityIdentifier("check-github-access")
    }
}

private func accessNotice(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle")
        .font(Focus.font(12)).foregroundStyle(Focus.warning)
        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Focus.warningSurface).clipShape(RoundedRectangle(cornerRadius: 6))
}
