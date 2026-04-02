import Testing
import Foundation
@testable import Triangulum

@Suite(.serialized)
struct WeatherManagerFetchTests {

    @Test @MainActor func testFetchWeatherParsesSuccessfulResponse() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_success")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0,
                     "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "wind": {"speed": 3.5, "deg": 180},
            "visibility": 10000,
            "name": "San Francisco"
        }
        """.utf8)
        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, json)
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.currentWeather?.condition == "Clear")
        #expect(weatherManager.currentWeather?.locationName == "San Francisco")
        #expect(weatherManager.errorMessage == "")
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesUnauthorizedResponse() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_unauthorized")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (response, Data("unauthorized".utf8))
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )
        weatherManager.isMonitoringEnabled = true
        weatherManager.weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in }

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage.contains("HTTP 401"))
        #expect(weatherManager.weatherCheckTimer == nil)
        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesGenericHTTPError() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_http_error")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))
            return (response, Data("server exploded".utf8))
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "API Error: HTTP 500")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesNonHTTPResponse() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_non_http")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
            return (response, Data("{}".utf8))
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "Unexpected server response")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesDecodingFailure() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_decode_failure")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("not-json".utf8))
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "Failed to parse weather data")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesTransportFailure() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_transport_failure")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let (session, cleanup) = WeatherTestHelper.createMockSession { _ in
            throw URLError(.timedOut)
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage.hasPrefix("Network error:"))
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherReturnsEarlyWhenAlreadyLoading() async {
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true
        )
        weatherManager.isLoading = true

        await weatherManager.fetchWeather()

        #expect(weatherManager.isLoading == true)
        #expect(weatherManager.errorMessage == "")
        #expect(weatherManager.currentWeather == nil)
    }

    @Test @MainActor func testFetchWeatherRequiresAPIKey() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        _ = Config.deleteAPIKey()
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "API key required")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherRequiresLocationData() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_missing_location")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let locationManager = WeatherTestHelper.createValidLocationManager()
        locationManager.latitude = 0
        locationManager.longitude = 0
        let weatherManager = WeatherManager(
            locationManager: locationManager,
            skipMonitoring: true
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "No location data available")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testRefreshWeatherSkipsWhenAlreadyLoading() async {
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true
        )
        weatherManager.isLoading = true

        weatherManager.refreshWeather()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(weatherManager.isLoading == true)
        #expect(weatherManager.errorMessage == "")
        #expect(weatherManager.currentWeather == nil)
    }

    @Test @MainActor func testRefreshWeatherStartsFetchTask() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_refresh_weather")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, json)
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        weatherManager.refreshWeather()
        for _ in 0..<50 where weatherManager.currentWeather == nil && weatherManager.errorMessage.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(weatherManager.currentWeather?.locationName == "San Francisco")
        #expect(weatherManager.errorMessage == "")
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testRefreshAvailabilityReportsLocationServicesRequiredWhenUnavailable() throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_location_unavailable")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let locationManager = WeatherTestHelper.createValidLocationManager()
        locationManager.isAvailable = false
        let weatherManager = WeatherManager(locationManager: locationManager, skipMonitoring: true)

        weatherManager.refreshAvailability()

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isInitializing == false)
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.errorMessage == "Location services required")
    }

    @Test @MainActor func testRefreshAvailabilityReportsGettingLocationWhenCoordinatesMissing() throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_getting_location")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let locationManager = WeatherTestHelper.createValidLocationManager()
        locationManager.latitude = 0
        locationManager.longitude = 0
        let weatherManager = WeatherManager(locationManager: locationManager, skipMonitoring: true)

        weatherManager.refreshAvailability()

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isInitializing == true)
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.errorMessage == "Getting location...")
    }

    @Test @MainActor func testRefreshAvailabilityStartsTimerWhenLoadingSuppressesFetch() throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_refresh_timer")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true
        )
        weatherManager.isLoading = true

        weatherManager.refreshAvailability()

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isAvailable == true)
        #expect(weatherManager.weatherCheckTimer != nil)
        #expect(abs((weatherManager.weatherCheckTimer?.timeInterval ?? 0) - 900) < 0.1)

        weatherManager.isLoading = false
        weatherManager.stopMonitoring()
    }

    @Test @MainActor func testRefreshAvailabilityAutoFetchesWeatherWhenConditionsBecomeValid() async throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_refresh_autofetch")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let (session, cleanup) = WeatherTestHelper.createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, json)
        }
        defer { cleanup() }
        let weatherManager = WeatherManager(
            locationManager: WeatherTestHelper.createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        weatherManager.refreshAvailability()
        for _ in 0..<50 where weatherManager.currentWeather == nil && weatherManager.errorMessage.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isAvailable == true)
        #expect(weatherManager.isInitializing == false)
        #expect(weatherManager.currentWeather?.locationName == "San Francisco")
        #expect(weatherManager.weatherCheckTimer != nil)

        weatherManager.stopMonitoring()
    }
}
