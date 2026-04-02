import Testing
import Foundation
import MapKit
@testable import Triangulum

private final class MockOSMURLProtocol: URLProtocol {
    private static let tokenHeader = "X-Mock-OSM-Token"
    private static let queue = DispatchQueue(label: "MockOSMURLProtocol")
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

@Suite(.serialized)
struct OSMGeocoderTests {

    private func createMockSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> (session: URLSession, cleanup: () -> Void) {
        let token = UUID().uuidString
        MockOSMURLProtocol.register(token: token, responseProvider: responseProvider)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOSMURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["X-Mock-OSM-Token": token]
        let session = URLSession(configuration: configuration)
        let cleanup = { MockOSMURLProtocol.unregister(token: token) }
        return (session, cleanup)
    }

    @Test func testSearchBuildsRegionQueryAndDecodesResults() async throws {
        let (session, cleanup) = createMockSession { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let viewbox = try #require(items["viewbox"])
                .split(separator: ",")
                .compactMap { Double($0) }

            #expect(items["format"] == "jsonv2")
            #expect(items["q"] == "coffee")
            #expect(items["limit"] == "3")
            #expect(items["bounded"] == "1")
            #expect(viewbox.count == 4)
            #expect(abs((viewbox.first ?? 0) - (-122.52)) < 0.0001)
            #expect(abs((viewbox.dropFirst().first ?? 0) - 37.85) < 0.0001)
            #expect(abs((viewbox.dropFirst(2).first ?? 0) - (-122.32)) < 0.0001)
            #expect(abs((viewbox.last ?? 0) - 37.75) < 0.0001)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("Triangulum/1.0") == true)

            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            let data = Data("""
            [
              {"display_name":"Coffee Shop","lat":"37.7800","lon":"-122.4100"}
            ]
            """.utf8)
            return (response, data)
        }
        defer { cleanup() }

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.42),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )

        let results = try await OSMGeocoder.search(
            query: "coffee",
            limit: 3,
            region: region,
            bounded: true,
            session: session
        )

        #expect(results.count == 1)
        #expect(results.first?.displayName == "Coffee Shop")
        #expect(results.first?.coordinate.latitude == 37.78)
        #expect(results.first?.coordinate.longitude == -122.41)
    }

    @Test func testSearchReturnsEmptyArrayForHTTPError() async throws {
        let (session, cleanup) = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
            return (response, Data("service unavailable".utf8))
        }
        defer { cleanup() }

        let results = try await OSMGeocoder.search(query: "museum", session: session)

        #expect(results.isEmpty)
    }

    @Test func testSearchReturnsEmptyArrayForDecodingFailure() async throws {
        let (session, cleanup) = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("not-json".utf8))
        }
        defer { cleanup() }

        let results = try await OSMGeocoder.search(query: "library", session: session)

        #expect(results.isEmpty)
    }

    @Test func testResultCoordinateFallsBackToZeroForInvalidStrings() {
        let result = OSMGeocoder.Result(displayName: "Invalid", lat: "north", lon: "west")

        #expect(result.coordinate.latitude == 0)
        #expect(result.coordinate.longitude == 0)
    }
}
