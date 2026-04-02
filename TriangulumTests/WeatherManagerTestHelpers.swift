import Foundation
@testable import Triangulum

final class MockWeatherURLProtocol: URLProtocol {
    private static let tokenHeader = "X-Mock-Weather-Token"
    private static let queue = DispatchQueue(label: "MockWeatherURLProtocol")
    private static var responseProviders: [String: (URLRequest) throws -> (URLResponse, Data?)] = [:]

    static func register(token: String, responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)) {
        queue.sync {
            responseProviders[token] = responseProvider
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

enum WeatherTestHelper {
    static func createMockSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> URLSession {
        let token = UUID().uuidString
        MockWeatherURLProtocol.register(token: token, responseProvider: responseProvider)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWeatherURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["X-Mock-Weather-Token": token]
        return URLSession(configuration: configuration)
    }

    static func createValidLocationManager() -> LocationManager {
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        locationManager.isAvailable = true
        locationManager.authorizationStatus = .authorizedWhenInUse
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194
        return locationManager
    }

    static func createSampleWeather() throws -> Weather {
        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        return Weather(from: response)
    }
}
