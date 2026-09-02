//
//  TideDiskCacheTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct TideDiskCacheTests {

    // MARK: - Fixtures

    /// Mutable clock so freshness boundaries are exercised deterministically.
    private final class Clock {
        var current: Date
        init(_ current: Date) { self.current = current }
        func date() -> Date { current }
    }

    private static let vancouver = TimeZone(identifier: "America/Vancouver")!

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TideDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func station(id: String = "07735", timeZoneIdentifier: String? = "America/Vancouver") -> TideStation {
        TideStation(
            id: id,
            provider: .canadaCHS,
            providerStationCode: id,
            name: "Vancouver",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: timeZoneIdentifier,
            datumLabel: "Chart Datum",
            supportsHourlyCurve: true
        )
    }

    private func tideDay(_ date: LocalDate, fetchedAt: Date) -> TideDay {
        TideDay(
            station: station(),
            localDate: date,
            hourlySamples: [TideSample(instant: utcDate(2026, 9, 1, 7), heightMetres: 2.5)],
            events: [],
            fetchedAt: fetchedAt,
            sourceAttribution: TideProvider.canadaCHS.attribution
        )
    }

    /// A complete seven-day week, Sep 1–7 2026 Vancouver time, with hourly
    /// samples spanning every local day and events on Sep 2 and Sep 5.
    /// (Vancouver stays on PDT until 2026-11-01, so every local day here has
    /// exactly 24 hourly samples.)
    private func septemberWeek(fetchedAt: Date) throws -> TideWeek {
        let timeZone = Self.vancouver
        let range = try LocalDate(year: 2026, month: 9, day: 1).rollingSevenDays(in: timeZone)
        var samples: [TideSample] = []
        var instant = try LocalDate(year: 2026, month: 9, day: 1).start(in: timeZone)
        let rangeEnd = try LocalDate(year: 2026, month: 9, day: 8).start(in: timeZone)
        while instant < rangeEnd {
            samples.append(TideSample(instant: instant, heightMetres: 2.5))
            instant = instant.addingTimeInterval(3600)
        }
        return TideWeek(
            station: station(),
            localDateRange: range,
            hourlySamples: samples,
            events: [
                TideEvent(kind: .high, instant: try LocalDate(year: 2026, month: 9, day: 2).noon(in: timeZone), heightMetres: 4.6),
                TideEvent(kind: .low, instant: try LocalDate(year: 2026, month: 9, day: 5).noon(in: timeZone), heightMetres: 0.7)
            ],
            fetchedAt: fetchedAt,
            sourceAttribution: TideProvider.canadaCHS.attribution
        )
    }

    private func loadDay(_ date: LocalDate, from cache: TideDiskCache) async throws -> TideDiskCache.CachedDay? {
        try await cache.loadDay(provider: .canadaCHS, stationID: "07735", date: date)
    }

    private static let thirtyDays: TimeInterval = TideDiskCache.predictionFreshness

    // MARK: - Prediction freshness

    @Test func predictionDayIsFreshForThirtyDays() async throws {
        let root = makeRoot()
        let fetchedAt = utcDate(2026, 9, 1)
        let clock = Clock(fetchedAt)
        let cache = TideDiskCache(rootURL: root, now: { clock.date() })
        try await cache.saveCompleteRange(septemberWeek(fetchedAt: fetchedAt), in: Self.vancouver)

        clock.current = fetchedAt.addingTimeInterval(Self.thirtyDays - 60)
        let loaded = try await loadDay(LocalDate(year: 2026, month: 9, day: 3), from: cache)
        let cached = try #require(loaded)
        #expect(!cached.isStale)
        #expect(cached.day.localDate == LocalDate(year: 2026, month: 9, day: 3))
    }

    @Test func staleDayStillLoadsWithIsStaleTrue() async throws {
        let root = makeRoot()
        let fetchedAt = utcDate(2026, 9, 1)
        let clock = Clock(fetchedAt)
        let cache = TideDiskCache(rootURL: root, now: { clock.date() })
        try await cache.saveCompleteRange(septemberWeek(fetchedAt: fetchedAt), in: Self.vancouver)

        clock.current = fetchedAt.addingTimeInterval(40 * 24 * 60 * 60)
        let loaded = try await loadDay(LocalDate(year: 2026, month: 9, day: 3), from: cache)
        let cached = try #require(loaded)
        #expect(cached.isStale)
        #expect(cached.day.hourlySamples.count == 24)
    }

    // MARK: - Rolling-window overlap regression

    @Test func sevenDayFetchSavedOnSep1YieldsSep2HitWithoutNewRangeKey() async throws {
        let root = makeRoot()
        let fetchedAt = utcDate(2026, 9, 1)
        let clock = Clock(fetchedAt)
        let cache = TideDiskCache(rootURL: root, now: { clock.date() })
        try await cache.saveCompleteRange(septemberWeek(fetchedAt: fetchedAt), in: Self.vancouver)

        // The next day's fetch of Sep 2 must hit the same day-keyed files.
        clock.current = utcDate(2026, 9, 2)
        let loaded = try await loadDay(LocalDate(year: 2026, month: 9, day: 2), from: cache)
        let cached = try #require(loaded, "Sep 2 must be a cache hit after the Sep 1 seven-day save")
        #expect(!cached.isStale)

        // Exactly seven day-keyed files exist — no rolling-range keys.
        let stationDirectory = root.appendingPathComponent("days/v1/canadaCHS/07735")
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: stationDirectory.path).sorted()
        #expect(fileNames == (1...7).map { String(format: "2026-09-%02d.json", $0) })
    }

    // MARK: - Partitioning

    @Test func saveCompleteRangePartitionsWeekIntoLocalDayFiles() async throws {
        let root = makeRoot()
        let timeZone = Self.vancouver
        let cache = TideDiskCache(rootURL: root)
        let week = try septemberWeek(fetchedAt: utcDate(2026, 9, 1))
        try await cache.saveCompleteRange(week, in: timeZone)

        let fileManager = FileManager.default
        for dayNumber in 1...7 {
            let url = root.appendingPathComponent(
                "days/v1/canadaCHS/07735/\(String(format: "2026-09-%02d", dayNumber)).json"
            )
            #expect(fileManager.fileExists(atPath: url.path), "missing day file \(url.lastPathComponent)")
        }

        let sep1 = LocalDate(year: 2026, month: 9, day: 1)
        let loaded1 = try await loadDay(sep1, from: cache)
        let day1 = try #require(loaded1)
        let sep1Start = try sep1.start(in: timeZone)
        #expect(day1.day.hourlySamples.count == 24)
        #expect(day1.day.hourlySamples.first?.instant == sep1Start)
        #expect(day1.day.events.isEmpty)
        #expect(day1.day.fetchedAt == week.fetchedAt)
        #expect(day1.day.station == week.station)

        let sep2 = LocalDate(year: 2026, month: 9, day: 2)
        let loaded2 = try await loadDay(sep2, from: cache)
        let day2 = try #require(loaded2)
        let sep2High = TideEvent(kind: .high, instant: try sep2.noon(in: timeZone), heightMetres: 4.6)
        #expect(day2.day.events == [sep2High])

        let sep5 = LocalDate(year: 2026, month: 9, day: 5)
        let loaded5 = try await loadDay(sep5, from: cache)
        let day5 = try #require(loaded5)
        let sep5Low = TideEvent(kind: .low, instant: try sep5.noon(in: timeZone), heightMetres: 0.7)
        #expect(day5.day.events == [sep5Low])
    }

    @Test func weekWithSamplesOutsideRangeThrowsAndWritesNoDayFiles() async throws {
        let root = makeRoot()
        let timeZone = Self.vancouver
        let cache = TideDiskCache(rootURL: root)
        let week = try septemberWeek(fetchedAt: utcDate(2026, 9, 1))
        let rangeEnd = try week.localDateRange.endInclusive.endExclusive(in: timeZone)
        let badWeek = TideWeek(
            station: week.station,
            localDateRange: week.localDateRange,
            hourlySamples: week.hourlySamples + [TideSample(
                instant: rangeEnd.addingTimeInterval(3600),
                heightMetres: 1.0
            )],
            events: week.events,
            fetchedAt: week.fetchedAt,
            sourceAttribution: week.sourceAttribution
        )

        await #expect(throws: (any Error).self) {
            try await cache.saveCompleteRange(badWeek, in: timeZone)
        }

        // Validation happens before any write: nothing reached the disk.
        let stationDirectory = root.appendingPathComponent("days/v1/canadaCHS/07735")
        #expect(!FileManager.default.fileExists(atPath: stationDirectory.path))
    }

    // MARK: - Schema mismatch

    @Test func schemaMismatchIsACleanMiss() async throws {
        let root = makeRoot()
        let cache = TideDiskCache(rootURL: root)
        try await cache.saveCompleteRange(septemberWeek(fetchedAt: utcDate(2026, 9, 1)), in: Self.vancouver)

        let date = LocalDate(year: 2026, month: 9, day: 1)
        let url = root.appendingPathComponent("days/v1/canadaCHS/07735/2026-09-01.json")
        let mismatched = try JSONEncoder().encode(
            StoredTideDay(
                schemaVersion: TideDiskCache.schemaVersion + 1,
                day: tideDay(date, fetchedAt: utcDate(2026, 9, 1))
            )
        )
        try mismatched.write(to: url)
        let mismatchedLoad = try await loadDay(date, from: cache)
        #expect(mismatchedLoad == nil)

        // Corrupt bytes are also a clean miss, not a throw.
        try Data("not json".utf8).write(to: url)
        let corruptLoad = try await loadDay(date, from: cache)
        #expect(corruptLoad == nil)
    }

    // MARK: - Catalogue

    @Test func catalogueIsFreshForThirtyDaysAndStaleCatalogueStillReadable() async throws {
        let root = makeRoot()
        let fetchedAt = utcDate(2026, 9, 1)
        let clock = Clock(fetchedAt)
        let cache = TideDiskCache(rootURL: root, now: { clock.date() })
        let stations = [station(id: "07735"), station(id: "07740")]
        try await cache.saveCatalog(provider: .canadaCHS, stations: stations, fetchedAt: fetchedAt)

        clock.current = fetchedAt.addingTimeInterval(TideDiskCache.catalogueFreshness - 60)
        let freshLoaded = try await cache.loadCatalog(provider: .canadaCHS)
        let fresh = try #require(freshLoaded)
        #expect(!fresh.isStale)
        #expect(fresh.stations == stations)

        clock.current = fetchedAt.addingTimeInterval(40 * 24 * 60 * 60)
        let staleLoaded = try await cache.loadCatalog(provider: .canadaCHS)
        let stale = try #require(staleLoaded)
        #expect(stale.isStale)
        #expect(stale.stations == stations)
    }

    @Test func catalogueTimeZoneEnrichmentSurvivesReload() async throws {
        let root = makeRoot()
        let cache = TideDiskCache(rootURL: root)
        let stations = [station(id: "07735", timeZoneIdentifier: nil)]
        try await cache.saveCatalog(provider: .canadaCHS, stations: stations, fetchedAt: utcDate(2026, 9, 1))

        let updated = try await cache.updateCatalogTimeZone(
            provider: .canadaCHS,
            stationID: "07735",
            identifier: "America/Vancouver"
        )
        #expect(updated.timeZoneIdentifier == "America/Vancouver")
        #expect(updated.timeZone == Self.vancouver)

        // A fresh actor over the same files sees the enrichment.
        let reloaded = TideDiskCache(rootURL: root)
        let reloadedCatalog = try await reloaded.loadCatalog(provider: .canadaCHS)
        let catalog = try #require(reloadedCatalog)
        #expect(catalog.stations.first?.timeZoneIdentifier == "America/Vancouver")
        #expect(catalog.stations.first?.name == "Vancouver")

        // Enrichment preserves the original fetch time.
        let clock = Clock(utcDate(2026, 10, 15))
        let staleReader = TideDiskCache(rootURL: root, now: { clock.date() })
        let afterEnrichmentLoaded = try await staleReader.loadCatalog(provider: .canadaCHS)
        let afterEnrichment = try #require(afterEnrichmentLoaded)
        #expect(afterEnrichment.isStale)
    }

    // MARK: - Source files

    @Test func sourceKindsProduceDistinctAnnualHourlyAndHiloPaths() async throws {
        let root = makeRoot()
        let cache = TideDiskCache(rootURL: root)

        let annual = Data("jma annual text".utf8)
        let hourly = Data("hko hourly csv".utf8)
        let hilo = Data("hko hilo csv".utf8)
        try await cache.saveSource(annual, provider: .japanJMA, stationID: "TK", year: 2026, kind: .annual)
        try await cache.saveSource(hourly, provider: .hongKongHKO, stationID: "TK", year: 2026, kind: .hourly)
        try await cache.saveSource(hilo, provider: .hongKongHKO, stationID: "TK", year: 2026, kind: .hilo)

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("sources/jma/TK/2026.txt").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("sources/hko/TK/2026-hourly.csv").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("sources/hko/TK/2026-hilo.csv").path))

        let loadedAnnual = try await cache.loadSource(provider: .japanJMA, stationID: "TK", year: 2026, kind: .annual)
        let loadedHourly = try await cache.loadSource(provider: .hongKongHKO, stationID: "TK", year: 2026, kind: .hourly)
        let loadedHilo = try await cache.loadSource(provider: .hongKongHKO, stationID: "TK", year: 2026, kind: .hilo)
        #expect(loadedAnnual == annual)
        #expect(loadedHourly == hourly)
        #expect(loadedHilo == hilo)

        // A kind/provider pair that was never saved is a miss.
        let unloaded = try await cache.loadSource(provider: .japanJMA, stationID: "TK", year: 2027, kind: .annual)
        #expect(unloaded == nil)
    }
}
