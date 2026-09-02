//
//  CanadaTideClientTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

/// `CanadaTideClient` against the canonical CHS fixtures captured live on
/// 2026-09-01 (docs/almanac-tide-source-contracts.md).
struct CanadaTideClientTests {

    private static let stationsURL = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations"
    private static let hourlyURL = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/5cebf1de3d0f4a073c4bb943/data"
        + "?time-series-code=wlp&from=2026-03-01T00:00:00Z&to=2026-03-02T00:00:00Z&resolution=SIXTY_MINUTES"
    private static let hiloURL = "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/5cebf1de3d0f4a073c4bb943/data"
        + "?time-series-code=wlp-hilo&from=2026-03-01T00:00:00Z&to=2026-03-02T00:00:00Z"

    // MARK: - Helpers

    private struct CatalogRow: Codable {
        let code: String
        let id: String
        let officialName: String
        let latitude: Double
        let longitude: Double
        let timeSeries: [SeriesRow]

        struct SeriesRow: Codable { let code: String }
    }

    private static func utc(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return try #require(calendar.date(from: components))
    }

    private func fixture(_ path: String) throws -> Data {
        try AlmanacFixtureLoader.data(path)
    }

    private func makeSession(
        routes: [String: Result<(Int, Data?), Error>]
    ) -> (URLSession, RequestRecorder, () -> Void) {
        let recorder = RequestRecorder()
        let (session, cleanup) = TestURLSessionHelper.makeSession { request in
            let url = try #require(request.url)
            recorder.record(url)
            switch routes[url.absoluteString] {
            case .success(let (statusCode, data)):
                return TestURLSessionHelper.httpResponse(url: url, statusCode: statusCode, data: data)
            case .failure(let error):
                throw error
            case nil:
                return TestURLSessionHelper.httpResponse(url: url, statusCode: 404, data: Data("not found".utf8))
            }
        }
        return (session, recorder, cleanup)
    }

    /// Canonical catalogue plus one schema-faithful station that only
    /// observes (`wlo`) and so cannot provide predictions.
    private func catalogDataWithNonPredictingRow() throws -> Data {
        let fixture = try JSONDecoder().decode(
            [CatalogRow].self, from: AlmanacFixtureLoader.data("CHS/stations-vancouver.json")
        )
        let observer = CatalogRow(
            code: "99999",
            id: "5d5d5d5d5d5d5d5d5d5d5d5d",
            officialName: "Observer Only",
            latitude: 50.0,
            longitude: -125.0,
            timeSeries: [CatalogRow.SeriesRow(code: "wlo")]
        )
        return try JSONEncoder().encode([fixture[0], observer])
    }

    private func marchFirstRange() -> LocalDateRange {
        LocalDateRange(
            start: LocalDate(year: 2026, month: 3, day: 1),
            endInclusive: LocalDate(year: 2026, month: 3, day: 1)
        )
    }

    // MARK: - Catalogue

    @Test func catalogFetchesStationsEndpointAndFiltersToPredictionCapable() async throws {

        let (session, recorder, cleanup) = makeSession(routes: [
            Self.stationsURL: .success((200, try catalogDataWithNonPredictingRow()))
        ])
        defer { cleanup() }
        let client = CanadaTideClient(session: session)

        let stations = try await client.loadStationCatalog()

        #expect(recorder.urls == [URL(string: Self.stationsURL)!])
        #expect(stations.count == 1)
        let vancouver = try #require(stations.first)
        #expect(vancouver.id == "5cebf1de3d0f4a073c4bb943")
        #expect(vancouver.providerStationCode == "07735")
        #expect(vancouver.name == "Vancouver")
        #expect(vancouver.latitude == 49.2863)
        #expect(vancouver.longitude == -123.0997)
        #expect(vancouver.datumLabel == "Chart Datum")
        #expect(vancouver.supportsHourlyCurve)
        #expect(vancouver.provider == .canadaCHS)
    }

    // MARK: - Predictions

