import Foundation
import Testing
@testable import BuddyCore

struct AuthorizationTests {
    @Test func deviceRequestUsesNoSecretAndRequiredScopes() async throws {
        let http = MockHTTP { request, _ in
            #expect(request.url?.absoluteString == "https://github.com/login/device/code")
            #expect(request.httpMethod == "POST")
            let body = String(data: request.httpBody!, encoding: .utf8)!
            #expect(body.contains("scope=repo%20read%3Aorg")); #expect(body.contains("client_id=public-id"))
            #expect(!body.contains("secret"))
            return json(deviceJSON)
        }
        let code = try await DeviceAuthorization(clientID: "public-id", transport: http).begin()
        #expect(code.user_code == "ABCD-EFGH")
    }
    @Test func missingConfigurationDoesNotSend() async {
        let http = MockHTTP { _, _ in Issue.record("Unexpected request"); return json("{}") }
        await #expect(throws: BuddyError.configuration) { try await DeviceAuthorization(clientID: "", transport: http).begin() }
    }
    @Test func pendingSlowDownAndSuccess() async throws {
        let clock = TestClock()
        let http = MockHTTP { request, count in
            #expect(request.url?.path == "/login/oauth/access_token")
            switch count {
            case 1: return json(#"{"error":"authorization_pending"}"#)
            case 2: return json(#"{"error":"slow_down"}"#)
            default: return json(#"{"access_token":"my-token"}"#)
            }
        }
        let auth = DeviceAuthorization(clientID: "id", transport: http, clock: clock)
        let token = try await auth.finish(decode(DeviceCode.self, Data(deviceJSON.utf8)))
        #expect(token == "my-token"); #expect(await clock.waits == [5, 5, 10])
    }
    @Test(arguments: [("access_denied", BuddyError.denied), ("expired_token", .expired), ("incorrect_client_credentials", .configuration)])
    func errors(code: String, expected: BuddyError) async throws {
        let http = MockHTTP { _, _ in json("{\"error\":\"\(code)\"}") }
        let auth = DeviceAuthorization(clientID: "id", transport: http, clock: TestClock())
        let device = try decode(DeviceCode.self, Data(deviceJSON.utf8))
        await #expect(throws: expected) { try await auth.finish(device) }
    }
    @Test func expiryStopsBeforeAnotherPoll() async throws {
        let clock = TestClock()
        let http = MockHTTP { _, _ in Issue.record("Expired code polled"); return json("{}") }
        let device = try decode(DeviceCode.self, Data(deviceJSON.replacingOccurrences(of: "900", with: "5").utf8))
        await #expect(throws: BuddyError.expired) {
            try await DeviceAuthorization(clientID: "id", transport: http, clock: clock).finish(device)
        }
    }
    @Test func cancellationStopsPolling() async throws {
        let device = try decode(DeviceCode.self, Data(deviceJSON.utf8))
        let auth = DeviceAuthorization(clientID: "id", transport: MockHTTP { _, _ in json("{}") })
        let task = Task { try await auth.finish(device) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
    @Test(arguments: ["http://github.com/login/device", "https://evil.example/device", "https://github.com:443/device"])
    func invalidVerificationURL(url: String) async {
        let http = MockHTTP { _, _ in json(deviceJSON.replacingOccurrences(of: "https://github.com/login/device", with: url)) }
        await #expect(throws: BuddyError.invalidResponse) { try await DeviceAuthorization(clientID: "id", transport: http).begin() }
    }
    @Test func malformedTokenResponse() async throws {
        let auth = DeviceAuthorization(clientID: "id", transport: MockHTTP { _, _ in json("{}") }, clock: TestClock())
        let device = try decode(DeviceCode.self, Data(deviceJSON.utf8))
        await #expect(throws: BuddyError.invalidResponse) { try await auth.finish(device) }
    }
}
