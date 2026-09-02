//
//  TideProviderClient.swift
//  Triangulum
//

import Foundation

/// The network seam one official tide provider implements. Clients receive
/// their `URLSession` in `init` (matching `WeatherManager`); tests inject the
/// shared token-isolated test session, production uses `.shared` from
/// `AlmanacDependencies.live()`.
///
/// JMA and HKO are annual-source providers: their clients own the raw-source
/// caching through the shared `TideDiskCache` (`loadSource`/`saveSource`),
/// because the protocol surface has no cache and `TideService` receives
/// pre-constructed clients. CHS and NOAA are per-request providers and take
/// only a session.
protocol TideProviderClient {
    var provider: TideProvider { get }
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}

/// Small helpers shared by the concrete clients: wall-clock instant
/// construction (JMA/HKO hour 24 rolls to the next day's midnight) and
/// event-kind inference for sources that omit high/low labels (CHS
/// `wlp-hilo`, HKO HLT) — physically, tides alternate.
enum TideClientSupport {
    /// Local wall-clock instant for `hour` (1…24) on `date` in `timeZone`.
    /// Hour 24 is the following day's midnight, built through calendar
    /// components so it stays correct across DST.
    static func instant(for date: LocalDate, hour: Int, in timeZone: TimeZone) throws -> Date {
        let resolved = hour == 24 ? try date.adding(days: 1, in: timeZone) : date
        var components = DateComponents()
        components.year = resolved.year
        components.month = resolved.month
        components.day = resolved.day
        components.hour = hour % 24
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let instant = calendar.date(from: components) else {
            throw LocalDateError.invalidDate
        }
        return instant
    }

    /// Minute-of-day (HHMM) to wall-clock instant on `date`.
    static func instant(minutes: Int, on date: LocalDate, in timeZone: TimeZone) throws -> Date {
        try instant(for: date, hour: minutes / 60, in: timeZone)
            .addingTimeInterval(TimeInterval(minutes % 60) * 60)
    }

    /// Alternating high/low kinds for time-ordered unlabeled events. The
    /// first event's kind comes from comparing the first pair; needs at
    /// least two values.
    static func alternatingEventKinds(values: [Double]) -> [TideEventKind]? {
        guard let first = values.first, let second = values.dropFirst().first else { return nil }
        let evenKind: TideEventKind = first < second ? .low : .high
        return values.indices.map { index in
            index % 2 == 0 ? evenKind : (evenKind == .high ? .low : .high)
        }
    }

    /// Kind for a lone unlabeled event, judged against the hourly curve's
    /// range: nearer the day's maximum than its minimum means high water.
    static func singleEventKind(value: Double, hourlyMinimum: Double, hourlyMaximum: Double) -> TideEventKind {
        abs(value - hourlyMaximum) <= abs(value - hourlyMinimum) ? .high : .low
    }
}
