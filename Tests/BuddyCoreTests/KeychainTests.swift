import Foundation
import Testing
@testable import BuddyCore

struct KeychainTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AI_BUDDY_TEST_KEYCHAIN"] == "1",
                   "Opt-in OS integration; uses a unique test-only Keychain service."))
    func keychainRoundTripUpdateAndDelete() async throws {
        let store = KeychainCredentialStore(service: "com.aibuddy.tests.\(UUID().uuidString)")
        do {
            #expect(try await store.load() == nil)
            let first = Credential(user: GitHubUser(id: 1, login: "first"), token: "test-only-token")
            try await store.save(first)
            #expect(try await store.load() == first)
            let next = Credential(user: GitHubUser(id: 2, login: "second"), token: "replacement")
            try await store.save(next)
            #expect(try await store.load() == next)
            try await store.delete()
            #expect(try await store.load() == nil)
            try await store.delete()
        } catch {
            try? await store.delete()
            throw error
        }
    }
}
