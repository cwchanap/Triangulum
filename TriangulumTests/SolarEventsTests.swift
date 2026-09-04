//
//  SolarEventsTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

private let utc = TimeZone(secondsFromGMT: 0)!
private let pacific = TimeZone(identifier: "America/Los_Angeles")!

private func solarCrossing(
    _ altitudeDeg: Double,
    rising: Bool,
    localDate: LocalDate,
    timeZone: TimeZone,
    latDeg: Double,
    lonDeg: Double
) -> Date? {
    ConstellationMapView.Astronomer.solarCrossing(
        altitudeDeg: altitudeDeg,
        rising: rising,
        localDate: localDate,
        timeZone: timeZone,
        latDeg: latDeg,
        lonDeg: lonDeg
    )
}

struct SolarEventsTests {

    // San Francisco, March 3 2026 — mid-latitude, well-defined sunrise/set
    let sfLat = 37.7749
    let sfLon = -122.4194
    let march3 = LocalDate(year: 2026, month: 3, day: 3)

    // MARK: - destination-aware solarCrossing

    @Test func sunriseOnTokyoCalendarDay() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833,
            rising: true,
            localDate: .init(year: 2026, month: 9, day: 1),
            timeZone: tokyo,
            latDeg: 35.6762,
            lonDeg: 139.6503
        )
        #expect(sunrise != nil)
    }

    // MARK: - solarCrossing nil for polar conditions

    @Test func circumpolarReturnsNilForAstronomicalTwilight() {
        // At lat=89°, the Sun never dips to -18° in summer — should return nil
        // Use June 21 (summer solstice), when Arctic has midnight sun
        let result = solarCrossing(-18.0, rising: true,
                                   localDate: LocalDate(year: 2026, month: 6, day: 21),
                                   timeZone: utc, latDeg: 89.0, lonDeg: 0.0)
        #expect(result == nil)
    }

    @Test func neverRisesReturnsNil() {
        // At lat=-89°, the Sun never rises above -0.833° in June (polar night for South Pole)
        let result = solarCrossing(-0.833, rising: true,
                                   localDate: LocalDate(year: 2026, month: 6, day: 21),
                                   timeZone: utc, latDeg: -89.0, lonDeg: 0.0)
        #expect(result == nil)
    }

    // MARK: - solarCrossing approximate correctness

    @Test func sunriseIsBeforeSolarNoon() {
        guard let sunrise = solarCrossing(-0.833, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let sunset = solarCrossing(-0.833, rising: false, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunset for mid-latitude test date")
            return
        }

        let solarNoon = sunrise.addingTimeInterval(sunset.timeIntervalSince(sunrise) / 2)
        #expect(sunrise < solarNoon)
        #expect(solarNoon < sunset)
    }

    @Test func dayLightDurationIsPlausible() {
        guard let sunrise = solarCrossing(-0.833, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let sunset = solarCrossing(-0.833, rising: false, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunset for mid-latitude test date")
            return
        }

        let daylightDuration = sunset.timeIntervalSince(sunrise)
        #expect(daylightDuration > 0)
        #expect(daylightDuration < 20 * 3600)
    }

    @Test func sunriseBeforeSunset() {
        guard let sunrise = solarCrossing(-0.833, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let sunset = solarCrossing(-0.833, rising: false, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunset for mid-latitude test date")
            return
        }

        #expect(sunrise < sunset)
    }

    @Test func twilightOrderIsCorrect() {
        // astronomical < nautical < civil < sunrise
        guard let astro = solarCrossing(-18.0, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil astronomical twilight for mid-latitude test date")
            return
        }
        guard let nautical = solarCrossing(-12.0, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil nautical twilight for mid-latitude test date")
            return
        }
        guard let civil = solarCrossing(-6.0, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil civil twilight for mid-latitude test date")
            return
        }
        guard let sunrise = solarCrossing(-0.833, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }

        #expect(astro < nautical)
        #expect(nautical < civil)
        #expect(civil < sunrise)
    }

    @Test func goldenHourEndIsAfterSunrise() {
        guard let sunrise = solarCrossing(-0.833, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil sunrise for mid-latitude test date")
            return
        }
        guard let goldenEnd = solarCrossing(6.0, rising: true, localDate: march3, timeZone: pacific, latDeg: sfLat, lonDeg: sfLon) else {
            Issue.record("Expected non-nil golden hour end for mid-latitude test date")
            return
        }

        #expect(sunrise < goldenEnd)
    }

    // MARK: - Civil-day bounds (high-latitude transition regression)

    /// Regression: the local-noon reference is an approximation, so a
    /// crossing can land on an adjacent civil day near polar transition
    /// dates. `solarCrossing` must never return a crossing outside the
    /// requested civil day — otherwise `SolarDay(date:)` attaches it to that
    /// date while the UI formats only `HH:mm`, mislabeling e.g. an Aug 26
    /// 00:10 sunset as Aug 25's sunset.
    @Test func crossingNeverFallsOutsideTheRequestedCivilDay() throws {
        // Cases spanning mid-latitudes and high-latitude transition dates
        // where the bug first appears.
        struct CrossingCase {
            let date: LocalDate
            let timeZone: TimeZone
            let lat: Double
            let lon: Double
        }
        let cases: [CrossingCase] = [
            CrossingCase(date: LocalDate(year: 2026, month: 8, day: 25),
                         timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!,
                         lat: 78.2232, lon: 15.65),
            CrossingCase(date: LocalDate(year: 2026, month: 8, day: 26),
                         timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!,
                         lat: 78.2232, lon: 15.65),
            // Utqiagvik around the sun's return in early August.
            CrossingCase(date: LocalDate(year: 2026, month: 8, day: 2),
                         timeZone: TimeZone(identifier: "America/Anchorage")!,
                         lat: 71.2906, lon: -156.7886),
            CrossingCase(date: LocalDate(year: 2026, month: 3, day: 3),
                         timeZone: pacific, lat: sfLat, lon: sfLon)
        ]
        for c in cases {
            let dayStart = try c.date.start(in: c.timeZone)
            let dayEnd = try c.date.endExclusive(in: c.timeZone)
            for altitude in [-18.0, -12.0, -6.0, -0.833, 6.0] {
                for rising in [true, false] {
                    guard let crossing = solarCrossing(altitude, rising: rising,
                                                       localDate: c.date, timeZone: c.timeZone,
                                                       latDeg: c.lat, lonDeg: c.lon) else { continue }
                    #expect(crossing >= dayStart && crossing < dayEnd,
                            "Crossing \(crossing) for \(c.date) lat\(c.lat) alt\(altitude) rising\(rising) outside civil day [\(dayStart), \(dayEnd))")
                }
            }
        }
    }

    /// Longyearbyen on 2026-08-25: the review's exact scenario. The local-noon
    /// approximation puts the post-transit sunset at ~00:10 Aug 26, but
    /// Longyearbyen actually has a late Aug-25 sunset (~23:55 local). The
    /// crossing must be refined within the civil day rather than clamped to
    /// nil, so the UI shows a real sunset and daylight duration on a day that
    /// has one.
    @Test func longyearbyenAug25HasAnInDaySunset() throws {
        let zone = TimeZone(identifier: "Arctic/Longyearbyen")!
        let date = LocalDate(year: 2026, month: 8, day: 25)
        let dayStart = try date.start(in: zone)
        let dayEnd = try date.endExclusive(in: zone)

        let sunset = solarCrossing(-0.833, rising: false, localDate: date,
                                   timeZone: zone, latDeg: 78.2232, lonDeg: 15.65)
        #expect(sunset != nil,
                "Longyearbyen Aug 25 2026 has a real late sunset; the crossing must resolve within the civil day, not be dropped as nil")
        if let sunset {
            #expect(sunset >= dayStart && sunset < dayEnd,
                    "Longyearbyen Aug 25 2026 sunset \(sunset) must fall within the civil day, not on Aug 26")
        }
        // The sunrise, if present, must likewise stay within Aug 25.
        let sunrise = solarCrossing(-0.833, rising: true, localDate: date,
                                    timeZone: zone, latDeg: 78.2232, lonDeg: 15.65)
        if let sunrise {
            #expect(sunrise >= dayStart && sunrise < dayEnd,
                    "Longyearbyen Aug 25 2026 sunrise \(sunrise) must fall within the civil day")
        }
    }

    /// Regression (P1): Longyearbyen on 2026-03-20 (vernal equinox). At 78°N
    /// the noon-based `cosH` for a -12° rising (nautical dawn) crossing lands
    /// just outside [-1, 1] (≈ -1.014) because the equinox declination isn't
    /// exactly 0° at local noon, so the feasibility guard previously returned
    /// nil before the full-day scan could find the real ~00:21 local nautical
    /// dawn. The infeasible-approximation path must fall back to the day scan
    /// instead of dropping the event.
    @Test func longyearbyenMar20NauticalDawnIsNotDroppedByNoonFeasibility() throws {
        let zone = TimeZone(identifier: "Arctic/Longyearbyen")!
        let date = LocalDate(year: 2026, month: 3, day: 20)
        let dayStart = try date.start(in: zone)
        let dayEnd = try date.endExclusive(in: zone)

        let nauticalDawn = solarCrossing(-12.0, rising: true, localDate: date,
                                         timeZone: zone, latDeg: 78.2232, lonDeg: 15.65)
        #expect(nauticalDawn != nil,
                "Longyearbyen Mar 20 2026 has a real nautical dawn; the noon cosH feasibility guard must not drop it as nil")
        if let nauticalDawn {
            #expect(nauticalDawn >= dayStart && nauticalDawn < dayEnd,
                    "Longyearbyen Mar 20 2026 nautical dawn \(nauticalDawn) must fall within the civil day")
        }
    }
}

