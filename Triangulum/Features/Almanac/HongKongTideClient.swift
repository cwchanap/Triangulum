//
//  HongKongTideClient.swift
//  Triangulum
//

import Foundation

/// Hong Kong Observatory (HKO) tide prediction client.
///
/// Request/response contract verified 2026-09-01 and recorded in
/// `docs/almanac-tide-source-contracts.md`. The catalogue is compiled
/// (`HongKongTideStations`, the active HHOT ∩ HLT intersection); predictions
/// come from two annual CSVs per station/year — `HHOT` (hourly heights) and
/// `HLT` (high/low times and heights). Both must parse for the requested
/// dates before a week is returned. Files carry a UTF-8 BOM and may use
/// CRLF endings and quoted fields. Times are HKT (Asia/Hong_Kong); heights
/// are metres above chart datum, kept as-is.
///
/// Annual-source provider: fetched files are immutable, so this client owns
/// the `TideDiskCache` source cache (`TideSourceKind.hourly` / `.hilo`,
/// keyed by station/year).
struct HongKongTideClient: TideProviderClient {
    let provider: TideProvider = .hongKongHKO

    private let session: URLSession
    private let cache: TideDiskCache

    /// HKO stations are compiled with Asia/Hong_Kong; the fallback guards
    /// against a station reconstructed from a cache without a time zone.
    private static let fallbackTimeZone = TimeZone(secondsFromGMT: 0)!

    private static let opendataURLString =
        "https://data.weather.gov.hk/weatherAPI/opendata/opendata.php"

    init(session: URLSession, cache: TideDiskCache) {
        self.session = session
        self.cache = cache
    }

    func loadStationCatalog() async throws -> [TideStation] {
        HongKongTideStations.all
    }

    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let timeZone = station.timeZone ?? Self.fallbackTimeZone
        let dates = try range.dates(in: timeZone)
        let years = Array(Set(dates.map(\.year))).sorted()

        // Both sources are required: hourly heights and high/low events.
        // A range crossing New Year may read two years per source kind.
        let sources = try await annualSources(station: station, years: years)
        let hourlyByDate = sources.hourlyByDate.filter { dates.contains($0.key) }
        let hiloByDate = sources.hiloByDate.filter { dates.contains($0.key) }

        let windowStart = try range.start.start(in: timeZone)
        let windowEnd = try range.endInclusive.endExclusive(in: timeZone)

        var hourlySamples: [TideSample] = []
        var events: [TideEvent] = []
        for date in dates {
            // Missing row for a requested date in either source rejects the
            // whole range.
            guard let heights = hourlyByDate[date], let pairs = hiloByDate[date] else {
                throw TideLoadError.noPredictions
            }
            for hour in 1...24 {
                guard let height = heights[hour - 1] else { continue }
                let instant = try TideClientSupport.instant(for: date, hour: hour, in: timeZone)
                guard instant >= windowStart && instant < windowEnd else { continue }
                hourlySamples.append(TideSample(instant: instant, heightMetres: height))
            }

            let eventKinds = try Self.eventKinds(pairs: pairs, hourlyHeights: heights)
            for (pair, kind) in zip(pairs, eventKinds) {
                let instant = try TideClientSupport.instant(
                    minutes: pair.minutes, on: date, in: timeZone
                )
                guard instant >= windowStart && instant < windowEnd else { continue }
                events.append(TideEvent(kind: kind, instant: instant, heightMetres: pair.heightMetres))
            }
        }
        hourlySamples.sort { $0.instant < $1.instant }
        events.sort { $0.instant < $1.instant }
        guard !hourlySamples.isEmpty, !events.isEmpty else { throw TideLoadError.noPredictions }

