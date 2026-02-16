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
        #expect(weather.humidity == 65)
        #expect(weather.pressure == 1013)
        #expect(weather.locationName == "San Francisco")
        #expect(abs(weather.temperatureCelsius - (295.15 - 273.15)) < 0.01)
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
            ("02n", "cloud.sun.fill"),
            ("03d", "cloud.fill"),
            ("09d", "cloud.drizzle.fill"),
            ("10d", "cloud.rain.fill"),
            ("11d", "cloud.bolt.fill"),
            ("13d", "cloud.snow.fill"),
            ("50d", "cloud.fog.fill")
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
}