// MARK: - SolarDay Tests

struct SolarDayTests {

    let sfLat = 37.7749
    let sfLon = -122.4194
    let march3 = LocalDate(year: 2026, month: 3, day: 3)

    private func makeSFDay() throws -> SolarDay {
        try SolarDay(date: march3, timeZone: pacific, latitude: sfLat, longitude: sfLon)
    }

    @Test func solarDayEventsAreChronological() throws {
        let day = try makeSFDay()
        #expect(day.state == .normal)

        let events = day.allEvents
        #expect(events.count == 10)
        for i in 1..<events.count {
            #expect(events[i-1].instant < events[i].instant,
                    "allEvents out of order at index \(i): \(events[i-1].kind) vs \(events[i].kind)")
        }

        let kinds = events.map(\.kind)
        #expect(kinds == SolarEventKind.allCases.filter { kinds.contains($0) },
                "allEvents should follow morning→evening kind order when times are tied")
    }

    @Test func solarDayPolarNightAt89NInDecember() throws {
        // December 21 — polar night at 89°N, Sun never rises above -0.833°
        let day = try SolarDay(date: LocalDate(year: 2026, month: 12, day: 21),
                               timeZone: utc, latitude: 89.0, longitude: 0.0)
        #expect(day.state == .polarNight)
        #expect(day.event(.sunrise) == nil)
        #expect(day.event(.sunset) == nil)
        #expect(day.allEvents.isEmpty)
    }

    @Test func solarDayPolarDayAt89NInJune() throws {
        // June 21 — midnight sun at 89°N, Sun never dips below -0.833°
        let day = try SolarDay(date: LocalDate(year: 2026, month: 6, day: 21),
                               timeZone: utc, latitude: 89.0, longitude: 0.0)
        #expect(day.state == .polarDay)
        #expect(day.event(.sunrise) == nil)
        #expect(day.event(.sunset) == nil)
        #expect(day.allEvents.isEmpty)
    }

    @Test func solarDayMorningGoldenEndAfterSunrise() throws {
        let day = try makeSFDay()
        guard let rise = day.event(.sunrise), let goldEnd = day.event(.morningGoldenEnd) else {
            Issue.record("Expected sunrise and morning golden hour end for the San Francisco test date")
            return
        }
        #expect(rise < goldEnd)
    }

    @Test func nextEventReturnsNilWhenAllPast() throws {
        let day = try makeSFDay()
        guard let sunset = day.event(.sunset) else {
            Issue.record("Expected non-nil sunset for the San Francisco test date")
            return
        }
        // Use a far-future "now" — after all events for the day
        let farFuture = sunset.addingTimeInterval(24 * 3600)
        #expect(day.nextEvent(after: farFuture) == nil)
    }

    @Test func nextEventReturnsFirstUpcoming() throws {
        let day = try makeSFDay()
        // Use astronomical dawn as "now" — next should be nautical dawn
        guard let astro = day.event(.astronomicalDawn), let nautical = day.event(.nauticalDawn) else {
            Issue.record("Expected astronomical and nautical dawn for the San Francisco test date")
            return
        }
        let next = day.nextEvent(after: astro.addingTimeInterval(1))
        #expect(next?.instant == nautical)
        #expect(next?.kind == .nauticalDawn)
    }

    // MARK: - SolarEventKind displayName (approved Almanac copy)

    @Test func displayNameMapping() {
        let expected: [SolarEventKind: String] = [
            .astronomicalDawn: "Astronomical dawn",
            .nauticalDawn: "Nautical dawn",
            .civilDawn: "Civil dawn",
            .sunrise: "Sunrise",
            .morningGoldenEnd: "Golden hour ends",
            .eveningGoldenStart: "Golden hour begins",
            .sunset: "Sunset",
            .civilDusk: "Civil dusk",
            .nauticalDusk: "Nautical dusk",
            .astronomicalDusk: "Astronomical dusk"
        ]
        for (kind, name) in expected {
            #expect(kind.displayName == name)
        }
        #expect(SolarEventKind.allCases.count == expected.count)
    }
}
