//
//  AlmanacLocalDateTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct AlmanacLocalDateTests {

    // MARK: - Instant → destination-local date

    @Test func sameInstantMapsToDifferentDestinationDates() {
        let instant = ISO8601DateFormatter().date(from: "2026-09-01T06:30:00Z")!
        let vancouver = TimeZone(identifier: "America/Vancouver")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!

        #expect(LocalDate(instant, in: vancouver) == .init(year: 2026, month: 8, day: 31))
        #expect(LocalDate(instant, in: tokyo) == .init(year: 2026, month: 9, day: 1))
    }

    // MARK: - DST day lengths

    @Test func vancouverDSTDayCanHave23Hours() throws {
        let zone = TimeZone(identifier: "America/Vancouver")!
        let day = LocalDate(year: 2026, month: 3, day: 8)
        #expect(try day.endExclusive(in: zone).timeIntervalSince(day.start(in: zone)) == 23 * 3600)
    }

    /// America/Vancouver is modeled as permanent UTC-7 from 2026-11-01 in recent
    /// tz databases (no 25-hour day), so the fall-back case uses Los Angeles,
    /// which still falls back to UTC-8 on 2026-11-01 in every tzdb vintage.
    @Test func losAngelesFallBackDayHas25Hours() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let day = LocalDate(year: 2026, month: 11, day: 1)
        #expect(try day.endExclusive(in: zone).timeIntervalSince(day.start(in: zone)) == 25 * 3600)
    }

    // MARK: - Noon construction (calendar components, not start + 12h)

    @Test func noonIsHour12OnSpringForwardDay() throws {
        let zone = TimeZone(identifier: "America/Vancouver")!
        let day = LocalDate(year: 2026, month: 3, day: 8)
        let noon = try day.noon(in: zone)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: noon) == 12)
        let dayStart = try day.start(in: zone)
        let dayEnd = try day.endExclusive(in: zone)
        #expect(noon >= dayStart)
        #expect(noon < dayEnd)
    }

    @Test func noonIsHour12OnFallBackDay() throws {
        // On 2026-11-01 in Los Angeles, start + 12 elapsed hours lands at
        // 11:00 wall time; a component-built noon must read 12:00.
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let day = LocalDate(year: 2026, month: 11, day: 1)
        let noon = try day.noon(in: zone)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: noon) == 12)
        let dayStart = try day.start(in: zone)
        let dayEnd = try day.endExclusive(in: zone)
        #expect(noon >= dayStart)
        #expect(noon < dayEnd)
    }

    // MARK: - Seven-day range across year boundary

    @Test func rollingSevenDaysCrossesYearBoundary() throws {
        let zone = TimeZone(identifier: "UTC")!
        let start = LocalDate(year: 2025, month: 12, day: 28)

        let range = try start.rollingSevenDays(in: zone)
        #expect(range.start == start)
        #expect(range.endInclusive == LocalDate(year: 2026, month: 1, day: 3))

        let dates = try range.dates(in: zone)
        #expect(dates.count == 7)
        #expect(dates.first == LocalDate(year: 2025, month: 12, day: 28))
        #expect(dates.last == LocalDate(year: 2026, month: 1, day: 3))
        #expect(dates == [start,
                          LocalDate(year: 2025, month: 12, day: 29),
                          LocalDate(year: 2025, month: 12, day: 30),
                          LocalDate(year: 2025, month: 12, day: 31),
                          LocalDate(year: 2026, month: 1, day: 1),
                          LocalDate(year: 2026, month: 1, day: 2),
                          LocalDate(year: 2026, month: 1, day: 3)])
    }

    @Test func addingDaysAcrossMonthAndYearBoundaries() throws {
        let zone = TimeZone(identifier: "UTC")!
        let jan31 = LocalDate(year: 2026, month: 1, day: 31)
        #expect(try jan31.adding(days: 1, in: zone) == LocalDate(year: 2026, month: 2, day: 1))
        #expect(try jan31.adding(days: 0, in: zone) == jan31)

        let dec31 = LocalDate(year: 2025, month: 12, day: 31)
        #expect(try dec31.adding(days: 1, in: zone) == LocalDate(year: 2026, month: 1, day: 1))
    }

    // MARK: - Invalid construction

    @Test func invalidCalendarDateThrowsInvalidDate() {
        let zone = TimeZone(identifier: "UTC")!
        #expect(throws: LocalDateError.invalidDate) {
            try LocalDate(year: 2026, month: 2, day: 30).start(in: zone)
        }
        #expect(throws: LocalDateError.invalidDate) {
            try LocalDate(year: 2026, month: 13, day: 1).noon(in: zone)
        }
        // The DST-midnight tolerance must never paper over genuinely invalid
        // dates, in a DST zone or not.
        let santiago = TimeZone(identifier: "America/Santiago")!
        #expect(throws: LocalDateError.invalidDate) {
            try LocalDate(year: 2026, month: 2, day: 30).start(in: santiago)
        }
    }

    // MARK: - DST transitions at midnight (America/Santiago)

    /// America/Santiago moves its clocks at 24:00: on 2026-09-06 the 00:00
    /// wall time is skipped (the day starts at 01:00) and on 2026-04-05 the
    /// 00:00 wall time repeats. `start` must resolve both days to an instant
    /// on the requested civil date instead of throwing.
    @Test func santiagoSpringForwardDayStartResolvesToTheRealFirstInstant() throws {
        let zone = TimeZone(identifier: "America/Santiago")!
        let day = LocalDate(year: 2026, month: 9, day: 6)

        let start = try day.start(in: zone)
        let noon = try day.noon(in: zone)
        let end = try day.endExclusive(in: zone)

        // 00:00 does not exist: the day starts at 01:00 local and is 23 hours
        // long, with noon 11 hours after the start.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: start) == 1)
        #expect(calendar.dateComponents([.year, .month, .day], from: start)
            == DateComponents(year: 2026, month: 9, day: 6))
        #expect(noon.timeIntervalSince(start) == 11 * 3600)
        #expect(end.timeIntervalSince(start) == 23 * 3600)
        #expect(calendar.dateComponents([.year, .month, .day], from: end)
            == DateComponents(year: 2026, month: 9, day: 7))

        // Rolling navigation across the transition day stays civil-date
        // correct for every day of the window.
        let range = try day.rollingSevenDays(in: zone)
        let dates = try range.dates(in: zone)
        #expect(dates.count == 7)
        #expect(dates.last == LocalDate(year: 2026, month: 9, day: 12))
    }

    @Test func santiagoFallBackDayStaysOnTheCorrectCivilDates() throws {
        let zone = TimeZone(identifier: "America/Santiago")!
        let day = LocalDate(year: 2026, month: 4, day: 5)

        let start = try day.start(in: zone)
        let noon = try day.noon(in: zone)
        let end = try day.endExclusive(in: zone)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: start) == 0)
        #expect(calendar.dateComponents([.year, .month, .day], from: start)
            == DateComponents(year: 2026, month: 4, day: 5))
        // Both the start and noon are on the requested civil day (noon stays
        // 12:00 wall time), and the day ends at the next day's midnight.
        #expect(calendar.component(.hour, from: noon) == 12)
        #expect(calendar.dateComponents([.year, .month, .day], from: noon)
            == DateComponents(year: 2026, month: 4, day: 5))
        #expect(calendar.dateComponents([.year, .month, .day], from: end)
            == DateComponents(year: 2026, month: 4, day: 6))

        // Foundation resolves the repeated midnight to its post-transition
        // occurrence, so the resolved day spans 24 h; every instant still
        // belongs to the intended civil dates.
        #expect(end > noon)
        let nextDay = try day.adding(days: 1, in: zone)
        #expect(nextDay == LocalDate(year: 2026, month: 4, day: 6))
    }

    // MARK: - Ordering and Codable

    @Test func orderingComparesByCalendarDate() {
        #expect(LocalDate(year: 2025, month: 12, day: 31) < LocalDate(year: 2026, month: 1, day: 1))
        #expect(LocalDate(year: 2026, month: 1, day: 2) < LocalDate(year: 2026, month: 3, day: 1))
        #expect(LocalDate(year: 2026, month: 3, day: 1) < LocalDate(year: 2026, month: 3, day: 2))
    }

    @Test func localDateCodableRoundTrip() throws {
        let original = LocalDate(year: 2026, month: 9, day: 1)
        let decoded = try JSONDecoder().decode(LocalDate.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
