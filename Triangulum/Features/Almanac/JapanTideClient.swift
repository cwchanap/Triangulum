//
//  JapanTideClient.swift
//  Triangulum
//

import Foundation

/// Japan Meteorological Agency (JMA) tide prediction client.
///
/// Request/response contract verified 2026-09-01 and recorded in
/// `docs/almanac-tide-source-contracts.md`. The catalogue is compiled
/// (`JapanTideStations`); predictions come from one annual fixed-width text
/// file per station/year, which carries both the hourly series and the
/// exact high/low events. Times are JST (Asia/Tokyo); heights are
/// centimetres above the tide-table datum and are normalized to metres.
///
/// Annual-source provider: fetched files are immutable, so this client owns
/// the `TideDiskCache` source cache (`TideSourceKind.annual`, keyed by
/// station/year) — the protocol surface has no cache and `TideService`
/// receives pre-constructed clients.
struct JapanTideClient: TideProviderClient {
    let provider: TideProvider = .japanJMA

    private let session: URLSession
    private let cache: TideDiskCache

    /// JMA stations are compiled with Asia/Tokyo; the fallback guards
    /// against a station reconstructed from a cache without a time zone.
    private static let fallbackTimeZone = TimeZone(secondsFromGMT: 0)!

    private static let annualBaseURLString =
        "https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt"

    /// Documented fixed-width record layout (1-based columns):
    /// 1–72 hourly heights (24 × 3-char cm), 73–78 YY MM DD (2 chars each,
    /// space-padded), 79–80 station symbol, 81–108 four highs and 109–136
    /// four lows as (4-char space-padded HHMM, 3-char cm); a missing event
    /// is time `9999` / height `999`.
    static let recordLength = 136

    init(session: URLSession, cache: TideDiskCache) {
        self.session = session
        self.cache = cache
    }

    func loadStationCatalog() async throws -> [TideStation] {
        JapanTideStations.all
    }

    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let timeZone = station.timeZone ?? Self.fallbackTimeZone
        let dates = try range.dates(in: timeZone)
        let years = Array(Set(dates.map(\.year))).sorted()

        // A range crossing New Year reads two annual source files.
        var recordsByDate: [LocalDate: AnnualRecord] = [:]
        for year in years {
            let records = try await annualRecords(station: station, year: year)
            for record in records where dates.contains(record.date) {
                recordsByDate[record.date] = record
            }
        }

        let windowStart = try range.start.start(in: timeZone)
        let windowEnd = try range.endInclusive.endExclusive(in: timeZone)

        var hourlySamples: [TideSample] = []
        var events: [TideEvent] = []
        for date in dates {
            guard let record = recordsByDate[date] else {
                // The requested window is not covered by the annual file.
                throw TideLoadError.noPredictions
            }
            for hour in 1...24 {
                guard let height = record.hourlyMetres[hour - 1] else { continue }
                let instant = try TideClientSupport.instant(for: date, hour: hour, in: timeZone)
                guard instant >= windowStart && instant < windowEnd else { continue }
                hourlySamples.append(TideSample(instant: instant, heightMetres: height))
            }
            for event in record.events {
                let instant = try TideClientSupport.instant(
                    minutes: event.minutes, on: date, in: timeZone
                )
                guard instant >= windowStart && instant < windowEnd else { continue }
                events.append(TideEvent(kind: event.kind, instant: instant, heightMetres: event.heightMetres))
            }
        }
        hourlySamples.sort { $0.instant < $1.instant }
        events.sort { $0.instant < $1.instant }
        guard !hourlySamples.isEmpty else { throw TideLoadError.noPredictions }

