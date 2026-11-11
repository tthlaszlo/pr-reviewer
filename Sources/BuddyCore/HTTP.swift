import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let headers: [String: String]
    public init(data: Data, status: Int = 200, headers: [String: String] = [:]) {
        self.data = data; self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
    }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public final class URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession
    public convenience init() { self.init(configuration: .ephemeral) }
    init(configuration config: URLSessionConfiguration) {
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw BuddyError.invalidResponse }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
            }
            return HTTPResponse(data: data, status: http.statusCode, headers: headers)
        } catch is CancellationError { throw CancellationError() }
        catch let error as BuddyError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw BuddyError.unavailable
        }
    }
}
func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { value in
        let string = try value.singleValueContainer().decode(String.self)
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        guard let date = iso.date(from: string) else { throw BuddyError.invalidResponse }
        return date
    }
    return decoder
}
func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try decoder().decode(type, from: data) }
    catch { throw BuddyError.invalidResponse }
}
func checkStatus(_ response: HTTPResponse) throws {
    guard (200..<300).contains(response.status) else {
        if response.status == 429 || (response.status == 403 &&
            (response.headers["x-ratelimit-remaining"] == "0" || response.headers["retry-after"] != nil)) {
            throw BuddyError.rateLimited
        }
        switch response.status {
        case 401: throw BuddyError.unauthorized
        case 403, 404: throw BuddyError.permissions
        default: throw BuddyError.unavailable
        }
    }
}
