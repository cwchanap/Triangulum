//
//  UnitedStatesTideClientTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

/// `UnitedStatesTideClient` against the canonical NOAA fixtures captured
/// live on 2026-09-01 (docs/almanac-tide-source-contracts.md).
struct UnitedStatesTideClientTests {

    private static let catalogURL =
        "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions"
    private static let hourlyURL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        + "?product=predictions&application=Triangulum&station=9414290"
        + "&begin_date=20260301&end_date=20260302&datum=MLLW&time_zone=gmt&units=metric&format=json&interval=h"
    private static let hiloURL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        + "?product=predictions&application=Triangulum&station=9414290"
        + "&begin_date=20260301&end_date=20260302&datum=MLLW&time_zone=gmt&units=metric&format=json&interval=hilo"

    // MARK: - Helpers

    /// Only the catalogue fields the client consumes; good enough to append
    /// schema-faithful test rows and re-serve the fixture.
    private struct CatalogRow: Codable {
        let id: String
        let name: String
        let type: String
        let lat: Double?
        let lng: Double?
        let referenceID: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case id, name, type, lat, lng
            case referenceID = "reference_id"
            case state
        }
    }

    private struct Catalog: Codable {
        let stations: [CatalogRow]
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

    /// Canonical fixture rows plus one schema-faithful, non-U.S. subordinate
    /// row (kept in-test so the canonical fixture stays slim).
    private func catalogWithNonUSSubordinateRow() throws -> Data {
        var catalog = try JSONDecoder().decode(
            Catalog.self, from: AlmanacFixtureLoader.data("NOAA/stations-selection.json")
        )
        let subordinate = CatalogRow(
            id: "9999999",
            name: "FOREIGN HARBOUR (Test)",
            type: "S",
            lat: 14.5,
            lng: -61.0,
            referenceID: "9414290",
            state: ""
        )
        return try JSONEncoder().encode(Catalog(stations: catalog.stations + [subordinate]))
    }

    /// Canonical fixture rows plus one schema-faithful NON-U.S. type "R"
    /// row: valid coordinates, empty `reference_id`, hourly-capable (the
    /// catalogue is `type=tidepredictions`), but no U.S. jurisdiction
    /// (`state` is empty) — it must be excluded by the jurisdiction filter.
    private func catalogWithForeignReferenceRow() throws -> Data {
        var catalog = try JSONDecoder().decode(
            Catalog.self, from: AlmanacFixtureLoader.data("NOAA/stations-selection.json")
        )
        let foreign = CatalogRow(
            id: "8888888",
            name: "FOREIGN PORT (Test)",
            type: "R",
            lat: 18.55,
            lng: -72.35,
            referenceID: nil,
            state: ""
        )
        return try JSONEncoder().encode(Catalog(stations: catalog.stations + [foreign]))
    }

    private func sanFrancisco(from client: UnitedStatesTideClient) async throws -> TideStation {
        let stations = try await client.loadStationCatalog()
        return try #require(stations.first { $0.id == "9414290" })
    }

    private func marchRange() -> LocalDateRange {
        LocalDateRange(
            start: LocalDate(year: 2026, month: 3, day: 1),
            endInclusive: LocalDate(year: 2026, month: 3, day: 2)
        )
    }

    // MARK: - Catalogue

    @Test func catalogKeepsReferenceRowsAndExcludesSubordinates() async throws {

        let (session, recorder, cleanup) = makeSession(routes: [
            Self.catalogURL: .success((200, try catalogWithNonUSSubordinateRow()))
        ])
        defer { cleanup() }
        let client = UnitedStatesTideClient(session: session)

        let stations = try await client.loadStationCatalog()

        #expect(recorder.urls == [URL(string: Self.catalogURL)!])
        // The type "R" reference row survives; the added non-U.S. type "S"
        // subordinate row (and the fixture's own "S" row) are excluded.
        #expect(stations.count == 1)
        let sanFrancisco = try #require(stations.first)
        #expect(sanFrancisco.id == "9414290")
        #expect(sanFrancisco.providerStationCode == "9414290")
        #expect(sanFrancisco.name == "SAN FRANCISCO (Golden Gate)")
        #expect(abs(sanFrancisco.latitude - 37.80630555555555) < 0.0000001)
        #expect(abs(sanFrancisco.longitude - (-122.4658888888889)) < 0.0000001)
        #expect(sanFrancisco.datumLabel == "MLLW")
        #expect(sanFrancisco.supportsHourlyCurve)
        #expect(sanFrancisco.provider == .unitedStatesNOAA)
    }

    /// Regression (C5): a type "R" row that would pass every other filter
    /// (reference/harmonic, no reference_id, valid coordinates, hourly
    /// capable) must still be excluded when it has no valid U.S.
    /// jurisdiction — non-U.S. rows carry no `state`.
    @Test func catalogExcludesSchemaFaithfulForeignTypeRRows() async throws {
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.catalogURL: .success((200, try catalogWithForeignReferenceRow()))
        ])
        defer { cleanup() }
        let client = UnitedStatesTideClient(session: session)

        let stations = try await client.loadStationCatalog()

        #expect(recorder.urls == [URL(string: Self.catalogURL)!])
        #expect(stations.count == 1)
        #expect(stations.first?.id == "9414290")
    }

    // MARK: - Predictions

    @Test func loadPredictionsUsesGMTMetricMLLWAndBothIntervals() async throws {
        let stationsSelectionFixture = try fixture("NOAA/stations-selection.json")
        let sanFranciscoHourlyFixture = try fixture("NOAA/san-francisco-hourly.json")
        let sanFranciscoHiloFixture = try fixture("NOAA/san-francisco-hilo.json")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.catalogURL: .success((200, stationsSelectionFixture)),
            Self.hourlyURL: .success((200, sanFranciscoHourlyFixture)),
            Self.hiloURL: .success((200, sanFranciscoHiloFixture))
        ])
        defer { cleanup() }
        let client = UnitedStatesTideClient(session: session)
        let station = try await sanFrancisco(from: client)

        let range = marchRange()
        let week = try await client.loadPredictions(station: station, range: range)

        // Exact Task 1 capture URLs: GMT day bounds, metric, MLLW, both
        // intervals requested.
        #expect(recorder.urls.contains(URL(string: Self.hourlyURL)!))
        #expect(recorder.urls.contains(URL(string: Self.hiloURL)!))

        // 48 hourly rows for the two GMT calendar days, metres above MLLW.
        #expect(week.hourlySamples.count == 48)
        let expectedFirst = try Self.utc(2026, 3, 1, 0)
        let expectedDay1End = try Self.utc(2026, 3, 1, 23)
        let expectedLast = try Self.utc(2026, 3, 2, 23)
        #expect(week.hourlySamples[0].instant == expectedFirst)
        #expect(abs(week.hourlySamples[0].heightMetres - (-0.223)) < 0.000001)
        #expect(week.hourlySamples[23].instant == expectedDay1End)
        #expect(week.hourlySamples[47].instant == expectedLast)

        // Typed high/low events, in order.
        #expect(week.events.count == 7)
        #expect(week.events.map(\.kind) == [.high, .low, .high, .low, .high, .low, .high])
        let expectedEvent0 = try Self.utc(2026, 3, 1, 6, 32)
        let expectedEvent3 = try Self.utc(2026, 3, 2, 0, 9)
        let expectedEvent6 = try Self.utc(2026, 3, 2, 18, 19)
        #expect(week.events[0].instant == expectedEvent0)
        #expect(abs(week.events[0].heightMetres - 1.541) < 0.000001)
        #expect(week.events[3].instant == expectedEvent3)
        #expect(abs(week.events[3].heightMetres - (-0.233)) < 0.000001)
        #expect(week.events[6].instant == expectedEvent6)

        #expect(week.station.datumLabel == "MLLW")
        #expect(week.sourceAttribution == TideProvider.unitedStatesNOAA.attribution)
        #expect(week.localDateRange == range)
    }

    @Test func loadPredictionsRejectsWhenEitherHalfFails() async throws {
        // datagetter answers {"error": …} when a window has no data: the
        // hilo half is then empty and the pair is incomplete.
        let stationsSelectionFixture = try fixture("NOAA/stations-selection.json")
        let sanFranciscoHourlyFixture = try fixture("NOAA/san-francisco-hourly.json")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.catalogURL: .success((200, stationsSelectionFixture)),
            Self.hourlyURL: .success((200, sanFranciscoHourlyFixture)),
            Self.hiloURL: .success((200, Data("{\"error\":\"No data was found.\"}".utf8)))
        ])
        defer { cleanup() }
        let client = UnitedStatesTideClient(session: session)
        let station = try await sanFrancisco(from: client)

        do {
            _ = try await client.loadPredictions(station: station, range: marchRange())
            Issue.record("Expected an incomplete-pair rejection")
        } catch {
            #expect((error as? TideLoadError) == .noPredictions)
        }
        #expect(recorder.urls.contains(URL(string: Self.hiloURL)!))
    }

    @Test func loadPredictionsMapsHTTPFailuresToNetworkUnavailable() async throws {
        let stationsSelectionFixture = try fixture("NOAA/stations-selection.json")
        let sanFranciscoHiloFixture = try fixture("NOAA/san-francisco-hilo.json")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.catalogURL: .success((200, stationsSelectionFixture)),
            Self.hourlyURL: .success((500, nil)),
            Self.hiloURL: .success((200, sanFranciscoHiloFixture))
        ])
        defer { cleanup() }
        let client = UnitedStatesTideClient(session: session)
        let station = try await sanFrancisco(from: client)

        do {
            _ = try await client.loadPredictions(station: station, range: marchRange())
            Issue.record("Expected a network failure")
        } catch {
            #expect((error as? TideLoadError) == .networkUnavailable)
        }
    }

    /// Regression (C2): the inclusive GMT end date must cover the range's
    /// final instant. A range ending 2026-09-07 in Los Angeles ends at
    /// 2026-09-08 00:00 PDT = 07:00Z — the final local evening falls on the
    /// NEXT GMT day, so the request must carry end_date=20260908 (the old
    /// derivation from the last local day's start sent 20260907 and dropped
    /// that evening's predictions).
    @Test func loadPredictionsEndDateCoversTheFinalLocalEveningForWesternStations() async throws {
        let (session, recorder, cleanup) = makeSession(routes: [:])
        defer { cleanup() }
        let client = UnitedStatesTideClient(session: session)
        let losAngeles = TideStation(
            id: "9414290",
            provider: .unitedStatesNOAA,
            providerStationCode: "9414290",
            name: "SAN FRANCISCO (Golden Gate)",
            latitude: 37.80630555555555,
            longitude: -122.4658888888889,
            timeZoneIdentifier: "America/Los_Angeles",
            datumLabel: "MLLW",
            supportsHourlyCurve: true
        )
        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 9, day: 1),
            endInclusive: LocalDate(year: 2026, month: 9, day: 7)
        )

        do {
            _ = try await client.loadPredictions(station: losAngeles, range: range)
            Issue.record("Expected the unrouted datagetter request to fail")
        } catch {
            // The 404 route below surfaces as .networkUnavailable; the URL
            // assertion is what this test checks.
            #expect((error as? TideLoadError) == .networkUnavailable)
        }

        let datagetterURLs = recorder.urls.map(\.absoluteString)
            .filter { $0.contains("datagetter") }
        #expect(datagetterURLs.count == 2)
        for url in datagetterURLs {
            #expect(url.contains("begin_date=20260901"), "GMT begin date must start the range")
            #expect(url.contains("end_date=20260908"), "GMT end date must cover the final local evening")
        }
    }
}