        return TideWeek(
            station: station,
            localDateRange: range,
            hourlySamples: hourlySamples,
            events: events,
            fetchedAt: Date(),
            sourceAttribution: provider.attribution
        )
    }

    // MARK: - Annual sources (cached)

    private struct HLTPair {
        let minutes: Int
        let heightMetres: Double
    }

    private struct AnnualSources {
        let hourlyByDate: [LocalDate: [Double?]]
        let hiloByDate: [LocalDate: [HLTPair]]
    }

    private func annualSources(
        station: TideStation, years: [Int]
    ) async throws -> AnnualSources {
        var hourlyByDate: [LocalDate: [Double?]] = [:]
        var hiloByDate: [LocalDate: [HLTPair]] = [:]
        for year in years {
            let hourlyText = try await annualSource(
                station: station, year: year, kind: .hourly, dataType: "HHOT"
            )
            for (date, heights) in try Self.parseHourlyCSV(hourlyText, year: year) {
                hourlyByDate[date] = heights
            }

            let hiloText = try await annualSource(
                station: station, year: year, kind: .hilo, dataType: "HLT"
            )
            for (date, pairs) in try Self.parseHighLowCSV(hiloText, year: year) {
                hiloByDate[date] = pairs
            }
        }
        return AnnualSources(hourlyByDate: hourlyByDate, hiloByDate: hiloByDate)
    }

    private func annualSource(
        station: TideStation, year: Int, kind: TideSourceKind, dataType: String
    ) async throws -> String {
        let data: Data
        if let cached = try await cache.loadSource(
            provider: .hongKongHKO, stationID: station.id, year: year, kind: kind
        ) {
            data = cached
        } else {
            let url = try Self.opendataURL(dataType: dataType, station: station.providerStationCode, year: year)
            data = try await Self.fetchData(from: url, session: session)
            try await cache.saveSource(
                data, provider: .hongKongHKO, stationID: station.id, year: year, kind: kind
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TideLoadError.invalidProviderResponse
        }
        return text
    }

    /// `…/opendata.php?dataType={HHOT|HLT}&station={CODE}&year={YEAR}&rformat=csv`
    private static func opendataURL(dataType: String, station: String, year: Int) throws -> URL {
        let urlString = "\(opendataURLString)?dataType=\(dataType)&station=\(station)&year=\(year)&rformat=csv"
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

    // MARK: - CSV parsing (BOM, CRLF, quoted commas)

    /// Minimal RFC-4180-style row splitting: tolerates a UTF-8 BOM, CRLF or
    /// LF endings, and quoted fields (commas and newlines inside quotes are
    /// preserved; `""` escapes a quote).
    private static func csvRows(_ text: String) -> [[String]] {
        var body = Substring(text)
        if body.hasPrefix("\u{feff}") { body = body.dropFirst() }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if inQuotes {
                if character == "\"" {
                    let next = body.index(after: index)
                    if next < body.endIndex, body[next] == "\"" {
                        field.append("\"")
                        index = body.index(after: next)
                    } else {
                        inQuotes = false
                        index = next
                    }
                } else {
                    field.append(character)
                    index = body.index(after: index)
                }
            } else if character == "\"" {
                inQuotes = true
                index = body.index(after: index)
            } else if character == "," {
                row.append(field)
                field = ""
                index = body.index(after: index)
            } else if character.isNewline {
                // Note: "\r\n" is a single Character grapheme, so compare
                // with isNewline rather than equality against "\r"/"\n".
                let next = body.index(after: index)
                if character == "\r", next < body.endIndex, body[next] == "\n" {
                    index = next
                }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
                index = body.index(after: index)
            } else {
                field.append(character)
                index = body.index(after: index)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// HHOT: header `MM,DD,01,…,24`, one row per day with 24 hourly heights
    /// in metres (empty cells become missing values).
    private static func parseHourlyCSV(_ text: String, year: Int) throws -> [LocalDate: [Double?]] {
        var byDate: [LocalDate: [Double?]] = [:]
        for row in csvRows(text) {
            guard row.count >= 2, Int(row[0].trimmingCharacters(in: .whitespaces)) != nil,
                  Int(row[1].trimmingCharacters(in: .whitespaces)) != nil else {
                continue // header or stray non-data row
            }
            guard row.count == 26,
                  let month = Int(row[0].trimmingCharacters(in: .whitespaces)),
                  let day = Int(row[1].trimmingCharacters(in: .whitespaces)) else {
                throw TideLoadError.invalidProviderResponse
            }
            let heights = (2..<26).map { column -> Double? in
                let cell = row[column].trimmingCharacters(in: .whitespaces)
                return cell.isEmpty ? nil : Double(cell)
            }
            byDate[LocalDate(year: year, month: month, day: day)] = heights
        }
        // A source with no data rows at all is malformed, not merely empty.
        guard !byDate.isEmpty else { throw TideLoadError.invalidProviderResponse }
        return byDate
    }

    /// HLT: header `Month,Date,Time,Height(m)×4`, one row per day with up to
    /// four `Time,Height(m)` pairs (HHMM, metres); empty trailing pairs are
    /// common (2- and 3-event days).
    private static func parseHighLowCSV(_ text: String, year: Int) throws -> [LocalDate: [HLTPair]] {
        var byDate: [LocalDate: [HLTPair]] = [:]
        for row in csvRows(text) {
            guard row.count >= 2, Int(row[0].trimmingCharacters(in: .whitespaces)) != nil,
                  Int(row[1].trimmingCharacters(in: .whitespaces)) != nil else {
                continue // header or stray non-data row
            }
            guard row.count == 10,
                  let month = Int(row[0].trimmingCharacters(in: .whitespaces)),
                  let day = Int(row[1].trimmingCharacters(in: .whitespaces)) else {
                throw TideLoadError.invalidProviderResponse
            }
            var pairs: [HLTPair] = []
            for pairIndex in 0..<4 {
                let timeCell = row[2 + pairIndex * 2].trimmingCharacters(in: .whitespaces)
                let heightCell = row[3 + pairIndex * 2].trimmingCharacters(in: .whitespaces)
                guard !timeCell.isEmpty, !heightCell.isEmpty else { break }
                // HHMM digits: 0116 is 01:16, i.e. 76 minutes, not 116.
                guard timeCell.count == 4,
                      let hour = Int(timeCell.prefix(2)),
                      let minute = Int(timeCell.suffix(2)),
                      (0...23).contains(hour), (0...59).contains(minute),
                      let height = Double(heightCell) else {
                    throw TideLoadError.invalidProviderResponse
                }
                pairs.append(HLTPair(minutes: hour * 60 + minute, heightMetres: height))
            }
            byDate[LocalDate(year: year, month: month, day: day)] = pairs
        }
        // A source with no data rows at all is malformed, not merely empty.
        guard !byDate.isEmpty else { throw TideLoadError.invalidProviderResponse }
        return byDate
    }

    // MARK: - Event kinds

    /// HLT rows are unlabeled; tides alternate, so kinds come from the
    /// day's first pair. A lone event is judged against the day's hourly
    /// range.
    private static func eventKinds(pairs: [HLTPair], hourlyHeights: [Double?]) throws -> [TideEventKind] {
        let values = pairs.map(\.heightMetres)
        if let alternating = TideClientSupport.alternatingEventKinds(values: values) {
            return alternating
        }
        if let only = values.first {
            let known = hourlyHeights.compactMap { $0 }
            return [TideClientSupport.singleEventKind(
                value: only,
                hourlyMinimum: known.min() ?? only,
                hourlyMaximum: known.max() ?? only
            )]
        }
        throw TideLoadError.invalidProviderResponse
    }
}
