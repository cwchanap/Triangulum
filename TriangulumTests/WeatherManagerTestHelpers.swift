import Foundation
@testable import Triangulum

enum WeatherTestHelper {
    static func createMockSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> (session: URLSession, cleanup: () -> Void) {
        TestURLSessionHelper.makeSession(responseProvider: responseProvider)
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
