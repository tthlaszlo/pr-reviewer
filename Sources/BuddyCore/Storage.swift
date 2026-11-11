import Foundation
import CSQLite
import Security

public protocol InboxStoring: Sendable {
    func load(accountID: Int64, page: PRPage) async throws -> Inbox?
    func save(_ inbox: Inbox, accountID: Int64, page: PRPage) async throws
    func clear() async throws
}
private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer
    init(path: String) throws {
        if path != ":memory:" {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw BuddyError.storage
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, 5000)
        guard sqlite3_exec(handle, "CREATE TABLE IF NOT EXISTS inbox (account INTEGER NOT NULL, page TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(account,page));", nil, nil, nil) == SQLITE_OK else {
            throw BuddyError.storage
        }
        if path != ":memory:" { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
    }
    deinit { sqlite3_close(handle) }
}
public actor SQLiteInboxStore: InboxStoring {
    private let path: String
    private var connection: SQLiteConnection?
    public init(path: String) { self.path = path }
    public static var applicationPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI Buddy/inbox.sqlite").path
    }
    private func database() throws -> OpaquePointer {
        if connection == nil { connection = try SQLiteConnection(path: path) }
        return connection!.handle
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(try database(), sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw BuddyError.storage }
        return stmt
    }
    private func bind(_ accountID: Int64, _ page: PRPage, to stmt: OpaquePointer) throws {
        guard sqlite3_bind_int64(stmt, 1, accountID) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, page.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw BuddyError.storage }
    }
    public func load(accountID: Int64, page: PRPage) throws -> Inbox? {
        let stmt = try statement("SELECT payload FROM inbox WHERE account=? AND page=?")
        defer { sqlite3_finalize(stmt) }
        try bind(accountID, page, to: stmt)
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw BuddyError.storage }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        do { return try JSONDecoder().decode(Inbox.self, from: data) }
        catch { throw BuddyError.storage }
    }
    public func save(_ inbox: Inbox, accountID: Int64, page: PRPage) throws {
        let stmt = try statement("INSERT INTO inbox(account,page,payload) VALUES(?,?,?) ON CONFLICT(account,page) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        try bind(accountID, page, to: stmt)
        let data = try JSONEncoder().encode(inbox)
        let status = data.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard status == SQLITE_OK, sqlite3_step(stmt) == SQLITE_DONE else { throw BuddyError.storage }
    }
    public func clear() throws {
        guard sqlite3_exec(try database(), "DELETE FROM inbox; VACUUM;", nil, nil, nil) == SQLITE_OK else { throw BuddyError.storage }
    }
}

public struct Credential: Codable, Equatable, Sendable {
    public let user: GitHubUser
    public let token: String
    public init(user: GitHubUser, token: String) { self.user = user; self.token = token }
}
public protocol CredentialStoring: Sendable {
    func load() async throws -> Credential?
    func save(_ credential: Credential) async throws
    func delete() async throws
}
public actor KeychainCredentialStore: CredentialStoring {
    private let service: String
    public init(service: String = "com.aibuddy.desktop.github") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "github.com"]
    }
    public func load() throws -> Credential? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw BuddyError.keychain(status) }
        do { return try JSONDecoder().decode(Credential.self, from: data) }
        catch { throw BuddyError.keychain(errSecDecode) }
    }
    public func save(_ credential: Credential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes = [kSecValueData as String: data,
                          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insertion = query.merging(attributes) { _, new in new }
            let result = SecItemAdd(insertion as CFDictionary, nil)
            guard result == errSecSuccess else { throw BuddyError.keychain(result) }
        } else if status != errSecSuccess { throw BuddyError.keychain(status) }
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BuddyError.keychain(status) }
    }
}
