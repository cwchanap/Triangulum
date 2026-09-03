//
//  HongKongTideClientTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

/// `HongKongTideClient` + compiled `HongKongTideStations` against the
/// canonical HKO fixtures captured live on 2026-09-01
/// (docs/almanac-tide-source-contracts.md).
struct HongKongTideClientTests {

    private static func opendataURL(dataType: String, station: String, year: Int) -> String {
        "https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=\(dataType)&station=\(station)&year=\(year)&rformat=csv"
    }

    private static var hourlyURL2026: String { opendataURL(dataType: "HHOT", station: "TPK", year: 2026) }
    private static var hiloURL2026: String { opendataURL(dataType: "HLT", station: "TPK", year: 2026) }
    private static var hourlyURL2027: String { opendataURL(dataType: "HHOT", station: "TPK", year: 2027) }
    private static var hiloURL2027: String { opendataURL(dataType: "HLT", station: "TPK", year: 2027) }

    private static let hkt = TimeZone(identifier: "Asia/Hong_Kong")!

    // MARK: - Helpers

    private func makeCache() throws -> TideDiskCache {
        TideDiskCache(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("almanac-hko-tests-\(UUID().uuidString)")
        )
    }

    private func hkt(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.hkt
        return try #require(calendar.date(from: components))
    }

    private func fixture(_ path: String) throws -> Data {
        try AlmanacFixtureLoader.data(path)
    }

    private func makeSession(routes: [String: Result<(Int, Data?), Error>]) -> (URLSession, RequestRecorder, () -> Void) {
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

    private func taiPoKau() throws -> TideStation {
        try #require(HongKongTideStations.all.first { $0.providerStationCode == "TPK" })
    }

    private func januaryRange(days: ClosedRange<Int>) -> LocalDateRange {
        LocalDateRange(
            start: LocalDate(year: 2026, month: 1, day: days.lowerBound),
            endInclusive: LocalDate(year: 2026, month: 1, day: days.upperBound)
        )
    }

    /// 2026 synthesis with BOM + LF endings (Dec 31 rows).
    private static func hourly2026() -> Data {
        let heights = (0..<24).map { String(format: "%.2f", 0.90 + Double($0) * 0.01) }
        let text = "\u{feff}MM,DD,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24\n"
            + "12,31," + heights.joined(separator: ",") + "\n"
        return Data(text.utf8)
    }

    private static func hilo2026() -> Data {
        let text = "\u{feff}Month,Date,Time,Height(m),Time,Height(m),Time,Height(m),Time,Height(m)\n"
            + "12,31,0313,1.10,0925,1.39,1150,1.31,1734,2.26\n"
        return Data(text.utf8)
    }

    /// 2027 synthesis with CRLF endings and quoted fields (Jan 1 rows) —
    /// proves the parser tolerates quotes and CRLF; the quoted header is a
    /// single field containing commas.
    private static func hourly2027() -> Data {
        let header = "\"MM,DD,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24\"\r\n"
        let heights = (0..<24).map { String(format: "%.2f", 1.40 + Double($0) * 0.01) }
        let row = heights.map { "\"\($0)\"" }.joined(separator: ",")
        return Data((header + "\"01\",\"01\"," + row + "\r\n").utf8)
    }

    private static func hilo2027() -> Data {
        let text = "\"Month\",\"Date\",\"Time\",\"Height(m)\",\"Time\",\"Height(m)\",\"Time\",\"Height(m)\",\"Time\",\"Height(m)\"\r\n"
            + "\"01\",\"01\",\"0512\",\"0.70\",\"1122\",\"1.63\",\"1714\",\"1.20\",\"2257\",\"2.41\"\r\n"
        return Data(text.utf8)
    }

    // MARK: - Compiled catalogue

    @Test func catalogIsCompiledActiveIntersectionWithoutNetwork() async throws {
        let (session, recorder, cleanup) = makeSession(routes: [:])
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: try makeCache())

        let stations = try await client.loadStationCatalog()

        // No runtime catalogue fetch and no resource loading.
        #expect(recorder.urls.isEmpty)
        // The two closed stations flagged by the dataset are excluded.
        #expect(stations.count == 12)
        #expect(stations.allSatisfy { $0.provider == .hongKongHKO })
        #expect(stations.contains { $0.providerStationCode == "TPK" && $0.name == "Tai Po Kau" })
        #expect(stations.contains { $0.providerStationCode == "QUB" })
        #expect(!stations.contains { ["CMW", "LOP"].contains($0.providerStationCode) })
        #expect(stations.first?.timeZoneIdentifier == "Asia/Hong_Kong")
        #expect(stations.first?.datumLabel == "Chart Datum")
    }

    // MARK: - Predictions