        return TideWeek(
            station: station,
            localDateRange: range,
            hourlySamples: hourlySamples,
            events: events,
            fetchedAt: Date(),
            sourceAttribution: provider.attribution
        )
    }

    // MARK: - Annual source (cached)

    private func annualRecords(station: TideStation, year: Int) async throws -> [AnnualRecord] {
        // Parse/validate before saving: a garbage 200 (captive portal, proxy
        // error page) must never poison the source cache until expiry.
        var freshlyFetched = false
        let data: Data
        if let cached = try await cache.loadSource(
            provider: .japanJMA, stationID: station.id, year: year, kind: .annual
        ) {
            data = cached
        } else {
            let url = try Self.annualURL(station: station, year: year)
            data = try await Self.fetchData(from: url, session: session)
            freshlyFetched = true
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TideLoadError.invalidProviderResponse
        }
        let records = try Self.parseAnnualFile(text, expectedStationSymbol: station.providerStationCode)
        if freshlyFetched {
            try await cache.saveSource(
                data, provider: .japanJMA, stationID: station.id, year: year, kind: .annual
            )
        }
        return records
    }

    /// `https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/{YEAR}/{STATION}.txt`
    private static func annualURL(station: TideStation, year: Int) throws -> URL {
        let urlString = "\(annualBaseURLString)/\(year)/\(station.providerStationCode).txt"
        guard let url = URL(string: urlString) else {
            throw TideLoadError.invalidProviderResponse
        }
        return url
    }

    // MARK: - Transport

    private static func fetchData(from url: URL, session: URLSession) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TideLoadError.networkUnavailable
            }
            return data
        } catch let error as TideLoadError {
            throw error
        } catch {
            throw TideLoadError.networkUnavailable
        }
    }

    // MARK: - Parsing

    private struct AnnualEvent {
        let minutes: Int
        let kind: TideEventKind
        let heightMetres: Double
    }

    private struct AnnualRecord {
        let date: LocalDate
        /// 24 entries, hour 1…24; `nil` marks a missing (999) value.
        let hourlyMetres: [Double?]
        let events: [AnnualEvent]
    }

    private static func parseAnnualFile(_ text: String, expectedStationSymbol symbol: String) throws -> [AnnualRecord] {
        // Splits on any newline grapheme (LF, CRLF, CR).
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var records: [AnnualRecord] = []
        for line in lines {
            var row = String(line)
            if row.hasSuffix("\r") { row = String(row.dropLast()) }
            guard !row.isEmpty else { continue } // trailing newline
            guard row.count == recordLength else {
                throw TideLoadError.invalidProviderResponse
            }
            let fields = Array(row)
            func field(_ range: Range<Int>) -> String {
                String(fields[range.lowerBound - 1..<range.upperBound - 1])
            }
            func fixedPoint(_ text: String) throws -> Double {
                guard let centimetres = Int(text.trimmingCharacters(in: .whitespaces)) else {
                    throw TideLoadError.invalidProviderResponse
                }
                return Double(centimetres) / 100.0
            }

            // Two-digit year on the audit-table century (2000s).
            guard let twoDigitYear = Int(field(73..<75).trimmingCharacters(in: .whitespaces)),
                  let month = Int(field(75..<77).trimmingCharacters(in: .whitespaces)),
                  let day = Int(field(77..<79).trimmingCharacters(in: .whitespaces)),
                  field(79..<81) == symbol else {
                throw TideLoadError.invalidProviderResponse
            }
            let year = 2000 + twoDigitYear

            var hourly: [Double?] = []
            for hour in 0..<24 {
                let text = field(hour * 3 + 1..<hour * 3 + 4)
                hourly.append(
                    text.trimmingCharacters(in: .whitespaces) == "999"
                        ? nil : try fixedPoint(text)
                )
            }

            var events: [AnnualEvent] = []
            for (offset, kind) in [(80, TideEventKind.high), (108, TideEventKind.low)] {
                for index in 0..<4 {
                    let base = offset + index * 7
                    let timeText = field(base + 1..<base + 5)
                    let heightText = field(base + 5..<base + 8)
                    let trimmedTime = timeText.trimmingCharacters(in: .whitespaces)
                    let trimmedHeight = heightText.trimmingCharacters(in: .whitespaces)
                    guard trimmedTime != "9999", trimmedHeight != "999" else { continue }
                    guard let hour = Int(timeText.prefix(2).trimmingCharacters(in: .whitespaces)),
                          let minute = Int(timeText.suffix(2).trimmingCharacters(in: .whitespaces)),
                          (0...23).contains(hour), (0...59).contains(minute) else {
                        throw TideLoadError.invalidProviderResponse
                    }
                    events.append(AnnualEvent(
                        minutes: hour * 60 + minute,
                        kind: kind,
                        heightMetres: try fixedPoint(heightText)
                    ))
                }
            }

            records.append(AnnualRecord(
                date: LocalDate(year: year, month: month, day: day),
                hourlyMetres: hourly,
                events: events
            ))
        }
        return records
    }
}
