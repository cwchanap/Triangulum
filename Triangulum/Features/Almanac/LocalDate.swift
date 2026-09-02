//
//  LocalDate.swift
//  Triangulum
//

import Foundation

/// Error thrown when a `LocalDate` cannot be resolved to an instant in a
/// given time zone (e.g. a nonexistent calendar date such as February 30).
enum LocalDateError: Error {
    case invalidDate
}

/// A calendar date in some destination's local time, independent of any
/// instant. Conversion to/from `Date` always goes through an explicit
/// `TimeZone` so the same instant can map to different dates in different
/// destinations.
struct LocalDate: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The destination-local calendar date containing `instant`.
    init(_ instant: Date, in timeZone: TimeZone) {
        let calendar = Self.calendar(in: timeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }

    /// Local midnight of this date (01:00 on zones whose DST transition
    /// skips midnight, e.g. America/Santiago's spring-forward day).
    func start(in timeZone: TimeZone) throws -> Date {
        try date(atHour: 0, in: timeZone)
    }

    /// Local noon of this date. Built from calendar components so noon stays
    /// at wall time 12:00 even on DST transition days (`start + 12h` does not).
    func noon(in timeZone: TimeZone) throws -> Date {
        try date(atHour: 12, in: timeZone)
    }

    /// Local midnight of the following day. On DST days the interval to this
    /// instant can be 23 or 25 hours rather than 24.
    func endExclusive(in timeZone: TimeZone) throws -> Date {
        // Resolve the next civil day's own start: calendar day-arithmetic on
        // this day's start would preserve the wall hour of a DST-shifted
        // start (01:00 on a midnight-transition day), shortening the day.
        try adding(days: 1, in: timeZone).start(in: timeZone)
    }

    /// The date `days` calendar days away in the destination's time zone.
    func adding(days: Int, in timeZone: TimeZone) throws -> LocalDate {
        let calendar = Self.calendar(in: timeZone)
        let start = try start(in: timeZone)
        guard let shifted = calendar.date(byAdding: .day, value: days, to: start) else {
            throw LocalDateError.invalidDate
        }
        return LocalDate(shifted, in: timeZone)
    }

    /// The seven-day window starting at this date.
    func rollingSevenDays(in timeZone: TimeZone) throws -> LocalDateRange {
        LocalDateRange(start: self, endInclusive: try adding(days: 6, in: timeZone))
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(atHour hour: Int, in timeZone: TimeZone) throws -> Date {
        let calendar = Self.calendar(in: timeZone)
        // DST zones that move midnight (e.g. America/Santiago) skip the 00:00
        // wall time on their spring-forward day; Calendar resolves the gap to
        // 01:00 (and reports nil on some platforms), so try 01:00 as well.
        // Accept any resolved instant on the requested civil date — calendar
        // arithmetic silently wraps overflowing components (Feb 30 → Mar 2),
        // which still fails the same civil-date check below.
        let candidates = hour == 0 ? [0, 1] : [hour]
        for candidate in candidates {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = candidate
            guard let date = calendar.date(from: components) else { continue }
            let resolved = calendar.dateComponents([.year, .month, .day], from: date)
            if resolved.year == year, resolved.month == month, resolved.day == day {
                return date
            }
        }
        throw LocalDateError.invalidDate
    }
}

/// An inclusive range of destination-local dates, e.g. a seven-day forecast
/// window that may cross month and year boundaries.
struct LocalDateRange: Codable, Hashable {
    let start: LocalDate
    let endInclusive: LocalDate

    func dates(in timeZone: TimeZone) throws -> [LocalDate] {
        var result: [LocalDate] = [start]
        var current = start
        while current < endInclusive {
            current = try current.adding(days: 1, in: timeZone)
            result.append(current)
        }
        return result
    }
}
