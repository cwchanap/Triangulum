import Testing
import Foundation
@testable import Triangulum

@Suite(.serialized)
struct WeatherManagerTests {

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

        #expect(abs(weather.temperatureCelsius - 26.85) < 0.01)
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

        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after stopMonitoring()")

        weatherManager.startMonitoring()
        #expect(weatherManager.isMonitoringEnabled == true,
                "isMonitoringEnabled should be true after startMonitoring()")

        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after final stopMonitoring()")
    }

    @Test @MainActor func testRefreshAvailabilityRestoresMonitoring() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after stopMonitoring()")

        weatherManager.refreshAvailability()
        #expect(weatherManager.isMonitoringEnabled == true,
                "refreshAvailability() should set isMonitoringEnabled back to true")

        weatherManager.stopMonitoring()
    }

    @Test @MainActor func testExplicitStopMonitoringNotOverriddenByFetchCompletion() async {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        weatherManager.stopMonitoring()

        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should be false after stopMonitoring()")

        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false,
                "isMonitoringEnabled should remain false after a second stopMonitoring()")

        await weatherManager.fetchWeather()
        #expect(weatherManager.isMonitoringEnabled == false,
                "A fetch completion must not re-enable monitoring after explicit stop")

        weatherManager.stopMonitoring()
    }

    @Test @MainActor func testStartMonitoringWithExistingWeatherRevalidatesImmediately() throws {
        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        _ = Config.deleteAPIKey()
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

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

        weatherManager.errorMessage = ""

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

    @Test @MainActor func testMonitoringRemainsEnabledAfterAuthError() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        #expect(weatherManager.isMonitoringEnabled == true,
                "isMonitoringEnabled should be true during normal operation")

        #expect(
            weatherManager.isMonitoringEnabled == true,
            "isMonitoringEnabled must stay true after a 401 timer-pause so stopFrequentPolling can re-arm the timer"
        )

        weatherManager.stopMonitoring()
        #expect(weatherManager.isMonitoringEnabled == false)
    }

    // MARK: - skipMonitoring Tests

    @Test @MainActor func testSkipMonitoringInit() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager, skipMonitoring: true)

        #expect(weatherManager.isMonitoringEnabled == false,
                "skipMonitoring:true must leave isMonitoringEnabled false")
        #expect(weatherManager.isInitializing == true,
                "isInitializing should remain true when monitoring is skipped")
        #expect(weatherManager.isAvailable == false)
        #expect(weatherManager.currentWeather == nil)
    }

    // MARK: - checkAndFetchWeather / startMonitoring branch tests

    @Test @MainActor func testCheckAndFetchWeatherCallsStopFrequentPollingWhenWeatherExists() throws {
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194

        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_coverage_only")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

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

        weatherManager.refreshAvailability()

        #expect(weatherManager.isAvailable == true,
                "isAvailable should be true when API key and location are valid")
        #expect(weatherManager.isMonitoringEnabled == true,
                "refreshAvailability should re-enable monitoring")

        weatherManager.stopMonitoring()
    }

    @Test @MainActor func testStartMonitoringSchedules15MinTimerWhenAvailable() throws {
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194

        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_coverage_only")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

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

        weatherManager.startMonitoring()

        #expect(weatherManager.isMonitoringEnabled == true)
        #expect(weatherManager.isAvailable == true,
                "isAvailable should remain true after successful revalidation")

        weatherManager.stopMonitoring()
    }

    @Test @MainActor func testStartMonitoringDoesNotCreateDuplicateTimer() throws {
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194

        let savedKey = Config.openWeatherAPIKey
        let hadKey = !savedKey.isEmpty
        let keyStored = Config.storeAPIKey("test_fake_key_no_duplicate_timer")
        try #require(keyStored, "Config.storeAPIKey must succeed; Keychain unavailable in this environment")
        defer {
            if hadKey { _ = Config.storeAPIKey(savedKey) } else { _ = Config.deleteAPIKey() }
        }

        let weatherManager = WeatherManager(locationManager: locationManager)
        weatherManager.stopMonitoring()

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

        weatherManager.startMonitoring()

        #expect(weatherManager.weatherCheckTimer != nil,
                "A 15-minute timer should be scheduled after successful revalidation")

        weatherManager.stopMonitoring()
        #expect(weatherManager.weatherCheckTimer == nil,
                "stopMonitoring() should leave no active timer — orphan timers indicate the duplicate-timer bug")
        #expect(weatherManager.isMonitoringEnabled == false)
    }

    @Test @MainActor func testStartMonitoringFallsBackToFrequentPollingWhenRevalidationFails() async throws {
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
        weatherManager.currentWeather = try WeatherTestHelper.createSampleWeather()

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
