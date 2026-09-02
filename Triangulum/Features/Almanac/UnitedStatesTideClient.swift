//
//  UnitedStatesTideClient.swift
//  Triangulum
//

import Foundation

/// NOAA CO-OPS tides and currents client.
///
/// Request/response contract verified 2026-09-01 and recorded in
/// `docs/almanac-tide-source-contracts.md`. Catalogue rows are filtered to
/// reference/harmonic stations (`type == "R"`, no `reference_id`) —
/// subordinate stations (`type == "S"`) inherit another station's harmonic
/// constants and cannot be predicted independently. Predictions are
/// requested twice (GMT/metric/MLLW): `interval=h` for the hourly curve and
/// `interval=hilo` for exact events; both responses must validate before a
/// week is returned. Heights are metres above MLLW, kept as-is.
struct UnitedStatesTideClient: TideProviderClient {
    let provider: TideProvider = .unitedStatesNOAA

    private let session: URLSession

    /// The mdapi catalogue carries no IANA time-zone names; until enriched
    /// by the service layer, GMT day bounds drive the request window (the
    /// prediction API itself is queried in GMT).
    private static let fallbackTimeZone = TimeZone(secondsFromGMT: 0)!

    private static let catalogURLString =
        "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions"
    private static let datagetterURLString = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

    /// `DateFormatter` is not thread-safe for concurrent use, and these
    /// value-type clients can be used concurrently, so formatters are
    /// built per `loadPredictions` call instead of shared statics.
    private static func makeGMTFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = dateFormat
        return formatter
    }

    init(session: URLSession) {
        self.session = session
    }

    func loadStationCatalog() async throws -> [TideStation] {
        let data = try await Self.fetchData(from: URL(string: Self.catalogURLString)!, session: session)
        let payload = try Self.decode(NOAAStationCatalog.self, from: data)
        return payload.stations
            .filter { station in
                // type "R" = reference/harmonic; "S" = subordinate. Rows in
                // this catalogue support hourly predictions by definition
                // (type=tidepredictions); valid coordinates are required for
                // nearest-station selection.
                station.type == "R"
                    && (station.referenceID ?? "").isEmpty
                    && (station.latitude ?? .nan).isFinite
                    && (station.longitude ?? .nan).isFinite
            }
            .map { station in
                TideStation(
                    id: station.id,
                    provider: .unitedStatesNOAA,
                    providerStationCode: station.id,
                    name: station.name,
                    latitude: station.latitude ?? .nan,
                    longitude: station.longitude ?? .nan,
                    timeZoneIdentifier: nil,
                    datumLabel: "MLLW",
                    supportsHourlyCurve: true
                )
            }
    }

    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let timeZone = station.timeZone ?? Self.fallbackTimeZone
        let gmtDayFormatter = Self.makeGMTFormatter(dateFormat: "yyyyMMdd")
        let predictionTimeFormatter = Self.makeGMTFormatter(dateFormat: "yyyy-MM-dd HH:mm")
        let beginDate = gmtDayFormatter.string(from: try range.start.start(in: timeZone))
        let endDate = gmtDayFormatter.string(from: try range.endInclusive.start(in: timeZone))

        let hourlyURL = try Self.predictionsURL(
            station: station, beginDate: beginDate, endDate: endDate, interval: "h"
        )
        let hiloURL = try Self.predictionsURL(
            station: station, beginDate: beginDate, endDate: endDate, interval: "hilo"
        )

        // Both intervals must validate before a week is returned.
        async let hourlyData = Self.fetchData(from: hourlyURL, session: session)
        async let hiloData = Self.fetchData(from: hiloURL, session: session)
        let hourlyRows = try await Self.predictions(hourlyData)
        let hiloRows = try await Self.predictions(hiloData)
        let windowStart = try range.start.start(in: timeZone)
        let windowEnd = try range.endInclusive.endExclusive(in: timeZone)

        let hourlySamples = try hourlyRows.map { row -> TideSample in
            guard let instant = predictionTimeFormatter.date(from: row.time) else {
                throw TideLoadError.invalidProviderResponse
            }
            return TideSample(instant: instant, heightMetres: row.height)
        }
        .sorted { $0.instant < $1.instant }
        .filter { $0.instant >= windowStart && $0.instant < windowEnd }
        guard !hourlySamples.isEmpty else { throw TideLoadError.noPredictions }

        let events = try hiloRows.map { row -> TideEvent in
            guard let instant = predictionTimeFormatter.date(from: row.time) else {
                throw TideLoadError.invalidProviderResponse
            }
            // The API types events as "H" / "L".
            let kind: TideEventKind
            switch row.type.uppercased() {
            case "H": kind = .high
            case "L": kind = .low
            default: throw TideLoadError.invalidProviderResponse
            }
            return TideEvent(kind: kind, instant: instant, heightMetres: row.height)
        }
        .sorted { $0.instant < $1.instant }
        .filter { $0.instant >= windowStart && $0.instant < windowEnd }
        guard !events.isEmpty else { throw TideLoadError.noPredictions }

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

    /// Contract URL form:
    /// `…/datagetter?product=predictions&application=Triangulum&station={id}&begin_date={YYYYMMDD}&end_date={YYYYMMDD}&datum=MLLW&time_zone=gmt&units=metric&format=json&interval={h|hilo}`
    private static func predictionsURL(
        station: TideStation, beginDate: String, endDate: String, interval: String
    ) throws -> URL {
        let urlString = "\(datagetterURLString)?product=predictions&application=Triangulum"
            + "&station=\(station.providerStationCode)&begin_date=\(beginDate)&end_date=\(endDate)"
            + "&datum=MLLW&time_zone=gmt&units=metric&format=json&interval=\(interval)"
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

    /// The datagetter answers `{"predictions": […]}` on success and
    /// `{"error": "…"}` when the window/station has no data; a missing or
    /// empty array is a clean no-predictions outcome.
    private static func predictions(_ data: Data) async throws -> [NOAAPrediction] {
        let payload = try decode(NOAAPredictionResponse.self, from: data)
        guard let rows = payload.predictions else { throw TideLoadError.noPredictions }
        return rows
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TideLoadError.invalidProviderResponse
        }
    }

    // MARK: - Response shapes (contract: docs/almanac-tide-source-contracts.md)

    private struct NOAAStationCatalog: Decodable {
        let stations: [NOAACatalogStation]
    }

    private struct NOAACatalogStation: Decodable {
        let id: String
        let name: String
        let type: String
        let latitude: Double?
        let longitude: Double?

        enum CodingKeys: String, CodingKey {
            case id, name, type
            case latitude = "lat"
            case longitude = "lng"
            case referenceID = "reference_id"
        }

        let referenceID: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            type = try container.decode(String.self, forKey: .type)
            latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
            longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
            referenceID = try container.decodeIfPresent(String.self, forKey: .referenceID)
        }
    }

    private struct NOAAPredictionResponse: Decodable {
        let predictions: [NOAAPrediction]?
    }

    private struct NOAAPrediction: Decodable {
        let time: String
        let height: Double
        let type: String

        enum CodingKeys: String, CodingKey {
            case time = "t"
            case height = "v"
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode(String.self, forKey: .time)
            // Heights arrive as JSON strings ("1.541"); fall back to numbers defensively.
            if let text = try? container.decode(String.self, forKey: .height),
               let parsed = Double(text) {
                height = parsed
            } else {
                height = try container.decode(Double.self, forKey: .height)
            }
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        }
    }
}
