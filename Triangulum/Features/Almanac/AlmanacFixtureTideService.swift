//
//  AlmanacFixtureTideService.swift
//

import Foundation

/// Deterministic tide data for UI tests (selected by `-ui-testing` alone).
///
/// The checked-in prediction fixtures live in the test bundle and cannot be
/// read from the app target, so this service generates a small fixed
/// Vancouver week in code instead — same determinism, no resource plumbing.
/// `fetchedAt` is pinned to `fixedNow`, so freshness never lapses mid-test.
struct AlmanacFixtureTideService: TideServing {

    /// 2026-09-15 12:00 Vancouver time (PDT). September 2026 per the tzdb
    /// note: Vancouver becomes permanent UTC-7 from 2026-11-01 on this
    /// machine, so fixture dates stay clear of that transition.
    static let fixedNow = fixedDate(2026, 9, 15, 12)

    static let station = TideStation(
        id: "CHS-07385",
        provider: .canadaCHS,
        providerStationCode: "07385",
        name: "Vancouver Point Atkinson",
        latitude: 49.3299,
        longitude: -123.2594,
        timeZoneIdentifier: "America/Vancouver",
        datumLabel: "Chart Datum",
        supportsHourlyCurve: true
    )

    private static let timeZone = TimeZone(identifier: "America/Vancouver")!

    func resolveStation(for location: AlmanacLocation, override: TideStationOverride?) async throws -> TideStationContext {
        TideStationContext(
            coverage: .provider(.canadaCHS),
            selected: Self.station,
            nearbyStations: [],
            distanceMetres: 0,
            timeZone: Self.timeZone
        )
    }

    func cachedDay(station: TideStation, date: LocalDate) async throws -> TideDaySnapshot? {
        TideDaySnapshot(day: Self.day(for: date), isStale: false)
    }

    func refreshRange(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let dates = try range.dates(in: Self.timeZone)
        return TideWeek(
            station: station,
            localDateRange: range,
            hourlySamples: dates.flatMap { Self.day(for: $0).hourlySamples },
            events: dates.flatMap { Self.day(for: $0).events },
            fetchedAt: Self.fixedNow,
            sourceAttribution: "Fixture (Canadian Hydrographic Service)"
        )
    }

    /// One deterministic day: semi-diurnal highs at 06:00/18:00, lows at
    /// 00:00/12:00, hourly samples between.
    static func day(for date: LocalDate) -> TideDay {
        let samples: [TideSample] = (0..<24).map { hour in
            TideSample(
                instant: fixedDate(date.year, date.month, date.day, hour),
                heightMetres: 2.5 + 1.5 * sin(Double(hour) / 24 * 2 * .pi)
            )
        }
        let events: [TideEvent] = [
            TideEvent(kind: .low, instant: fixedDate(date.year, date.month, date.day, 0), heightMetres: 1.0),
            TideEvent(kind: .high, instant: fixedDate(date.year, date.month, date.day, 6), heightMetres: 4.0),
            TideEvent(kind: .low, instant: fixedDate(date.year, date.month, date.day, 12), heightMetres: 1.0),
            TideEvent(kind: .high, instant: fixedDate(date.year, date.month, date.day, 18), heightMetres: 4.0)
        ]
        return TideDay(
            station: station,
            localDate: date,
            hourlySamples: samples,
            events: events,
            fetchedAt: fixedNow,
            sourceAttribution: "Fixture (Canadian Hydrographic Service)"
        )
    }

    private static func fixedDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
