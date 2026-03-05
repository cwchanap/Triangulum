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
        let sunset = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: false,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )

        guard let sunrise else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let sunset else {
            Issue.record("Expected non-nil sunset for mid-latitude test date")
            return
        }

        let solarNoon = sunrise.addingTimeInterval(sunset.timeIntervalSince(sunrise) / 2)
        #expect(sunrise < solarNoon)
        #expect(solarNoon < sunset)
    }

    @Test func testSunsetIsAfterNoon() {
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        let sunset = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: false,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )

        guard let sunrise else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let sunset else {
            Issue.record("Expected non-nil sunset for mid-latitude test date")
            return
        }

        let daylightDuration = sunset.timeIntervalSince(sunrise)
        #expect(daylightDuration > 0)
        #expect(daylightDuration < 20 * 3600)
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

        guard let sunrise else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let sunset else {
            Issue.record("Expected non-nil sunset for mid-latitude test date")
            return
        }

        #expect(sunrise < sunset)
    }

    @Test func testTwilightOrderIsCorrect() {
        // astronomical < nautical < civil < sunrise
        let astro = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -18.0, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let nautical = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -12.0, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let civil = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -6.0, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -0.833, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)

        guard let astro else {
            Issue.record("Expected non-nil astronomical twilight for mid-latitude test date")
            return
        }
        guard let nautical else {
            Issue.record("Expected non-nil nautical twilight for mid-latitude test date")
            return
        }
        guard let civil else {
            Issue.record("Expected non-nil civil twilight for mid-latitude test date")
            return
        }
        guard let sunrise else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }

        #expect(astro < nautical)
        #expect(nautical < civil)
        #expect(civil < sunrise)
    }

    @Test func testGoldenHourEndIsAfterSunrise() {
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -0.833, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let goldenEnd = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: 6.0, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)

        guard let sunrise else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let goldenEnd else {
            Issue.record("Expected non-nil golden hour end for mid-latitude test date")
            return
        }

        #expect(sunrise < goldenEnd)
    }
}

// MARK: - SolarDay Tests

struct SolarDayTests {

    let sfLat = 37.7749
    let sfLon = -122.4194
    let march3: Date = Date(timeIntervalSince1970: 1741032000)

    @Test func testSolarDayEventsAreChronological() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        let times = [
            day.astronomicalDawn, day.nauticalDawn, day.civilDawn,
            day.sunrise, day.morningGoldenEnd,
            day.eveningGoldenStart, day.sunset,
            day.civilDusk, day.nauticalDusk, day.astronomicalDusk
        ].compactMap { $0 }
        for i in 1..<times.count {
            #expect(times[i-1] < times[i], "Events out of order at index \(i)")
        }
        // Also verify allEvents (the primary API) is sorted
        let events = day.allEvents
        for i in 1..<events.count {
            #expect(events[i-1].time < events[i].time,
                    "allEvents out of order at index \(i): \(events[i-1].label) vs \(events[i].label)")
        }
    }

    @Test func testSolarDayAllNilAtNorthPoleInWinter() {
        // December 21 — polar night at 89°N, Sun never rises above -0.833°
        let dec21 = Date(timeIntervalSince1970: 1766361600) // ~2025-12-21
        let day = SolarDay(date: dec21, latitude: 89.0, longitude: 0.0)
        #expect(day.sunrise == nil)
        #expect(day.sunset == nil)
    }

    @Test func testSolarDayMorningGoldenEndAfterSunrise() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        if let rise = day.sunrise, let goldEnd = day.morningGoldenEnd {
            #expect(rise < goldEnd)
        }
    }

    @Test func testNextEventReturnsNilWhenAllPast() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        // Use a far-future "now" — after all events for the day
        let farFuture = march3.addingTimeInterval(24 * 3600)
        #expect(day.nextEvent(after: farFuture) == nil)
    }

    @Test func testNextEventReturnsFirstUpcoming() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        // Use astronomical dawn as "now" — next should be nautical dawn
        if let astro = day.astronomicalDawn, let nautical = day.nauticalDawn {
            let next = day.nextEvent(after: astro.addingTimeInterval(1))
            #expect(next?.time == nautical)
        }
    }
}
