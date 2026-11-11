import Foundation

public struct DeviceCode: Decodable, Equatable, Sendable {
    public let device_code: String
    public let user_code: String
    public let verification_uri: URL
    public let expires_in: Int
    public let interval: Int
}
public protocol DeviceClock: Sendable {
    func now() async -> Date
    func sleep(seconds: Int) async throws
}
public struct SystemDeviceClock: DeviceClock {
    public init() {}
    public func now() async -> Date { Date() }
    public func sleep(seconds: Int) async throws { try await Task.sleep(for: .seconds(seconds)) }
}
public protocol GitHubAuthorization: Sendable {
    func begin() async throws -> DeviceCode
    func finish(_ code: DeviceCode) async throws -> String
}
public struct DeviceAuthorization: GitHubAuthorization {
    let clientID: String
    let transport: any HTTPTransport
    let clock: any DeviceClock
    public init(clientID: String, transport: any HTTPTransport = URLSessionTransport(),
                clock: any DeviceClock = SystemDeviceClock()) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport; self.clock = clock
    }
    private func post(_ path: String, fields: [String: String]) async throws -> HTTPResponse {
        guard !clientID.isEmpty, !clientID.contains("$(") else { throw BuddyError.configuration }
        var request = URLRequest(url: URL(string: "https://github.com/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)
        let response = try await transport.send(request)
        try checkStatus(response)
        return response
    }
    public func begin() async throws -> DeviceCode {
        let response = try await post("login/device/code", fields: ["client_id": clientID, "scope": "repo read:org"])
        let code = try decode(DeviceCode.self, response.data)
        guard !code.device_code.isEmpty, !code.user_code.isEmpty,
              code.expires_in > 0, code.expires_in <= 3600,
              (1...3600).contains(code.interval),
              code.verification_uri.scheme == "https", code.verification_uri.host == "github.com",
              code.verification_uri.user == nil, code.verification_uri.password == nil,
              code.verification_uri.port == nil else { throw BuddyError.invalidResponse }
        return code
    }
    public func finish(_ code: DeviceCode) async throws -> String {
        let expiresAt = await clock.now().addingTimeInterval(TimeInterval(code.expires_in))
        var interval = max(1, code.interval)
        struct Token: Decodable { let access_token: String?; let error: String? }
        while await clock.now() < expiresAt {
            try Task.checkCancellation()
            try await clock.sleep(seconds: interval)
            guard await clock.now() < expiresAt else { throw BuddyError.expired }
            let response = try await post("login/oauth/access_token", fields: [
                "client_id": clientID, "device_code": code.device_code,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            try Task.checkCancellation()
            let result = try decode(Token.self, response.data)
            switch result.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw BuddyError.denied
            case "expired_token": throw BuddyError.expired
            case .some: throw BuddyError.configuration
            case nil:
                guard let token = result.access_token, !token.isEmpty else { throw BuddyError.invalidResponse }
                return token
            }
        }
        throw BuddyError.expired
    }
}
