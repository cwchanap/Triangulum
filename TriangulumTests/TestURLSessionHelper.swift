import Foundation

/// Token-isolated stub `URLProtocol` shared by all suite tests that need a
/// mocked `URLSession`. Each mock session carries a unique token header, so
/// concurrently registered sessions never see each other's responses.
final class TestURLProtocol: URLProtocol {
    static let tokenHeader = "X-Test-URLProtocol-Token"
    private static let queue = DispatchQueue(label: "TestURLProtocol")
    private static var responseProviders: [String: (URLRequest) throws -> (URLResponse, Data?)] = [:]

    static func register(token: String, responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)) {
        queue.sync {
            responseProviders[token] = responseProvider
        }
    }

    static func unregister(token: String) {
        queue.sync {
            responseProviders.removeValue(forKey: token)
        }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: Self.tokenHeader) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let responseProvider = Self.queue.sync {
            Self.responseProviders[token]
        }

        guard let responseProvider else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try responseProvider(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Builds token-isolated mock `URLSession` instances backed by
/// `TestURLProtocol`. The returned `cleanup` must be called when the session
/// is no longer needed (typically in a `defer`) so the token's response
/// provider does not leak into other tests.
enum TestURLSessionHelper {
    static func makeSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> (session: URLSession, cleanup: () -> Void) {
        let token = UUID().uuidString
        TestURLProtocol.register(token: token, responseProvider: responseProvider)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [TestURLProtocol.tokenHeader: token]
        let session = URLSession(configuration: configuration)
        let cleanup = { TestURLProtocol.unregister(token: token) }
        return (session, cleanup)
    }

    /// Convenience for response providers: a JSON/CSV/text `HTTPURLResponse`.
    static func httpResponse(url: URL, statusCode: Int = 200, data: Data? = nil) -> (URLResponse, Data?) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        return (response!, data)
    }
}

/// Thread-safe request URL recorder: `URLProtocol` callbacks arrive on the
/// session's internal queue, so tests capture requested URLs here instead of
/// mutating a captured array.
final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [URL] = []

    func record(_ url: URL) {
        lock.lock()
        requested.append(url)
        defer { lock.unlock() }
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }
}