    @Test func loadPredictionsParsesCSVSlicesHKTAndInfersEventKinds() async throws {
        let taiPoKau2026HourlyFixture = try fixture("HKO/tai-po-kau-2026-hourly.csv")
        let taiPoKau2026HiloFixture = try fixture("HKO/tai-po-kau-2026-hilo.csv")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.hourlyURL2026: .success((200, taiPoKau2026HourlyFixture)),
            Self.hiloURL2026: .success((200, taiPoKau2026HiloFixture))
        ])
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: try makeCache())

        let range = januaryRange(days: 1...5)
        let week = try await client.loadPredictions(station: try taiPoKau(), range: range)

        // Exactly the two contract requests: HHOT + HLT for 2026.
        #expect(Set(recorder.urls) == Set([
            URL(string: Self.hourlyURL2026)!,
            URL(string: Self.hiloURL2026)!
        ]))

        // Jan 1–4 contribute hours 1…24 each (hour 24 lands at next-day
        // midnight); Jan 5 contributes hours 1…23: 4×24 + 23 = 119.
        #expect(week.hourlySamples.count == 119)
        let jan1FirstHour = try hkt(2026, 1, 1, 1)
        #expect(week.hourlySamples[0].instant == jan1FirstHour)
        #expect(abs(week.hourlySamples[0].heightMetres - 0.68) < 0.0000001)
        let jan2Midnight = try hkt(2026, 1, 2, 0)
        #expect(week.hourlySamples.contains { $0.instant == jan2Midnight && abs($0.heightMetres - 1.07) < 0.0000001 })
        let jan6Midnight = try hkt(2026, 1, 6, 0)
        #expect(!week.hourlySamples.contains { $0.instant == jan6Midnight })

        // Unlabeled HLT pairs alternate: Jan 1 is low, high, low, high.
        #expect(week.events.count == 20)
        let jan1Events = week.events.filter { $0.instant < jan2Midnight }
        #expect(jan1Events.map(\.kind) == [.low, .high, .low, .high])
        let jan1Event0 = try hkt(2026, 1, 1, 1, 16)
        let jan1Event3 = try hkt(2026, 1, 1, 19, 52)
        #expect(jan1Events[0].instant == jan1Event0)
        #expect(abs(jan1Events[0].heightMetres - 0.67) < 0.0000001)
        #expect(jan1Events[3].instant == jan1Event3)
        #expect(abs(jan1Events[3].heightMetres - 2.55) < 0.0000001)

        #expect(week.station.datumLabel == "Chart Datum")
        #expect(week.sourceAttribution == TideProvider.hongKongHKO.attribution)
        #expect(week.localDateRange == range)
    }

    @Test func rejectsWhenHiloSourceIsMalformed() async throws {
        let taiPoKau2026HourlyFixture = try fixture("HKO/tai-po-kau-2026-hourly.csv")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.hourlyURL2026: .success((200, taiPoKau2026HourlyFixture)),
            Self.hiloURL2026: .success((200, Data("<html>not a csv</html>".utf8)))
        ])
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: try makeCache())

        do {
            _ = try await client.loadPredictions(station: try taiPoKau(), range: januaryRange(days: 1...5))
            Issue.record("Expected a malformed-source rejection")
        } catch {
            #expect((error as? TideLoadError) == .invalidProviderResponse)
        }
    }

    @Test func rejectsWhenHourlySourceMissingRequestedDates() async throws {
        // The captured hourly file stops at Jan 10; Jan 14–15 rows are
        // missing while the hilo file does cover them — the range must be
        // rejected because either source is incomplete.
        let taiPoKau2026HourlyFixture = try fixture("HKO/tai-po-kau-2026-hourly.csv")
        let taiPoKau2026HiloFixture = try fixture("HKO/tai-po-kau-2026-hilo.csv")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.hourlyURL2026: .success((200, taiPoKau2026HourlyFixture)),
            Self.hiloURL2026: .success((200, taiPoKau2026HiloFixture))
        ])
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: try makeCache())

        do {
            _ = try await client.loadPredictions(station: try taiPoKau(), range: januaryRange(days: 14...15))
            Issue.record("Expected a missing-source rejection")
        } catch {
            #expect((error as? TideLoadError) == .noPredictions)
        }
    }

    @Test func newYearRangeReadsBothYearsForBothSourceKinds() async throws {

        let (session, recorder, cleanup) = makeSession(routes: [
            Self.hourlyURL2026: .success((200, Self.hourly2026())),
            Self.hiloURL2026: .success((200, Self.hilo2026())),
            Self.hourlyURL2027: .success((200, Self.hourly2027())),
            Self.hiloURL2027: .success((200, Self.hilo2027()))
        ])
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: try makeCache())

        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 12, day: 31),
            endInclusive: LocalDate(year: 2027, month: 1, day: 1)
        )
        let week = try await client.loadPredictions(station: try taiPoKau(), range: range)

        // Two years × two source kinds.
        #expect(recorder.urls.count == 4)
        #expect(recorder.urls.contains(URL(string: Self.hourlyURL2026)!))
        #expect(recorder.urls.contains(URL(string: Self.hiloURL2026)!))
        #expect(recorder.urls.contains(URL(string: Self.hourlyURL2027)!))
        #expect(recorder.urls.contains(URL(string: Self.hiloURL2027)!))

        // Dec 31 hours 1…24 (hour 24 at Jan 1 00:00) + Jan 1 hours 1…23.
        #expect(week.hourlySamples.count == 47)
        let dec31FirstHour = try hkt(2026, 12, 31, 1)
        #expect(week.hourlySamples[0].instant == dec31FirstHour)
        #expect(abs(week.hourlySamples[0].heightMetres - 0.90) < 0.0000001)
        let newYear0100 = try hkt(2027, 1, 1, 1)
        #expect(week.hourlySamples.contains { $0.instant == newYear0100 && abs($0.heightMetres - 1.40) < 0.0000001 })

        // Events from both years: the quoted-comma/CRLF 2027 CSV parsed.
        #expect(week.events.count == 8)
        let newYearMidnight = try hkt(2027, 1, 1, 0)
        let dec31Events = week.events.filter { $0.instant < newYearMidnight }
        #expect(dec31Events.map(\.kind) == [.low, .high, .low, .high])
        let jan1High1122 = try hkt(2027, 1, 1, 11, 22)
        #expect(week.events.contains { $0.kind == .high && $0.instant == jan1High1122 && abs($0.heightMetres - 1.63) < 0.0000001 })
        let jan1Low0512 = try hkt(2027, 1, 1, 5, 12)
        #expect(week.events.contains { $0.kind == .low && $0.instant == jan1Low0512 && abs($0.heightMetres - 0.70) < 0.0000001 })
    }

    @Test func cacheReuseServesSecondCallWithoutNetwork() async throws {
        let cache = try makeCache()
        let taiPoKau2026HourlyFixture = try fixture("HKO/tai-po-kau-2026-hourly.csv")
        let taiPoKau2026HiloFixture = try fixture("HKO/tai-po-kau-2026-hilo.csv")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.hourlyURL2026: .success((200, taiPoKau2026HourlyFixture)),
            Self.hiloURL2026: .success((200, taiPoKau2026HiloFixture))
        ])
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: cache)

        _ = try await client.loadPredictions(station: try taiPoKau(), range: januaryRange(days: 1...5))
        _ = try await client.loadPredictions(station: try taiPoKau(), range: januaryRange(days: 1...5))

        // The second call came from TideDiskCache (.hourly / .hilo kinds).
        #expect(recorder.urls.count == 2)
        let cachedHourly = try await cache.loadSource(
            provider: .hongKongHKO, stationID: "TPK", year: 2026, kind: .hourly
        )
        let cachedHilo = try await cache.loadSource(
            provider: .hongKongHKO, stationID: "TPK", year: 2026, kind: .hilo
        )
        #expect(cachedHourly != nil)
        #expect(cachedHilo != nil)
    }

    /// A 200-with-garbage response (captive portal, proxy error page) is
    /// rejected AND not persisted for either source kind — otherwise it
    /// would re-poison every call until source expiry.
    @Test func garbage200IsNotCachedAndLaterGoodFetchRecovers() async throws {
        let cache = try makeCache()
        let serveGarbage = TestToggle(true)
        let recorder = RequestRecorder()
        let (session, cleanup) = TestURLSessionHelper.makeSession { request in
            let url = try #require(request.url)
            recorder.record(url)
            let data = serveGarbage.isOn
                ? Data("<html>captive portal</html>".utf8)
                : try AlmanacFixtureLoader.data(
                    url.absoluteString == Self.hourlyURL2026
                        ? "HKO/tai-po-kau-2026-hourly.csv"
                        : "HKO/tai-po-kau-2026-hilo.csv"
                )
            return TestURLSessionHelper.httpResponse(url: url, statusCode: 200, data: data)
        }
        defer { cleanup() }
        let client = HongKongTideClient(session: session, cache: cache)

        do {
            _ = try await client.loadPredictions(station: try taiPoKau(), range: januaryRange(days: 1...5))
            Issue.record("Expected a garbage-200 rejection")
        } catch {
            #expect((error as? TideLoadError) == .invalidProviderResponse)
        }
        #expect(try await cache.loadSource(
            provider: .hongKongHKO, stationID: "TPK", year: 2026, kind: .hourly
        ) == nil)
        #expect(try await cache.loadSource(
            provider: .hongKongHKO, stationID: "TPK", year: 2026, kind: .hilo
        ) == nil)

        // Once the provider recovers, a later good fetch succeeds and is cached.
        serveGarbage.set(false)
        let week = try await client.loadPredictions(station: try taiPoKau(), range: januaryRange(days: 1...5))
        #expect(week.hourlySamples.count == 119)
        #expect(recorder.urls == [
            URL(string: Self.hourlyURL2026)!,
            URL(string: Self.hourlyURL2026)!,
            URL(string: Self.hiloURL2026)!
        ])
        #expect(try await cache.loadSource(
            provider: .hongKongHKO, stationID: "TPK", year: 2026, kind: .hourly
        ) != nil)
        #expect(try await cache.loadSource(
            provider: .hongKongHKO, stationID: "TPK", year: 2026, kind: .hilo
        ) != nil)
    }
}
