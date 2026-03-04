//
//  SolarEventsTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct SolarEventsTests {

    // San Francisco, March 3 2026 — mid-latitude, well-defined sunrise/set
    let sfLat = 37.7749
    let sfLon = -122.4194
    // Unix timestamp for 2026-03-03 local noon in San Francisco (UTC-8 in winter = 20:00 UTC)
    // 2026-03-03 20:00 UTC = 1741032000
    let march3: Date = Date(timeIntervalSince1970: 1741032000)

    // MARK: - solarCrossing nil for polar conditions

    @Test func testCircumpolarReturnsNilForAstronomicalTwilight() {
        // At lat=89°, the Sun never dips to -18° in summer — should return nil for some date
        // Use June 21 (summer solstice), when Arctic has midnight sun
        let summerSolstice = Date(timeIntervalSince1970: 1750291200) // ~2025-06-19 UTC
        let result = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -18.0, rising: true,
            date: summerSolstice, latDeg: 89.0, lonDeg: 0.0
        )
        #expect(result == nil)
    }

    @Test func testNeverRisesReturnsNil() {
        // At lat=-89°, the Sun never rises above -18° in June (polar night for South Pole)
        let summerSolstice = Date(timeIntervalSince1970: 1750291200)
        let result = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: summerSolstice, latDeg: -89.0, lonDeg: 0.0
        )
        #expect(result == nil)
    }

    // MARK: - solarCrossing approximate correctness

    @Test func testSunriseIsBeforeNoon() {
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        #expect(sunrise != nil)
        if let t = sunrise {
            // Sunrise in SF in March is around 06:30-07:00 local time.
            // Verify it falls in the morning hours (before noon).
            let cal = Calendar.current
            let hour = cal.component(.hour, from: t)
            #expect(hour >= 5 && hour <= 9)
        }
    }

    @Test func testSunsetIsAfterNoon() {
        let sunset = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: false,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        #expect(sunset != nil)
        if let t = sunset {
            let cal = Calendar.current
            let hour = cal.component(.hour, from: t)
            #expect(hour >= 17 && hour <= 21)
        }
    }

    @Test func testSunriseBeforeSunset() {
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        let sunset = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: false,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        #expect(sunrise != nil)
        #expect(sunset != nil)
        if let rise = sunrise, let set = sunset {
            #expect(rise < set)
        }
    }

    @Test func testTwilightOrderIsCorrect() {
        // astronomical < nautical < civil < sunrise
        let astro   = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -18.0,  rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let nautical = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -12.0, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let civil    = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -6.0,  rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let sunrise  = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -0.833, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        if let a = astro, let n = nautical, let c = civil, let s = sunrise {
            #expect(a < n)
            #expect(n < c)
            #expect(c < s)
        }
    }

    @Test func testGoldenHourEndIsAfterSunrise() {
        let sunrise    = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -0.833, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let goldenEnd  = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: 6.0,   rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        #expect(sunrise != nil)
        #expect(goldenEnd != nil)
        if let s = sunrise, let g = goldenEnd {
            #expect(s < g)
        }
    }
}
