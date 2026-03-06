//
//  SolarEventsTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let components = DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: 0,
        second: 0
    )
    return calendar.date(from: components)!
}

struct SolarEventsTests {

    // San Francisco, March 3 2026 — mid-latitude, well-defined sunrise/set
    let sfLat = 37.7749
    let sfLon = -122.4194
    // 2026-03-03 local noon in San Francisco (UTC-8 in winter = 20:00 UTC)
    let march3: Date = makeUTCDate(year: 2026, month: 3, day: 3, hour: 20)

    // MARK: - solarCrossing nil for polar conditions

    @Test func testCircumpolarReturnsNilForAstronomicalTwilight() {
        // At lat=89°, the Sun never dips to -18° in summer — should return nil for some date
        // Use June 21 (summer solstice), when Arctic has midnight sun
        let summerSolstice = makeUTCDate(year: 2026, month: 6, day: 21)
        let result = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -18.0, rising: true,
            date: summerSolstice, latDeg: 89.0, lonDeg: 0.0
        )
        #expect(result == nil)
    }

    @Test func testNeverRisesReturnsNil() {
        // At lat=-89°, the Sun never rises above -18° in June (polar night for South Pole)
        let summerSolstice = makeUTCDate(year: 2026, month: 6, day: 21)
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
    let march3: Date = makeUTCDate(year: 2026, month: 3, day: 3, hour: 20)

    @Test func testSolarDayEventsAreChronological() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        #expect(day.astronomicalDawn != nil)
        #expect(day.nauticalDawn != nil)
        #expect(day.civilDawn != nil)
        #expect(day.sunrise != nil)
        #expect(day.morningGoldenEnd != nil)
        #expect(day.eveningGoldenStart != nil)
        #expect(day.sunset != nil)
        #expect(day.civilDusk != nil)
        #expect(day.nauticalDusk != nil)
        #expect(day.astronomicalDusk != nil)

        guard let astronomicalDawn = day.astronomicalDawn,
              let nauticalDawn = day.nauticalDawn,
              let civilDawn = day.civilDawn,
              let sunrise = day.sunrise,
              let morningGoldenEnd = day.morningGoldenEnd,
              let eveningGoldenStart = day.eveningGoldenStart,
              let sunset = day.sunset,
              let civilDusk = day.civilDusk,
              let nauticalDusk = day.nauticalDusk,
              let astronomicalDusk = day.astronomicalDusk else {
            Issue.record("Expected all SolarDay events for the San Francisco test date")
            return
        }

        let times = [
            astronomicalDawn, nauticalDawn, civilDawn,
            sunrise, morningGoldenEnd,
            eveningGoldenStart, sunset,
            civilDusk, nauticalDusk, astronomicalDusk
        ]
        #expect(times.count == 10)
        for i in 1..<times.count {
            #expect(times[i-1] < times[i], "Events out of order at index \(i)")
        }
        // Also verify allEvents (the primary API) is sorted
        let events = day.allEvents
        #expect(events.count == 10)
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
        #expect(day.sunrise != nil)
        #expect(day.morningGoldenEnd != nil)
        guard let rise = day.sunrise, let goldEnd = day.morningGoldenEnd else {
            Issue.record("Expected sunrise and morning golden hour end for the San Francisco test date")
            return
        }
        #expect(rise < goldEnd)
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
        #expect(day.astronomicalDawn != nil)
        #expect(day.nauticalDawn != nil)
        guard let astro = day.astronomicalDawn, let nautical = day.nauticalDawn else {
            Issue.record("Expected astronomical and nautical dawn for the San Francisco test date")
            return
        }
        let next = day.nextEvent(after: astro.addingTimeInterval(1))
        #expect(next?.time == nautical)
    }
}
