import SwiftUI
import BuddyCore

@main
struct AIBuddyApp: App {
    @StateObject private var workspace: Workspace
    init() {
        Focus.registerFonts()
        let id = (Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["AI_BUDDY_UI_TEST"] {
            _workspace = StateObject(wrappedValue: UITestFixtures.workspace(scenario: fixture))
            return
        }
        #endif
        _workspace = StateObject(wrappedValue: Workspace(
            configured: !id.isEmpty && !id.contains("$("), github: GitHubClient(),
            authorization: DeviceAuthorization(clientID: id), credentials: KeychainCredentialStore(),
            cache: SQLiteInboxStore(path: SQLiteInboxStore.applicationPath)))
    }
    var body: some Scene {
        WindowGroup {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 860, minHeight: 560)
                .preferredColorScheme(.light)
                .tint(Focus.accentText)
                .task { await workspace.start() }
        }
        .defaultSize(width: 1140, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh pull requests") { Task { await workspace.refreshAll() } }
                    .keyboardShortcut("r")
                    .disabled(workspace.user == nil)
            }
        }
    }
}
