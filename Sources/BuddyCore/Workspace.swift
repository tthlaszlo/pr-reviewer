import Foundation
import Combine

@MainActor
public final class Workspace: ObservableObject {
    @Published public private(set) var user: GitHubUser?
    @Published public private(set) var inboxes: [PRPage: Inbox] = [:]
    @Published public private(set) var refreshing: Set<PRPage> = []
    @Published public private(set) var errors: [PRPage: String] = [:]
    @Published public private(set) var stale: Set<PRPage> = []
    @Published public private(set) var connectionError: String?
    @Published public private(set) var deviceCode: DeviceCode?
    @Published public private(set) var connecting = false
    @Published public private(set) var needsReconnection = false
    @Published public private(set) var restrictedPages: Set<PRPage> = []
    @Published public private(set) var starting = true
    @Published public private(set) var disconnecting = false
    public let configured: Bool
    public let applicationSettingsURL: URL
    private let github: any GitHubServing
    private let authorization: any GitHubAuthorization
    private let credentials: any CredentialStoring
    private let cache: any InboxStoring
    private var credential: Credential?
    private var generation = 0
    private var started = false
    private var connectionTask: Task<Void, Never>?
    private var refreshTasks: [PRPage: Task<Void, Never>] = [:]

    public init(configured: Bool, github: any GitHubServing, authorization: any GitHubAuthorization,
                credentials: any CredentialStoring, cache: any InboxStoring,
                applicationSettingsURL: URL = GitHubAccessHelp.applicationsURL) {
        self.configured = configured; self.github = github; self.authorization = authorization
        self.credentials = credentials; self.cache = cache
        self.applicationSettingsURL = applicationSettingsURL
    }
    public func start() async {
        guard !started else { return }
        started = true
        let version = generation
        defer { starting = false }
        do {
            let saved = try await credentials.load()
            guard version == generation else { return }
            guard let saved else { return }
            credential = saved; user = saved.user
            for page in PRPage.allCases {
                do {
                    let inbox = try await cache.load(accountID: saved.user.id, page: page)
                    guard version == generation else { return }
                    if let inbox { inboxes[page] = inbox; stale.insert(page) }
                } catch {
                    guard version == generation else { return }
                    errors[page] = message(error)
                }
            }
            guard version == generation else { return }
            starting = false
            await refreshAll()
        } catch { if version == generation { connectionError = message(error) } }
    }
    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for page in PRPage.allCases { group.addTask { await self.refresh(page) } }
        }
    }
    public func requestRefresh(_ page: PRPage) {
        guard refreshTasks[page] == nil else { return }
        let version = generation
        refreshTasks[page] = Task { [weak self] in
            await self?.refresh(page)
            if self?.generation == version { self?.refreshTasks[page] = nil }
        }
    }
    public func refresh(_ page: PRPage) async {
        guard let credential, !refreshing.contains(page), !disconnecting, !connecting, !needsReconnection else { return }
        let version = generation
        refreshing.insert(page)
        defer { if version == generation { refreshing.remove(page) } }
        do {
            // Verify stable identity before reading or displaying cached-account data.
            let current = try await github.user(token: credential.token)
            guard version == generation, !Task.isCancelled else { return }
            guard current.id == credential.user.id else { throw BuddyError.unauthorized }
            let inbox = try await github.inbox(token: credential.token, login: current.login, page: page)
            guard version == generation, !Task.isCancelled else { return }
            inboxes[page] = inbox; stale.remove(page); errors[page] = nil
            restrictedPages.remove(page)
            do { try await cache.save(inbox, accountID: current.id, page: page) }
            catch { if version == generation { errors[page] = message(error) } }
        } catch is CancellationError { }
        catch {
            guard version == generation else { return }
            if error as? BuddyError == .unauthorized {
                // A revoked token affects all GitHub pages. Invalidate outstanding responses,
                // but retain the old credential/cache until replacement succeeds or disconnect.
                generation += 1
                stopRefreshes()
                needsReconnection = true
                for destination in PRPage.allCases {
                    errors[destination] = message(error)
                    if inboxes[destination] != nil { stale.insert(destination) }
                }
            } else {
                errors[page] = message(error)
                if error as? BuddyError == .permissions { restrictedPages.insert(page) }
                if inboxes[page] != nil { stale.insert(page) }
            }
        }
    }
    private func stopRefreshes() {
        for task in refreshTasks.values { task.cancel() }
        refreshTasks = [:]
        refreshing = []
    }
    public func connect() {
        guard user == nil || needsReconnection else { return }
        beginConnection()
    }
    public func reconnect() {
        beginConnection()
    }
    private func beginConnection() {
        guard !starting, !connecting, !disconnecting else { return }
        guard configured else { connectionError = BuddyError.configuration.localizedDescription; return }
        connectionError = nil; connecting = true
        generation += 1
        stopRefreshes()
        let version = generation
        connectionTask = Task { [weak self] in await self?.authorize(version: version) }
    }
    private func authorize(version: Int) async {
        let previousCredential = credential
        defer { if version == generation { connecting = false; deviceCode = nil } }
        do {
            let code = try await authorization.begin()
            guard version == generation, !Task.isCancelled else { return }
            deviceCode = code
            let token = try await authorization.finish(code)
            let current = try await github.user(token: token)
            guard version == generation, !Task.isCancelled else { return }
            try await cache.clear()
            guard version == generation, !Task.isCancelled else { return }
            let saved = Credential(user: current, token: token)
            // Cancelling waits for this task before allowing another connection, so an in-flight
            // Keychain save can be cleaned up without deleting a newer account's credential.
            try await credentials.save(saved)
            guard version == generation, !Task.isCancelled else {
                if let previousCredential { try await credentials.save(previousCredential) }
                else { try await credentials.delete() }
                return
            }
            credential = saved; user = current; inboxes = [:]; errors = [:]; stale = []
            needsReconnection = false; restrictedPages = []
            connecting = false; deviceCode = nil
            await refreshAll()
        } catch is CancellationError { }
        catch { if version == generation { connectionError = message(error) } }
    }
    public func cancelConnection() async {
        guard connecting else { return }
        generation += 1
        connectionTask?.cancel()
        await connectionTask?.value
        connectionTask = nil; connecting = false; deviceCode = nil
    }
    public func disconnect() async {
        guard !disconnecting else { return }
        disconnecting = true
        generation += 1
        connectionTask?.cancel()
        stopRefreshes()
        await connectionTask?.value
        credential = nil; user = nil; inboxes = [:]; errors = [:]; stale = []; refreshing = []
        deviceCode = nil; connecting = false; connectionError = nil
        needsReconnection = false; restrictedPages = []
        do { try await credentials.delete() } catch { connectionError = message(error) }
        do { try await cache.clear() } catch { connectionError = message(error) }
        disconnecting = false
    }
    func waitForConnection() async { await connectionTask?.value }
    private func message(_ error: Error) -> String {
        (error as? BuddyError)?.localizedDescription ?? BuddyError.unavailable.localizedDescription
    }
}
