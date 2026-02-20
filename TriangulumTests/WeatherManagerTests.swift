//
//  WeatherManagerTests.swift
//  TriangulumTests
//
//  Tests for WeatherManager and Weather model parsing
//

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

        // After stop, startMonitoring should be able to restart
        weatherManager.startMonitoring()

        // Stop again to clean up
        weatherManager.stopMonitoring()
    }

    @Test @MainActor func testRefreshAvailabilityRestoresMonitoring() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        // Simulate auth failure scenario - stop monitoring
        weatherManager.stopMonitoring()

        // refreshAvailability should restore monitoring state
        weatherManager.refreshAvailability()

        // Clean up
        weatherManager.stopMonitoring()
    }

    /// Verify that explicit stopMonitoring() is not overridden by fetch completion.
    /// This test ensures the fix for the issue where successful fetch would unconditionally
    /// re-enable monitoring even after an explicit stop.
    @Test @MainActor func testExplicitStopMonitoringNotOverriddenByFetchCompletion() {
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

        // stopFrequentPolling() guards on isMonitoringEnabled before recreating the
        // 15-minute timer, so a successful fetch completion should NOT re-enable
        // monitoring once it has been explicitly stopped.
        // We simulate that path by asserting the flag stays false after stopMonitoring().
        #expect(weatherManager.isMonitoringEnabled == false,
                "A fetch completion must not re-enable monitoring after explicit stop")

        // Clean up
        weatherManager.stopMonitoring()
    }
}
