//
//  JapanTideClientTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

/// `JapanTideClient` + compiled `JapanTideStations` against the canonical
/// JMA fixtures captured live on 2026-09-01
/// (docs/almanac-tide-source-contracts.md).
struct JapanTideClientTests {

    private static let annualURL2026 =
        "https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/2026/TK.txt"
    private static let annualURL2027 =
        "https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/2027/TK.txt"
    private static let jst = TimeZone(identifier: "Asia/Tokyo")!

    // MARK: - Helpers

    private func makeCache() throws -> TideDiskCache {
        TideDiskCache(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("almanac-jma-tests-\(UUID().uuidString)")
        )
    }

    private func jst(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.jst
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

    private func tokyo() throws -> TideStation {
        try #require(JapanTideStations.all.first { $0.providerStationCode == "TK" })
    }

    /// Builds a schema-faithful 136-char annual record (contract layout:
    /// 72-char hourly, 6-char YYMMDD space-padded, 2-char symbol, four
    /// 4-char HHMM + 3-char cm highs, same lows, 9999/999 sentinels).
    private func record(
        year: Int, month: Int, day: Int, symbol: String,
        hourly: [Int], highs: [(Int, Int, Int)], lows: [(Int, Int, Int)]
    ) -> String {
        func leftPadded(_ text: String, _ width: Int) -> String {
            String(repeating: " ", count: width - text.count) + text
        }
        func group(_ hhmm: Int, _ centimetres: Int) -> String {
            leftPadded(String(hhmm), 4) + leftPadded(String(centimetres), 3)
        }
        var text = hourly.map { leftPadded(String($0), 3) }.joined()
        text += leftPadded(String(year % 100), 2)
        text += leftPadded(String(month), 2)
        text += leftPadded(String(day), 2)
        text += symbol
        for slot in 0..<4 {
            if slot < highs.count {
                text += group(highs[slot].0 * 100 + highs[slot].1, highs[slot].2)
            } else {
                text += group(9999, 999)
            }
        }
        for slot in 0..<4 {
            if slot < lows.count {
                text += group(lows[slot].0 * 100 + lows[slot].1, lows[slot].2)
            } else {
                text += group(9999, 999)
            }
        }
        return text
    }

    // MARK: - Compiled catalogue

    @Test func tokyoStationMatchesCapturedOfficialRecord() throws {
        let tokyo = try #require(JapanTideStations.all.first { $0.providerStationCode == "TK" })
        #expect(tokyo.name == "Tokyo")
        #expect(abs(tokyo.latitude - 35.65) < 0.0001)
        #expect(abs(tokyo.longitude - 139.7666667) < 0.0001)
    }

    @Test func catalogIsCompiledWithoutNetwork() async throws {
        let (session, recorder, cleanup) = makeSession(routes: [:])
        defer { cleanup() }
        let client = JapanTideClient(session: session, cache: try makeCache())

        let stations = try await client.loadStationCatalog()

        // No runtime catalogue fetch and no resource loading.
        #expect(recorder.urls.isEmpty)
        #expect(stations.count > 200)
        #expect(stations.allSatisfy { $0.provider == .japanJMA })
        #expect(stations.first { $0.providerStationCode == "TK" }?.name == "Tokyo")
        #expect(stations.first { $0.providerStationCode == "TK" }?.timeZoneIdentifier == "Asia/Tokyo")
    }

    // MARK: - Predictions

    @Test func loadPredictionsParses136ByteRecordsSlicesJSTAndConvertsCentimetres() async throws {
        let cache = try makeCache()
        let tokyo2026Fixture = try fixture("JMA/tokyo-2026.txt")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.annualURL2026: .success((200, tokyo2026Fixture))
        ])
        defer { cleanup() }
        let client = JapanTideClient(session: session, cache: cache)

        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 1, day: 15),
            endInclusive: LocalDate(year: 2026, month: 1, day: 16)
        )
        let week = try await client.loadPredictions(station: try tokyo(), range: range)

        #expect(recorder.urls == [URL(string: Self.annualURL2026)!])

        // Jan 15 contributes hours 1…24 (hour 24 lands at Jan 16 00:00 JST);
        // Jan 16 contributes hours 1…23 (hour 24 at Jan 17 00:00 is clipped
        // by the window's exclusive end): 24 + 23 = 47 samples.
        #expect(week.hourlySamples.count == 47)
        let jan15FirstHour = try jst(2026, 1, 15, 1)
        #expect(week.hourlySamples[0].instant == jan15FirstHour)
        #expect(abs(week.hourlySamples[0].heightMetres - 0.90) < 0.0000001) // 90 cm
        let jan16Midnight = try jst(2026, 1, 16, 0)
        #expect(week.hourlySamples.contains { $0.instant == jan16Midnight && abs($0.heightMetres - 0.46) < 0.0000001 })
        let jan17Midnight = try jst(2026, 1, 17, 0)
        #expect(!week.hourlySamples.contains { $0.instant == jan17Midnight })

        // Line 15/16 exact highs and lows, cm → m, kinds from the file
        // section, ordered by time.
        #expect(week.events.count == 8)
        #expect(week.events.map(\.kind) == [.high, .low, .high, .low, .high, .low, .high, .low])
        let event0 = try jst(2026, 1, 15, 4, 21)
        let event1 = try jst(2026, 1, 15, 8, 42)
        let event2 = try jst(2026, 1, 15, 13, 48)
        let event3 = try jst(2026, 1, 15, 21, 22)
        let event7 = try jst(2026, 1, 16, 22, 2)
        #expect(week.events[0].instant == event0)
        #expect(abs(week.events[0].heightMetres - 1.53) < 0.0000001)
        #expect(week.events[1].instant == event1)
        #expect(abs(week.events[1].heightMetres - 1.23) < 0.0000001)
        #expect(week.events[2].instant == event2)
        #expect(abs(week.events[2].heightMetres - 1.56) < 0.0000001)
        #expect(week.events[3].instant == event3)
        #expect(abs(week.events[3].heightMetres - 0.30) < 0.0000001)
        #expect(week.events[7].instant == event7)
        #expect(abs(week.events[7].heightMetres - 0.19) < 0.0000001)

        #expect(week.station.datumLabel == "Tide-Table Datum")
        #expect(week.sourceAttribution == TideProvider.japanJMA.attribution)
        #expect(week.localDateRange == range)
    }

    @Test func newYearRangeReadsTwoAnnualSourceFiles() async throws {
        let tokyo2026Fixture = try fixture("JMA/tokyo-2026.txt")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.annualURL2026: .success((200, tokyo2026Fixture)),
            Self.annualURL2027: .success((200, Data(record(
                year: 2027, month: 1, day: 1, symbol: "TK",
                hourly: Array(100..<124),
                highs: [(5, 0, 150), (17, 30, 180)],
                lows: [(11, 15, 90), (23, 45, 60)]
            ).utf8)))
        ])
        defer { cleanup() }
        let client = JapanTideClient(session: session, cache: try makeCache())

        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 12, day: 31),
            endInclusive: LocalDate(year: 2027, month: 1, day: 1)
        )
        let week = try await client.loadPredictions(station: try tokyo(), range: range)

        // Both years were fetched.
        #expect(recorder.urls == [
            URL(string: Self.annualURL2026)!,
            URL(string: Self.annualURL2027)!
        ])

        // Dec 31 hours 1…24 (hour 24 at Jan 1 00:00) + Jan 1 hours 1…23.
        #expect(week.hourlySamples.count == 47)
        let dec31FirstHour = try jst(2026, 12, 31, 1)
        #expect(week.hourlySamples[0].instant == dec31FirstHour)
        #expect(abs(week.hourlySamples[0].heightMetres - 1.16) < 0.0000001)
        let newYearMidnight = try jst(2027, 1, 1, 0)
        #expect(week.hourlySamples.contains { $0.instant == newYearMidnight && abs($0.heightMetres - 1.27) < 0.0000001 })
        let newYear0100 = try jst(2027, 1, 1, 1)
        #expect(week.hourlySamples.contains { $0.instant == newYear0100 && abs($0.heightMetres - 1.00) < 0.0000001 })

        // Events from both files: Dec 31 (4) + Jan 1 2027 (4).
        #expect(week.events.count == 8)
        let dec31High2351 = try jst(2026, 12, 31, 23, 1)
        #expect(week.events.contains { $0.kind == .high && $0.instant == dec31High2351 && abs($0.heightMetres - 1.27) < 0.0000001 })
        let dec31Low0333 = try jst(2026, 12, 31, 3, 33)
        #expect(week.events.contains { $0.kind == .low && $0.instant == dec31Low0333 && abs($0.heightMetres - 0.73) < 0.0000001 })
        let jan1High1730 = try jst(2027, 1, 1, 17, 30)
        #expect(week.events.contains { $0.kind == .high && $0.instant == jan1High1730 && abs($0.heightMetres - 1.80) < 0.0000001 })
        let jan1Low2345 = try jst(2027, 1, 1, 23, 45)
        #expect(week.events.contains { $0.kind == .low && $0.instant == jan1Low2345 && abs($0.heightMetres - 0.60) < 0.0000001 })
    }

    @Test func cacheReuseServesSecondCallWithoutNetwork() async throws {
        let cache = try makeCache()
        let tokyo2026Fixture = try fixture("JMA/tokyo-2026.txt")
        let (session, recorder, cleanup) = makeSession(routes: [
            Self.annualURL2026: .success((200, tokyo2026Fixture))
        ])
        defer { cleanup() }
        let client = JapanTideClient(session: session, cache: cache)

        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 1, day: 15),
            endInclusive: LocalDate(year: 2026, month: 1, day: 16)
        )
        _ = try await client.loadPredictions(station: try tokyo(), range: range)
        _ = try await client.loadPredictions(station: try tokyo(), range: range)

        // The second call came from TideDiskCache (TideSourceKind.annual).
        #expect(recorder.urls == [URL(string: Self.annualURL2026)!])
        let cached = try await cache.loadSource(
            provider: .japanJMA, stationID: "TK", year: 2026, kind: .annual
        )
        #expect(cached != nil)
    }

    @Test func rejectsMalformedAnnualFile() async throws {
        let fixture = String(
            data: try AlmanacFixtureLoader.data("JMA/tokyo-2026.txt"), encoding: .utf8
        )!
        var lines = fixture.split(separator: "\n", omittingEmptySubsequences: false)
        lines[10] = lines[10].dropLast() // a 135-char record breaks the layout
        let malformed = Data(lines.joined(separator: "\n").utf8)


        let (session, recorder, cleanup) = makeSession(routes: [
            Self.annualURL2026: .success((200, malformed))
        ])
        defer { cleanup() }
        let client = JapanTideClient(session: session, cache: try makeCache())

        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 1, day: 15),
            endInclusive: LocalDate(year: 2026, month: 1, day: 16)
        )
        do {
            _ = try await client.loadPredictions(station: try tokyo(), range: range)
            Issue.record("Expected a malformed-file rejection")
        } catch {
            #expect((error as? TideLoadError) == .invalidProviderResponse)
        }
    }

    /// A 200-with-garbage response (captive portal, proxy error page) is
    /// rejected AND not persisted — otherwise it would re-poison every call
    /// for that station/year until source expiry.
    @Test func garbage200IsNotCachedAndLaterGoodFetchRecovers() async throws {
        let cache = try makeCache()
        var serveGarbage = true
        let recorder = RequestRecorder()
        let (session, cleanup) = TestURLSessionHelper.makeSession { request in
            let url = try #require(request.url)
            recorder.record(url)
            let data = serveGarbage
                ? Data("<html>captive portal</html>".utf8)
                : try AlmanacFixtureLoader.data("JMA/tokyo-2026.txt")
            return TestURLSessionHelper.httpResponse(url: url, statusCode: 200, data: data)
        }
        defer { cleanup() }
        let client = JapanTideClient(session: session, cache: cache)

        let range = LocalDateRange(
            start: LocalDate(year: 2026, month: 1, day: 15),
            endInclusive: LocalDate(year: 2026, month: 1, day: 16)
        )

        do {
            _ = try await client.loadPredictions(station: try tokyo(), range: range)
            Issue.record("Expected a garbage-200 rejection")
        } catch {
            #expect((error as? TideLoadError) == .invalidProviderResponse)
        }
        let poisoned = try await cache.loadSource(
            provider: .japanJMA, stationID: "TK", year: 2026, kind: .annual
        )
        #expect(poisoned == nil)

        // Once the provider recovers, a later good fetch succeeds and is cached.
        serveGarbage = false
        let week = try await client.loadPredictions(station: try tokyo(), range: range)
        #expect(week.hourlySamples.count == 47)
        #expect(recorder.urls == [
            URL(string: Self.annualURL2026)!,
            URL(string: Self.annualURL2026)!
        ])
        #expect(try await cache.loadSource(
            provider: .japanJMA, stationID: "TK", year: 2026, kind: .annual
        ) != nil)
    }
}
