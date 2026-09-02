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

    /// Local midnight of this date.
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
        let calendar = Self.calendar(in: timeZone)
        let start = try start(in: timeZone)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw LocalDateError.invalidDate
        }
        return next
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
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let date = calendar.date(from: components) else {
            throw LocalDateError.invalidDate
        }
        // `Calendar.date(from:)` silently wraps overflowing components
        // (Feb 30 → Mar 2); the round trip rejects such dates.
        let resolved = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day,
              resolved.hour == hour else {
            throw LocalDateError.invalidDate
        }
        return date
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
