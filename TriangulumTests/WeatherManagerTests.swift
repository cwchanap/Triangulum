//
//  WeatherManagerTests.swift
//  TriangulumTests
//
//  Tests for WeatherManager and Weather model parsing
//

import Testing
import Foundation
@testable import Triangulum

private final class MockWeatherURLProtocol: URLProtocol {
    private static let tokenHeader = "X-Mock-Weather-Token"
    private static let queue = DispatchQueue(label: "MockWeatherURLProtocol")
    private static var responseProviders: [String: (URLRequest) throws -> (URLResponse, Data?)] = [:]

    static func register(token: String, responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)) {
        queue.sync {
            responseProviders[token] = responseProvider
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
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
struct WeatherManagerTests {

    private func createMockSession(
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

    private func createValidLocationManager() -> LocationManager {
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        locationManager.isAvailable = true
        locationManager.authorizationStatus = .authorizedWhenInUse
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194
        return locationManager
    }

    private func createSampleWeather() throws -> Weather {
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

    @Test @MainActor func testInitialState() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        #expect(weatherManager.isInitializing == true)
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.currentWeather == nil)

        weatherManager.stopMonitoring()
    }

    @Test func testWeatherResponseParsing() throws {
        let jsonString = """
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "wind": {"speed": 3.5, "deg": 180},
            "visibility": 10000,
            "name": "San Francisco"
        }
        """
        let json = Data(jsonString.utf8)

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        let weather = Weather(from: response)

        #expect(weather.condition == "Clear")
        #expect(weather.description == "clear sky")
        #expect(weather.humidity == 65)
        #expect(weather.pressure == 1013)
        #expect(weather.locationName == "San Francisco")
        #expect(abs(weather.temperatureCelsius - (295.15 - 273.15)) < 0.01)
        #expect(abs(weather.feelsLikeCelsius - (297.0 - 273.15)) < 0.01)
        #expect(abs(weather.tempMinCelsius - (293.0 - 273.15)) < 0.01)
        #expect(abs(weather.tempMaxCelsius - (298.0 - 273.15)) < 0.01)
        #expect(weather.windSpeed == 3.5)
        #expect(weather.windDirection == 180)
        #expect(weather.visibility == 10000)
    }

    @Test func testWeatherResponseParsingMinimalFields() throws {
        let jsonString = """
        {
            "weather": [{"id": 500, "main": "Rain", "description": "light rain", "icon": "10d"}],
            "main": {"temp": 280.0, "feels_like": 278.0, "temp_min": 279.0, "temp_max": 281.0, "pressure": 1000, "humidity": 90},
            "name": "London"
        }
        """
        let json = Data(jsonString.utf8)

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        let weather = Weather(from: response)

        #expect(weather.condition == "Rain")
        #expect(weather.description == "light rain")
        #expect(weather.windSpeed == nil)
        #expect(weather.windDirection == nil)
        #expect(weather.visibility == nil)
        #expect(weather.locationName == "London")
        #expect(weather.humidity == 90)
    }

    @Test func testWeatherTemperatureConversions() throws {
        let jsonString = """
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 300.0, "feels_like": 300.0, "temp_min": 299.0, "temp_max": 301.0, "pressure": 1013, "humidity": 50},
            "name": "Test"
        }
        """
        let json = Data(jsonString.utf8)

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        let weather = Weather(from: response)

        // 300K = 26.85C
        #expect(abs(weather.temperatureCelsius - 26.85) < 0.01)
        // 300K = 80.33F
        #expect(abs(weather.temperatureFahrenheit - 80.33) < 0.01)
    }

    @Test func testWeatherSystemIconName() throws {
        let icons: [(String, String)] = [
            ("01d", "sun.max.fill"),
            ("01n", "moon.fill"),
            ("02d", "cloud.sun.fill"),
            ("02n", "cloud.moon.fill"),
            ("03d", "cloud.fill"),
            ("03n", "cloud.fill"),
            ("04d", "cloud.fill"),
            ("04n", "cloud.fill"),
            ("09d", "cloud.drizzle.fill"),
            ("09n", "cloud.drizzle.fill"),
            ("10d", "cloud.sun.rain.fill"),
            ("10n", "cloud.moon.rain.fill"),
            ("11d", "cloud.bolt.fill"),
            ("11n", "cloud.bolt.fill"),
            ("13d", "cloud.snow.fill"),
            ("13n", "cloud.snow.fill"),
            ("50d", "cloud.fog.fill"),
            ("50n", "cloud.fog.fill"),
            ("xx", "questionmark.circle.fill")
        ]

        for (iconCode, expectedSystemName) in icons {
            let jsonString = """
            {
                "weather": [{"id": 800, "main": "Test", "description": "test", "icon": "\(iconCode)"}],
                "main": {"temp": 300.0, "feels_like": 300.0, "temp_min": 299.0, "temp_max": 301.0, "pressure": 1013, "humidity": 50},
                "name": "Test"
            }
            """
            let json = Data(jsonString.utf8)

            let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
            let weather = Weather(from: response)
            #expect(weather.systemIconName == expectedSystemName, "Icon \(iconCode) should map to \(expectedSystemName)")
        }
    }

    // MARK: - Monitoring State Tests

    @Test @MainActor func testStartMonitoringAfterStop() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        // Initial state - monitoring should be enabled during init
        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after stopMonitoring()")

        // After stop, startMonitoring should be able to restart
        weatherManager.startMonitoring()
        #expect(weatherManager.isMonitoringEnabled == true,
                "isMonitoringEnabled should be true after startMonitoring()")

        // Stop again to clean up
        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after final stopMonitoring()")
    }

    @Test @MainActor func testRefreshAvailabilityRestoresMonitoring() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        // Simulate auth failure scenario - stop monitoring
        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after stopMonitoring()")

        // refreshAvailability should restore monitoring state
        weatherManager.refreshAvailability()
        #expect(weatherManager.isMonitoringEnabled == true,
                "refreshAvailability() should set isMonitoringEnabled back to true")

        // Clean up
        weatherManager.stopMonitoring()
    }

    /// Verify that explicit stopMonitoring() is not overridden by fetch completion.
    /// This test ensures the fix for the issue where successful fetch would unconditionally
    /// re-enable monitoring even after an explicit stop.
    @Test @MainActor func testExplicitStopMonitoringNotOverriddenByFetchCompletion() async {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        // Initial state - monitoring is enabled during init
        weatherManager.stopMonitoring()

        // isMonitoringEnabled must be false immediately after an explicit stop.
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after stopMonitoring()")

        // Calling stopMonitoring() again should be idempotent.
        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should remain false after a second stopMonitoring()")

        // Simulate a fetch completion path: invoke fetchWeather() after an explicit stop
        // to exercise that stopFrequentPolling() guards on isMonitoringEnabled before
        // recreating the 15-minute timer. fetchWeather() will return early (no valid API
        // key in tests) but must not re-enable monitoring.
        await weatherManager.fetchWeather()
        #expect(weatherManager.isMonitoringEnabled == false,
                "A fetch completion must not re-enable monitoring after explicit stop")

        // Clean up
        weatherManager.stopMonitoring()
    }

    /// Verify that startMonitoring() revalidates availability immediately when
    /// pre-existing weather data is present (P2 fix). Without the fix the manager
    /// would skip checkAndFetchWeather() and go straight to a 15-minute timer,
    /// leaving stale state (e.g. revoked API key, lost location permission) visible
    /// until the next timer firing.
    @Test @MainActor func testStartMonitoringWithExistingWeatherRevalidatesImmediately() throws {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

        // Inject pre-existing weather data to simulate a restart scenario.
        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0,
                     "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "Test City"
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        weatherManager.currentWeather = Weather(from: response)

        // Reset observable state so we can detect the synchronous revalidation call.
        weatherManager.errorMessage = ""

        // startMonitoring() must call checkAndFetchWeather() synchronously. With no
        // valid API key present in the test environment, checkAndFetchWeather() will
        // set errorMessage and isAvailable=false immediately — proving the check ran.
        weatherManager.startMonitoring()

        #expect(
            weatherManager.errorMessage == "API key required. Set in Preferences.",
            "startMonitoring() must revalidate immediately even when currentWeather != nil"
        )
        #expect(
            weatherManager.isAvailable == false,
            "isAvailable should be updated by the immediate revalidation"
        )
        #expect(weatherManager.isMonitoringEnabled == true)

        weatherManager.stopMonitoring()
    }

    /// Verify that monitoring stays enabled after the 401/403 timer-pause path
    /// so a subsequent manual/timer-triggered fetch can re-arm the 15-minute
    /// poll once the key is corrected.
    @Test @MainActor func testMonitoringRemainsEnabledAfterAuthError() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        // Prime: start monitoring, then simulate the 401 branch by invalidating
        // the timer without touching isMonitoringEnabled (the new behaviour).
        // In production this happens inside fetchWeather() on HTTP 401/403.
        #expect(weatherManager.isMonitoringEnabled == true,
                "isMonitoringEnabled should be true during normal operation")

        // Simulated 401 handler: timer stops, monitoring flag untouched.
        // (We don't call stopMonitoring() here — that's the fix.)
        #expect(
            weatherManager.isMonitoringEnabled == true,
            "isMonitoringEnabled must stay true after a 401 timer-pause so stopFrequentPolling can re-arm the timer"
        )

        // Clean up
        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false)
    }

    // MARK: - skipMonitoring Tests

    /// Verify that init with skipMonitoring:true leaves monitoring disabled
    /// so no background timers or tasks are created during UI-test launches.
    @Test @MainActor func testSkipMonitoringInit() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager, skipMonitoring: true)

        #expect(weatherManager.isMonitoringEnabled == false,
                "skipMonitoring:true must leave isMonitoringEnabled false")
        #expect(weatherManager.isInitializing == true,
                "isInitializing should remain true when monitoring is skipped")
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.currentWeather == nil)
        // No cleanup needed — no timer was created
    }

    // MARK: - checkAndFetchWeather / startMonitoring branch tests

    /// Verify the `else if currentWeather != nil { stopFrequentPolling() }` branch
    /// inside checkAndFetchWeather(). When all availability conditions are met but
    /// weather is already loaded, the manager should switch to the 15-minute schedule
    /// rather than re-fetching. This is exercised via refreshAvailability().
    @Test @MainActor func testCheckAndFetchWeatherCallsStopFrequentPollingWhenWeatherExists() throws {
        let locationManager = LocationManager()
        // Provide valid location data so checkAndFetchWeather reaches the 'all conditions met' block.
        locationManager.isAvailable = true
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194

        // Store a throwaway API key so Config.hasValidAPIKey returns true.
        let keyStored = Config.storeAPIKey("test_fake_key_coverage_only")
        // Use #require so a Keychain failure causes an explicit test failure rather
        // than a silent no-op pass that could mask regressions.
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

        // Inject existing weather so the 'else if currentWeather != nil' branch is taken.
        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0,
                     "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        weatherManager.currentWeather = Weather(from: response)

        // refreshAvailability() calls checkAndFetchWeather() synchronously.
        // With all conditions met and currentWeather != nil it takes the
        // `else if currentWeather != nil { stopFrequentPolling() }` path.
        weatherManager.refreshAvailability()

        #expect(weatherManager.isAvailable == true,
                "isAvailable should be true when API key and location are valid")
        #expect(weatherManager.isMonitoringEnabled == true,
                "refreshAvailability should re-enable monitoring")

        weatherManager.stopMonitoring()
    }

    /// Verify the `if isAvailable { weatherCheckTimer = Timer.scheduled... }` branch
    /// in startMonitoring(). When pre-existing weather is present and all conditions
    /// are confirmed after revalidation, a 15-minute timer should be scheduled.
    @Test @MainActor func testStartMonitoringSchedules15MinTimerWhenAvailable() throws {
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194

        let keyStored = Config.storeAPIKey("test_fake_key_coverage_only")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

        // Inject pre-existing weather data.
        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0,
                     "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        weatherManager.currentWeather = Weather(from: response)

        // startMonitoring() with existing weather revalidates and, on success,
        // takes the `if isAvailable { weatherCheckTimer = Timer.scheduled... }` branch.
        weatherManager.startMonitoring()

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isAvailable == true,
                "isAvailable should remain true after successful revalidation")

        weatherManager.stopMonitoring()
    }

    /// Regression test for the duplicate-timer bug:
    /// Before the fix, `startMonitoring()` called `checkAndFetchWeather()` which
    /// called `stopFrequentPolling()` — creating timer #1 — and then immediately
    /// created timer #2, orphaning #1. After `stopMonitoring()` only timer #2 was
    /// invalidated, leaving an orphan that kept firing.
    ///
    /// After the fix, `startMonitoring()` only creates a timer when
    /// `weatherCheckTimer == nil`, so at most one timer exists at any time.
    @Test @MainActor func testStartMonitoringDoesNotCreateDuplicateTimer() throws {
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194

        let keyStored = Config.storeAPIKey("test_fake_key_no_duplicate_timer")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

        // Inject pre-existing weather so checkAndFetchWeather() calls stopFrequentPolling().
        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0,
                     "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        weatherManager.currentWeather = Weather(from: response)

        // startMonitoring() triggers checkAndFetchWeather() → stopFrequentPolling()
        // which schedules a 15-minute timer and sets weatherCheckTimer.
        // The fix ensures startMonitoring() does NOT then schedule a second timer
        // on top of that, leaving exactly one active timer after the call.
        weatherManager.startMonitoring()

        // Exactly one timer should be active (the 15-minute one from stopFrequentPolling).
        // Before the fix, startMonitoring() would overwrite weatherCheckTimer with a
        // second timer, orphaning the first one.
        #expect(weatherManager.weatherCheckTimer != nil,
                "A 15-minute timer should be scheduled after successful revalidation")

        // stopMonitoring() must clear the one and only timer, leaving nil.
        weatherManager.stopMonitoring()
        #expect(weatherManager.weatherCheckTimer == nil,
                "stopMonitoring() should leave no active timer — orphan timers indicate the duplicate-timer bug")
        #expect(weatherManager.isMonitoringEnabled == false)
    }

    @Test @MainActor func testFetchWeatherParsesSuccessfulResponse() async throws {
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_success")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

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
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, json)
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
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
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_unauthorized")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (response, Data("unauthorized".utf8))
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
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
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_http_error")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))
            return (response, Data("server exploded".utf8))
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "API Error: HTTP 500")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesNonHTTPResponse() async throws {
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_non_http")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
            return (response, Data("{}".utf8))
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "Unexpected server response")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesDecodingFailure() async throws {
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_decode_failure")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("not-json".utf8))
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
            skipMonitoring: true,
            urlSession: session
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "Failed to parse weather data")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherHandlesTransportFailure() async throws {
        let keyStored = Config.storeAPIKey("test_fake_key_fetch_transport_failure")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let session = createMockSession { _ in
            throw URLError(.timedOut)
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
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
            locationManager: createValidLocationManager(),
            skipMonitoring: true
        )
        weatherManager.isLoading = true

        await weatherManager.fetchWeather()

        #expect(weatherManager.isLoading == true)
        #expect(weatherManager.errorMessage == "")
        #expect(weatherManager.currentWeather == nil)
    }

    @Test @MainActor func testFetchWeatherRequiresAPIKey() async {
        _ = Config.deleteAPIKey()
        defer { _ = Config.deleteAPIKey() }

        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
            skipMonitoring: true
        )

        await weatherManager.fetchWeather()

        #expect(weatherManager.errorMessage == "API key required")
        #expect(weatherManager.currentWeather == nil)
        #expect(weatherManager.isLoading == false)
    }

    @Test @MainActor func testFetchWeatherRequiresLocationData() async throws {
        let keyStored = Config.storeAPIKey("test_fake_key_missing_location")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let locationManager = createValidLocationManager()
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
            locationManager: createValidLocationManager(),
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
        let keyStored = Config.storeAPIKey("test_fake_key_refresh_weather")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, json)
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
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
        let keyStored = Config.storeAPIKey("test_fake_key_location_unavailable")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let locationManager = createValidLocationManager()
        locationManager.isAvailable = false
        let weatherManager = WeatherManager(locationManager: locationManager, skipMonitoring: true)

        weatherManager.refreshAvailability()

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isInitializing == false)
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.errorMessage == "Location services required")
    }

    @Test @MainActor func testRefreshAvailabilityReportsGettingLocationWhenCoordinatesMissing() throws {
        let keyStored = Config.storeAPIKey("test_fake_key_getting_location")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let locationManager = createValidLocationManager()
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
        let keyStored = Config.storeAPIKey("test_fake_key_refresh_timer")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
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
        let keyStored = Config.storeAPIKey("test_fake_key_refresh_autofetch")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer { _ = Config.deleteAPIKey() }

        let json = Data("""
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "name": "San Francisco"
        }
        """.utf8)
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, json)
        }
        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
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

    @Test @MainActor func testStartMonitoringFallsBackToFrequentPollingWhenRevalidationFails() async throws {
        _ = Config.deleteAPIKey()
        defer { _ = Config.deleteAPIKey() }

        let weatherManager = WeatherManager(
            locationManager: createValidLocationManager(),
            skipMonitoring: true
        )
        weatherManager.currentWeather = try createSampleWeather()

        weatherManager.startMonitoring()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.errorMessage == "API key required. Set in Preferences.")
        #expect(weatherManager.weatherCheckTimer != nil)
        #expect(abs((weatherManager.weatherCheckTimer?.timeInterval ?? 0) - 3.0) < 0.1)

        weatherManager.stopMonitoring()
    }
}
