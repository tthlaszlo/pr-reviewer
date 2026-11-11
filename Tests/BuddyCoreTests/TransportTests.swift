import Foundation
import Testing
@testable import BuddyCore

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.path == "/offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response: URLResponse = url.path == "/invalid" ?
            URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil) :
            HTTPURLResponse(url: url, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "20"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("body".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
struct TransportTests {
    private func transport() -> URLSessionTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(configuration: config)
    }
    @Test func preservesStatusBodyAndNormalizedHeaders() async throws {
        let response = try await transport().send(URLRequest(url: URL(string: "https://example.test/response")!))
        #expect(response.status == 403)
        #expect(response.data == Data("body".utf8))
        #expect(response.headers["retry-after"] == "20")
    }
    @Test func networkErrorsBecomeSafeMessages() async {
        await #expect(throws: BuddyError.unavailable) {
            try await transport().send(URLRequest(url: URL(string: "https://example.test/offline")!))
        }
    }
    @Test func invalidResponseIsRejected() async {
        await #expect(throws: BuddyError.invalidResponse) {
            try await transport().send(URLRequest(url: URL(string: "https://example.test/invalid")!))
        }
    }
    @Test func cancelledTransportDoesNotBecomeNetworkError() async {
        let transport = transport()
        let task = Task { try await transport.send(URLRequest(url: URL(string: "https://example.test/response")!)) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
}
