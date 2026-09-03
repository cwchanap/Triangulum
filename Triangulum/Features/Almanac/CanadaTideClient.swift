//
//  CanadaTideClient.swift
//  Triangulum
//

import Foundation

/// Canadian Hydrographic Service (CHS) IWLS client.
///
/// Request/response contract verified 2026-09-01 and recorded in
/// `docs/almanac-tide-source-contracts.md`. High/low predictions come from
/// the `wlp-hilo` data series — the `/tide-tables` endpoints expose only
/// hierarchy metadata, not events. Heights are metres above the station's
/// chart datum and are kept as-is.
///
/// Per-request provider: no source cache (annual-source caching is JMA/HKO
/// only); the catalogue is fetched live through the injected session.
struct CanadaTideClient: TideProviderClient {
    let provider: TideProvider = .canadaCHS

    private let session: URLSession

    /// CHS catalogues omit time zones; until enriched by the service layer,
    /// windows are computed in UTC.
    private static let fallbackTimeZone = TimeZone(secondsFromGMT: 0)!

    private static let stationsURLString = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations"
    private static let dataURLString = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations"

    private static let iso8601UTC: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init(session: URLSession) {
        self.session = session
    }

    func loadStationCatalog() async throws -> [TideStation] {
        let data = try await Self.fetchData(from: URL(string: Self.stationsURLString)!, session: session)
        let rows = try Self.decode([CHSCatalogStation].self, from: data)
        return rows
            .filter { station in
                let series = Set(station.timeSeries.map(\.code))
                return series.contains("wlp") && series.contains("wlp-hilo")
            }
            .map { station in
                TideStation(
                    id: station.id,
                    provider: .canadaCHS,
                    providerStationCode: station.code,
                    name: station.officialName,
                    latitude: station.latitude,
                    longitude: station.longitude,
                    timeZoneIdentifier: nil,
                    datumLabel: "Chart Datum",
                    supportsHourlyCurve: true
                )
            }
    }

    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let timeZone = station.timeZone ?? Self.fallbackTimeZone
        let windowStart = try range.start.start(in: timeZone)
        let windowEnd = try range.endInclusive.endExclusive(in: timeZone)

        let hourlyURL = try Self.dataURL(
            station: station, series: "wlp", from: windowStart, until: windowEnd, withResolution: true
        )
        let hiloURL = try Self.dataURL(
            station: station, series: "wlp-hilo", from: windowStart, until: windowEnd, withResolution: false
        )

        // Both halves must validate before a week is returned; an
        // incomplete hourly/high-low pair is rejected outright.
        async let hourlyData = Self.fetchData(from: hourlyURL, session: session)
        async let hiloData = Self.fetchData(from: hiloURL, session: session)
        let hourlyRows = try Self.decode(
            [CHSDataPoint].self, from: try await hourlyData
        ).sorted { $0.eventDate < $1.eventDate }
        let hiloRows = try Self.decode(
            [CHSDataPoint].self, from: try await hiloData
        ).sorted { $0.eventDate < $1.eventDate }

        let hourlySamples = try hourlyRows.map { row -> TideSample in
            guard let instant = Self.iso8601UTC.date(from: row.eventDate) else {
                throw TideLoadError.invalidProviderResponse
            }
            return TideSample(instant: instant, heightMetres: row.value)
        }
        .filter { $0.instant >= windowStart && $0.instant < windowEnd }
        guard !hourlySamples.isEmpty else { throw TideLoadError.noPredictions }

        let eventValues = hiloRows.map(\.value)
        let eventKinds: [TideEventKind]
        if let alternating = TideClientSupport.alternatingEventKinds(values: eventValues) {
            eventKinds = alternating
        } else if eventValues.isEmpty {
            throw TideLoadError.noPredictions
        } else if eventValues.count == 1 {
            eventKinds = [TideClientSupport.singleEventKind(
                value: eventValues[0],
                hourlyMinimum: hourlySamples.map(\.heightMetres).min() ?? eventValues[0],
                hourlyMaximum: hourlySamples.map(\.heightMetres).max() ?? eventValues[0]
            )]
        } else {
            // Multiple non-alternating events cannot be labeled reliably;
            // never let the zip below silently drop rows.
            throw TideLoadError.invalidProviderResponse
        }
        let events = try zip(hiloRows, eventKinds).map { row, kind -> TideEvent in
            guard let instant = Self.iso8601UTC.date(from: row.eventDate) else {
                throw TideLoadError.invalidProviderResponse
            }
            return TideEvent(kind: kind, instant: instant, heightMetres: row.value)
        }
        .filter { $0.instant >= windowStart && $0.instant < windowEnd }

        return TideWeek(
            station: station,
            localDateRange: range,
            hourlySamples: hourlySamples,
            events: events,
            fetchedAt: Date(),
            sourceAttribution: provider.attribution
        )
    }

    // MARK: - Requests

    /// Contract URL forms:
    /// `…/stations/{stationId}/data?time-series-code=wlp&from={ISO8601Z}&to={ISO8601Z}&resolution=SIXTY_MINUTES`
    /// and the same without `resolution` for `wlp-hilo`.
    private static func dataURL(
        station: TideStation, series: String, from: Date, until: Date, withResolution: Bool
    ) throws -> URL {
        let fromText = iso8601UTC.string(from: from)
        let untilText = iso8601UTC.string(from: until)
        var urlString = "\(dataURLString)/\(station.id)/data?time-series-code=\(series)&from=\(fromText)&to=\(untilText)"
        if withResolution {
            urlString += "&resolution=SIXTY_MINUTES"
        }
        guard let url = URL(string: urlString) else {
            throw TideLoadError.invalidProviderResponse
        }
        return url
    }

    // MARK: - Transport and decoding

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

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TideLoadError.invalidProviderResponse
        }
    }

    // MARK: - Response shapes (contract: docs/almanac-tide-source-contracts.md)

    private struct CHSCatalogStation: Decodable {
        let code: String
        let id: String
        let officialName: String
        let latitude: Double
        let longitude: Double
        let timeSeries: [CHSTimeSeries]
    }

    private struct CHSTimeSeries: Decodable {
        let code: String
    }

    private struct CHSDataPoint: Decodable {
        let eventDate: String
        let value: Double
    }
}