    @Test func loadPredictionsRequestsBothSeriesWithContractURLsAndParsesMetres() async throws {
        let stationsVancouverFixture = try fixture("CHS/stations-vancouver.json")
        let vancouverHourlyFixture = try fixture("CHS/vancouver-hourly.json")
        let vancouverHiloFixture = try fixture("CHS/vancouver-hilo.json")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.stationsURL: .success((200, stationsVancouverFixture)),
            Self.hourlyURL: .success((200, vancouverHourlyFixture)),
            Self.hiloURL: .success((200, vancouverHiloFixture))
        ])
        defer { cleanup() }
        let client = CanadaTideClient(session: session)

        let station = try #require(try await client.loadStationCatalog().first)
        let range = marchFirstRange()
        let week = try await client.loadPredictions(station: station, range: range)

        // Exact Task 1 capture URLs: wlp with resolution, wlp-hilo without.
        #expect(recorder.urls.contains(URL(string: Self.hourlyURL)!))
        #expect(recorder.urls.contains(URL(string: Self.hiloURL)!))

        // 25 fixture rows span 00:00Z…00:00Z inclusive; the window is
        // [Mar 1 00:00Z, Mar 2 00:00Z), so the trailing row is clipped.
        #expect(week.hourlySamples.count == 24)
        let expectedFirstSample = try Self.utc(2026, 3, 1, 0)
        #expect(week.hourlySamples.first?.instant == expectedFirstSample)
        #expect(abs(week.hourlySamples[0].heightMetres - 3.656) < 0.000001)
        #expect(abs(week.hourlySamples[6].heightMetres - 0.787) < 0.000001)
        let expectedLastSample = try Self.utc(2026, 3, 1, 23)
        #expect(week.hourlySamples.last?.instant == expectedLastSample)

        // wlp-hilo rows are unlabeled: low, high, low, high by value.
        #expect(week.events.count == 4)
        #expect(week.events.map(\.kind) == [.low, .high, .low, .high])
        let expectedEvent0 = try Self.utc(2026, 3, 1, 5, 44)
        let expectedEvent1 = try Self.utc(2026, 3, 1, 13, 3)
        let expectedEvent2 = try Self.utc(2026, 3, 1, 18, 41)
        let expectedEvent3 = try Self.utc(2026, 3, 1, 23, 32)
        #expect(week.events[0].instant == expectedEvent0)
        #expect(abs(week.events[0].heightMetres - 0.774) < 0.000001)
        #expect(week.events[1].instant == expectedEvent1)
        #expect(abs(week.events[1].heightMetres - 4.61) < 0.000001)
        #expect(week.events[2].instant == expectedEvent2)
        #expect(abs(week.events[2].heightMetres - 3.055) < 0.000001)
        #expect(week.events[3].instant == expectedEvent3)
        #expect(abs(week.events[3].heightMetres - 4.031) < 0.000001)

        // Chart-datum heights pass through untouched; attribution is the
        // provider's official name.
        #expect(week.station.datumLabel == "Chart Datum")
        #expect(week.sourceAttribution == TideProvider.canadaCHS.attribution)
        #expect(week.localDateRange == range)
        #expect(week.station == station)
    }

    @Test func loadPredictionsRejectsIncompletePairWhenHiloIsEmpty() async throws {
        let stationsVancouverFixture = try fixture("CHS/stations-vancouver.json")
        let vancouverHourlyFixture = try fixture("CHS/vancouver-hourly.json")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.stationsURL: .success((200, stationsVancouverFixture)),
            Self.hourlyURL: .success((200, vancouverHourlyFixture)),
            Self.hiloURL: .success((200, Data("[]".utf8)))
        ])
        defer { cleanup() }
        let client = CanadaTideClient(session: session)

        let station = try #require(try await client.loadStationCatalog().first)

        do {
            _ = try await client.loadPredictions(station: station, range: marchFirstRange())
            Issue.record("Expected an incomplete-pair rejection")
        } catch {
            #expect((error as? TideLoadError) == .noPredictions)
        }
        #expect(recorder.urls.contains(URL(string: Self.hiloURL)!))
    }

    @Test func loadPredictionsMapsHTTPFailuresToNetworkUnavailable() async throws {
        let stationsVancouverFixture = try fixture("CHS/stations-vancouver.json")
        let vancouverHourlyFixture = try fixture("CHS/vancouver-hourly.json")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.stationsURL: .success((200, stationsVancouverFixture)),
            Self.hourlyURL: .success((200, vancouverHourlyFixture)),
            Self.hiloURL: .success((500, nil))
        ])
        defer { cleanup() }
        let client = CanadaTideClient(session: session)

        let station = try #require(try await client.loadStationCatalog().first)

        do {
            _ = try await client.loadPredictions(station: station, range: marchFirstRange())
            Issue.record("Expected a network failure")
        } catch {
            #expect((error as? TideLoadError) == .networkUnavailable)
        }
    }
}
