import Foundation

public enum GitHubConnectionStatus: String, Sendable {
    case checking, connecting, removing, removalIncomplete
    case notConfigured, disconnected, reconnectRequired, limited, attentionRequired, connected

    public var title: String {
        switch self {
        case .checking: "Checking connection"
        case .connecting: "Connecting"
        case .removing: "Removing connection"
        case .removalIncomplete: "Removal incomplete"
        case .notConfigured: "Not configured"
        case .disconnected: "Not connected"
        case .reconnectRequired: "Reconnect required"
        case .limited: "Limited access"
        case .attentionRequired: "Needs attention"
        case .connected: "Connected"
        }
    }
    public var detail: String {
        switch self {
        case .checking: "Checking the saved connection and GitHub access."
        case .connecting: "Complete GitHub approval in your browser, or cancel below."
        case .removing: "Removing the saved credential and cached pull requests from this Mac."
        case .removalIncomplete: "Some local connection data could not be removed. Retry removal below."
        case .notConfigured: "This build needs the app developer's GitHub configuration before it can connect."
        case .disconnected: "No GitHub account is connected on this Mac."
        case .reconnectRequired: "Your GitHub authorization is no longer valid. Reconnect to restore access."
        case .limited: "GitHub access is restricted for some repositories, teams or PR pages."
        case .attentionRequired: "The last operation reported a problem. Review the details and try again."
        case .connected: "Your GitHub connection is available."
        }
    }
}
