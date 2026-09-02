//
//  TideServiceTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct TideServiceTests {

    // MARK: - Fakes

    private final class FakeTideClient: TideProviderClient {
        let provider: TideProvider
        var catalog: [TideStation]
        var catalogError: (any Error)?
        var week: TideWeek?
        var predictionError: (any Error)?
        private(set) var catalogFetchCount = 0
        private(set) var predictionRequests: [(station: TideStation, range: LocalDateRange)] = []

        init(provider: TideProvider, catalog: [TideStation] = [], week: TideWeek? = nil) {
            self.provider = provider
            self.catalog = catalog
            self.week = week
        }

        func loadStationCatalog() async throws -> [TideStation] {
            catalogFetchCount += 1
            if let catalogError { throw catalogError }
            return catalog
        }

        func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
            predictionRequests.append((station, range))
            if let predictionError { throw predictionError }
            guard let week else { throw TideLoadError.noPredictions }
            return week
        }
    }

    /// Maximally sensitive fake: every call counts, so a service that consults
    /// the resolver for an already-zoned station fails the test.
    private final class FakeTimeZoneResolver: TideStationTimeZoneResolving {
        var identifier = "America/Vancouver"
        var error: (any Error)?
        private(set) var resolveCount = 0

        func resolveIdentifier(for station: TideStation) async throws -> String {
            resolveCount += 1
            if let error { throw error }
            return identifier
        }
    }

    /// Mutable clock so catalogue/day freshness boundaries are deterministic.
    private final class Clock {
        var current: Date
        init(_ current: Date) { self.current = current }
        func date() -> Date { current }
    }

    // MARK: - Fixtures

    private static let vancouver = TimeZone(identifier: "America/Vancouver")!
    private static let fetchedAt = Self.utcDate(2026, 9, 1)

    private static let septemberRange = LocalDateRange(
        start: LocalDate(year: 2026, month: 9, day: 1),
        endInclusive: LocalDate(year: 2026, month: 9, day: 7)
    )

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func station(
        id: String,
        latitude: Double,
        longitude: Double = -123.1207,
        timeZoneIdentifier: String? = "America/Vancouver",
        provider: TideProvider = .canadaCHS
    ) -> TideStation {
        TideStation(
            id: id,
            provider: provider,
            providerStationCode: id,
            name: "Station \(id)",
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            datumLabel: "Chart Datum",
            supportsHourlyCurve: true
        )
    }

    private func vancouverLocation() -> AlmanacLocation {
        AlmanacLocation(
            mode: .selected,
            latitude: 49.2827,
            longitude: -123.1207,
            displayName: "Vancouver",
            timeZoneIdentifier: "America/Vancouver",
            countryCode: "CA",
            administrativeArea: "British Columbia"
        )
    }

    private func tokyoLocation() -> AlmanacLocation {
        AlmanacLocation(
            mode: .selected,
            latitude: 35.6812,
            longitude: 139.7671,
            displayName: "Tokyo",
            timeZoneIdentifier: "Asia/Tokyo",
            countryCode: "JP",
            administrativeArea: "Tokyo"
        )
    }

    private func parisLocation() -> AlmanacLocation {
        AlmanacLocation(
            mode: .selected,
            latitude: 48.8566,
            longitude: 2.3522,
            displayName: "Paris",
            timeZoneIdentifier: "Europe/Paris",
            countryCode: "FR",
            administrativeArea: "Île-de-France"
        )
    }

    /// A complete seven-day week, Sep 1–7 2026 Vancouver time, with hourly
    /// samples spanning every local day and events on Sep 2 and Sep 5.
    private func septemberWeek(station: TideStation, fetchedAt: Date) throws -> TideWeek {
        let timeZone = station.timeZone ?? Self.vancouver
        var samples: [TideSample] = []
        var instant = try LocalDate(year: 2026, month: 9, day: 1).start(in: timeZone)
        let rangeEnd = try LocalDate(year: 2026, month: 9, day: 8).start(in: timeZone)
        while instant < rangeEnd {
            samples.append(TideSample(instant: instant, heightMetres: 2.5))
            instant = instant.addingTimeInterval(3600)
        }
        return TideWeek(
            station: station,
            localDateRange: Self.septemberRange,
            hourlySamples: samples,
            events: [
                TideEvent(kind: .high, instant: try LocalDate(year: 2026, month: 9, day: 2).noon(in: timeZone), heightMetres: 4.6),
                TideEvent(kind: .low, instant: try LocalDate(year: 2026, month: 9, day: 5).noon(in: timeZone), heightMetres: 0.7)
            ],
            fetchedAt: fetchedAt,
            sourceAttribution: station.provider.attribution
        )
    }

    private func makeCache(clock: Clock? = nil) -> TideDiskCache {
        TideDiskCache(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TideServiceTests-\(UUID().uuidString)"),
            now: { clock?.date() ?? Date() }
        )
    }

    /// Ten eligible CHS stations at 0, 5, … 45 km north of the Vancouver
    /// location (0.045° latitude ≈ 5 km), nearest first.
    private func tenStationCatalog() -> [TideStation] {
        (0..<10).map { index in
            station(id: String(format: "S%02d", index), latitude: 49.2827 + Double(index) * 0.045)
        }
    }

    // MARK: - Coverage and dispatch from the same injected set

    @Test func sameInjectedEnabledProvidersDriveCoverageAndClientDispatch() async throws {
        let tokyo = station(
            id: "TK",
            latitude: 35.65,
            longitude: 139.7666667,
            timeZoneIdentifier: "Asia/Tokyo",
            provider: .japanJMA
        )
        let jmaClient = FakeTideClient(provider: .japanJMA, catalog: [tokyo])
        let resolver = FakeTimeZoneResolver()
        let service = TideService(
            enabledProviders: [.japanJMA],
            clients: [.japanJMA: jmaClient],
            cache: makeCache(),
            timeZoneResolver: resolver
        )

        let context = try await service.resolveStation(for: tokyoLocation(), override: nil)

        // The same injected set routed coverage…
        #expect(context.coverage == .provider(.japanJMA))
        // …and dispatched to the one client built for it, without geocoding
        // (the compiled JMA station already carries Asia/Tokyo).
        #expect(jmaClient.catalogFetchCount == 1)
        #expect(resolver.resolveCount == 0)
        #expect(context.selected.id == "TK")
    }

    @Test func disabledSupportedProviderThrowsProviderUnavailableWithoutEditingStaticEnum() async throws {
        let chsClient = FakeTideClient(provider: .canadaCHS)
        let service = TideService(
            enabledProviders: [.unitedStatesNOAA],
            clients: [.unitedStatesNOAA: FakeTideClient(provider: .unitedStatesNOAA)],
            cache: makeCache(),
            timeZoneResolver: FakeTimeZoneResolver()
        )

        // The static enum is only the production default and stays untouched.
        #expect(TideProvider.enabled == [.canadaCHS, .unitedStatesNOAA, .japanJMA, .hongKongHKO])

        await #expect(throws: TideLoadError.providerUnavailable) {
            try await service.resolveStation(for: vancouverLocation(), override: nil)
        }
        #expect(chsClient.catalogFetchCount == 0)
    }

    @Test func unsupportedRegionRemainsDistinct() async throws {
        let service = TideService(
            enabledProviders: [.canadaCHS, .unitedStatesNOAA, .japanJMA, .hongKongHKO],
            clients: [:],
            cache: makeCache(),
            timeZoneResolver: FakeTimeZoneResolver()
        )

        await #expect(throws: TideLoadError.unsupportedRegion) {
            try await service.resolveStation(for: parisLocation(), override: nil)
        }
    }

    // MARK: - Selection and override

    @Test func nearestStationAndUpToEightAlternatives() async throws {
        let catalog = tenStationCatalog()
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        try await cache.saveCatalog(provider: .canadaCHS, stations: catalog, fetchedAt: clock.current)
        let chsClient = FakeTideClient(provider: .canadaCHS)
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)

        let context = try await service.resolveStation(for: vancouverLocation(), override: nil)

        #expect(context.selected.id == "S00")
        #expect(context.distanceMetres < 100)
        #expect(context.nearbyStations.map(\.id) == ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"])
        #expect(context.coverage == .provider(.canadaCHS))
    }

    @Test func manualOverrideWinsWhileValid() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        try await cache.saveCatalog(provider: .canadaCHS, stations: tenStationCatalog(), fetchedAt: clock.current)
        let service = makeService(clients: [.canadaCHS: FakeTideClient(provider: .canadaCHS)], cache: cache)
        let location = vancouverLocation()

        let overridden = try await service.resolveStation(
            for: location,
            override: TideStationOverride(stationID: "S03", anchorLatitude: location.latitude, anchorLongitude: location.longitude)
        )
        #expect(overridden.selected.id == "S03")
        // The auto-nearest stays offered and the chosen station is removed.
        #expect(overridden.nearbyStations.count == 8)
        #expect(overridden.nearbyStations.contains { $0.id == "S00" })
        #expect(!overridden.nearbyStations.contains { $0.id == "S03" })

        // An override naming an unknown station is invalid and falls back.
        let fallback = try await service.resolveStation(
            for: location,
            override: TideStationOverride(stationID: "GHOST", anchorLatitude: location.latitude, anchorLongitude: location.longitude)
        )
        #expect(fallback.selected.id == "S00")
    }

    // MARK: - Time-zone enrichment

    @Test func missingZoneIsGeocodedOnceWrittenToCachedCatalogueThenReused() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let unresolved = station(id: "07735", latitude: 49.2827, timeZoneIdentifier: nil)
        let chsClient = FakeTideClient(provider: .canadaCHS, catalog: [unresolved])
        let resolver = FakeTimeZoneResolver()
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache, timeZoneResolver: resolver)

        let first = try await service.resolveStation(for: vancouverLocation(), override: nil)
        #expect(first.timeZone == Self.vancouver)
        #expect(resolver.resolveCount == 1)

        // The resolved identifier landed in the cached catalogue — the single
        // persistence source of truth.
        let stored = try await cache.loadCatalog(provider: .canadaCHS)
        #expect(stored?.stations.first?.timeZoneIdentifier == "America/Vancouver")

        // The enriched catalogue is reused; no second geocode.
        let second = try await service.resolveStation(for: vancouverLocation(), override: nil)
        #expect(second.timeZone == Self.vancouver)
        #expect(resolver.resolveCount == 1)
    }

    @Test func catalogueRefreshMergesPreviouslyResolvedZones() async throws {
        // A stale catalogue whose station was enriched earlier; the fresh
        // provider row still lacks a zone.
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let enriched = station(id: "07735", latitude: 49.2827, timeZoneIdentifier: nil)
        var seeded = enriched
        seeded.timeZoneIdentifier = "America/Vancouver"
        try await cache.saveCatalog(provider: .canadaCHS, stations: [seeded], fetchedAt: clock.current)

        clock.current = clock.current.addingTimeInterval(40 * 24 * 60 * 60)

        let chsClient = FakeTideClient(provider: .canadaCHS, catalog: [enriched])
        let resolver = FakeTimeZoneResolver()
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache, timeZoneResolver: resolver)

        let context = try await service.resolveStation(for: vancouverLocation(), override: nil)

        // The merged zone survived the 30-day catalogue refresh: no geocode,
        // and the refreshed cached row keeps the identifier.
        #expect(resolver.resolveCount == 0)
        #expect(chsClient.catalogFetchCount == 1)
        #expect(context.timeZone == Self.vancouver)
        let stored = try await cache.loadCatalog(provider: .canadaCHS)
        #expect(stored?.stations.first?.timeZoneIdentifier == "America/Vancouver")
    }

    // MARK: - Cache-first day reads

    @Test func freshSelectedDayReturnsWithoutNetwork() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let vancouver = station(id: "07735", latitude: 49.2827)
        try await cache.saveCompleteRange(septemberWeek(station: vancouver, fetchedAt: clock.current), in: Self.vancouver)
        let chsClient = FakeTideClient(provider: .canadaCHS)
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)

        let snapshot = try await service.cachedDay(
            station: vancouver,
            date: LocalDate(year: 2026, month: 9, day: 3)
        )

        let day = try #require(snapshot)
        #expect(!day.isStale)
        #expect(day.day.localDate == LocalDate(year: 2026, month: 9, day: 3))
        #expect(day.day.hourlySamples.count == 24)
        #expect(chsClient.predictionRequests.isEmpty)
    }

    @Test func staleSelectedDayReturnsBeforeRefresh() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let vancouver = station(id: "07735", latitude: 49.2827)
        try await cache.saveCompleteRange(septemberWeek(station: vancouver, fetchedAt: clock.current), in: Self.vancouver)
        clock.current = clock.current.addingTimeInterval(40 * 24 * 60 * 60)
        let chsClient = FakeTideClient(provider: .canadaCHS)
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)

        let snapshot = try await service.cachedDay(
            station: vancouver,
            date: LocalDate(year: 2026, month: 9, day: 3)
        )

        // The stale day is returned as-is; refreshing is the caller's move.
        let day = try #require(snapshot)
        #expect(day.isStale)
        #expect(chsClient.predictionRequests.isEmpty)
    }

    @Test func sep2UsesDayCachedBySep1RangeFetch() async throws {
        let clock = Clock(Self.utcDate(2026, 9, 1))
        let cache = makeCache(clock: clock)
        let vancouver = station(id: "07735", latitude: 49.2827)
        let chsClient = FakeTideClient(
            provider: .canadaCHS,
            week: try septemberWeek(station: vancouver, fetchedAt: clock.current)
        )
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)

        _ = try await service.refreshRange(station: vancouver, range: Self.septemberRange)

        // The next day, the moving window's Sep 2 entry is a cache hit.
        clock.current = Self.utcDate(2026, 9, 2)
        let snapshot = try await service.cachedDay(
            station: vancouver,
            date: LocalDate(year: 2026, month: 9, day: 2)
        )
        let day = try #require(snapshot, "Sep 2 must hit the day file written by the Sep 1 range fetch")
        #expect(!day.isStale)
        #expect(day.day.events.first?.kind == .high)
        #expect(chsClient.predictionRequests.count == 1)
    }

    // MARK: - Forced refresh

    @Test func forcedRefreshUpdatesCacheOnSuccess() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let vancouver = station(id: "07735", latitude: 49.2827)
        let week = try septemberWeek(station: vancouver, fetchedAt: clock.current)
        let chsClient = FakeTideClient(provider: .canadaCHS, week: week)
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)

        let refreshed = try await service.refreshRange(station: vancouver, range: Self.septemberRange)

        #expect(refreshed == week)
        #expect(chsClient.predictionRequests.count == 1)
        #expect(chsClient.predictionRequests.first?.range == Self.septemberRange)
        let snapshot = try await service.cachedDay(
            station: vancouver,
            date: LocalDate(year: 2026, month: 9, day: 5)
        )
        #expect(snapshot?.day.fetchedAt == week.fetchedAt)
    }

    @Test func forcedRefreshFailurePreservesCachedDay() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let vancouver = station(id: "07735", latitude: 49.2827)
        let chsClient = FakeTideClient(
            provider: .canadaCHS,
            week: try septemberWeek(station: vancouver, fetchedAt: clock.current)
        )
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)
        _ = try await service.refreshRange(station: vancouver, range: Self.septemberRange)

        clock.current = clock.current.addingTimeInterval(40 * 24 * 60 * 60)
        chsClient.predictionError = TideLoadError.networkUnavailable

        await #expect(throws: TideLoadError.networkUnavailable) {
            try await service.refreshRange(station: vancouver, range: Self.septemberRange)
        }

        // The failed refresh never erased the usable cached day.
        let snapshot = try await service.cachedDay(
            station: vancouver,
            date: LocalDate(year: 2026, month: 9, day: 3)
        )
        let day = try #require(snapshot)
        #expect(day.isStale)
        #expect(day.day.hourlySamples.count == 24)
    }

    @Test func partialResultNeverCallsSaveCompleteRange() async throws {
        let clock = Clock(Self.fetchedAt)
        let cache = makeCache(clock: clock)
        let vancouver = station(id: "07735", latitude: 49.2827)
        // A partial provider result: hourly curve without exact events.
        let partial = try septemberWeek(station: vancouver, fetchedAt: clock.current)
        let partialWeek = TideWeek(
            station: partial.station,
            localDateRange: partial.localDateRange,
            hourlySamples: partial.hourlySamples,
            events: [],
            fetchedAt: partial.fetchedAt,
            sourceAttribution: partial.sourceAttribution
        )
        let chsClient = FakeTideClient(provider: .canadaCHS, week: partialWeek)
        let service = makeService(clients: [.canadaCHS: chsClient], cache: cache)

        await #expect(throws: TideLoadError.noPredictions) {
            try await service.refreshRange(station: vancouver, range: Self.septemberRange)
        }

        // No normalized day entry was created or replaced.
        let snapshot = try await service.cachedDay(
            station: vancouver,
            date: LocalDate(year: 2026, month: 9, day: 1)
        )
        #expect(snapshot == nil)
    }

    // MARK: - New Year ranges through the real annual-source clients

    @Test func newYearRequestsCoverBothYears() async throws {
        let clock = Clock(Self.utcDate(2026, 12, 31))
        let cache = makeCache(clock: clock)
        let resolver = FakeTimeZoneResolver()
        let newYearRange = LocalDateRange(
            start: LocalDate(year: 2026, month: 12, day: 31),
            endInclusive: LocalDate(year: 2027, month: 1, day: 1)
        )

        // JMA: the canonical 2026 fixture carries Dec 31; Jan 1 2027 is a
        // schema-faithful synthetic record.
        let jmaRecorder = RequestRecorder()
        let (jmaSession, jmaCleanup) = TestURLSessionHelper.makeSession { request in
            let url = try #require(request.url)
            jmaRecorder.record(url)
            let data = url.absoluteString.hasSuffix("/2027/TK.txt")
                ? Data(Self.jmaRecord(
                    year: 2027, month: 1, day: 1, symbol: "TK",
                    hourly: Array(100..<124),
                    highs: [(5, 0, 150), (17, 30, 180)],
                    lows: [(11, 15, 90), (23, 45, 60)]
                ).utf8)
                : try AlmanacFixtureLoader.data("JMA/tokyo-2026.txt")
            return TestURLSessionHelper.httpResponse(url: url, statusCode: 200, data: data)
        }
        defer { jmaCleanup() }
        let tokyo = try #require(JapanTideStations.all.first { $0.providerStationCode == "TK" })
        let jmaService = TideService(
            enabledProviders: [.japanJMA],
            clients: [.japanJMA: JapanTideClient(session: jmaSession, cache: cache)],
            cache: cache,
            timeZoneResolver: resolver
        )

        let jmaWeek = try await jmaService.refreshRange(station: tokyo, range: newYearRange)
        let requestedURLs = jmaRecorder.urls.map(\.absoluteString)
        #expect(requestedURLs.contains { $0.hasSuffix("/2026/TK.txt") })
        #expect(requestedURLs.contains { $0.hasSuffix("/2027/TK.txt") })
        let jmaDec31 = try await cache.loadDay(
            provider: .japanJMA, stationID: "TK", date: LocalDate(year: 2026, month: 12, day: 31)
        )
        let jmaJan1 = try await cache.loadDay(
            provider: .japanJMA, stationID: "TK", date: LocalDate(year: 2027, month: 1, day: 1)
        )
        #expect(jmaDec31?.day.hourlySamples.count == 23) // hours 1…23; hour 24 lands on Jan 1
        #expect(jmaDec31?.day.events.isEmpty == false)
        #expect(jmaJan1?.day.hourlySamples.count == 24) // Dec 31 hour 24 + Jan 1 hours 1…23
        #expect(jmaJan1?.day.events.count == 4)
        #expect(jmaWeek.localDateRange == newYearRange)

        // HKO: both source kinds must cover both years for the range.
        let hkoRecorder = RequestRecorder()
        let (hkoSession, hkoCleanup) = TestURLSessionHelper.makeSession { request in
            let url = try #require(request.url)
            hkoRecorder.record(url)
            let data: Data
            switch request.url?.absoluteString {
            case .some(let string) where string.contains("year=2026") && string.contains("HHOT"):
                data = Self.hkoHourlyCSV(year: 2026, month: 12, day: 31, baseHeight: 0.90)
            case .some(let string) where string.contains("year=2026") && string.contains("HLT"):
                data = Data("\u{feff}Month,Date,Time,Height(m),Time,Height(m),Time,Height(m),Time,Height(m)\n12,31,0313,1.10,0925,1.39,1150,1.31,1734,2.26\n".utf8)
            case .some(let string) where string.contains("year=2027") && string.contains("HHOT"):
                data = Self.hkoHourlyCSV(year: 2027, month: 1, day: 1, baseHeight: 1.40)
            case .some(let string) where string.contains("year=2027") && string.contains("HLT"):
                data = Data("\u{feff}Month,Date,Time,Height(m),Time,Height(m),Time,Height(m),Time,Height(m)\n01,01,0512,0.70,1122,1.63,1714,1.20,2257,2.41\n".utf8)
            default:
                data = Data("not found".utf8)
            }
            return TestURLSessionHelper.httpResponse(url: url, statusCode: 200, data: data)
        }
        defer { hkoCleanup() }
        let taiPoKau = try #require(HongKongTideStations.all.first { $0.providerStationCode == "TPK" })
        let hkoService = TideService(
            enabledProviders: [.hongKongHKO],
            clients: [.hongKongHKO: HongKongTideClient(session: hkoSession, cache: cache)],
            cache: cache,
            timeZoneResolver: resolver
        )

        _ = try await hkoService.refreshRange(station: taiPoKau, range: newYearRange)
        #expect(hkoRecorder.urls.map(\.absoluteString).contains { $0.contains("year=2026") })
        #expect(hkoRecorder.urls.map(\.absoluteString).contains { $0.contains("year=2027") })
        let hkoDec31 = try await cache.loadDay(
            provider: .hongKongHKO, stationID: "TPK", date: LocalDate(year: 2026, month: 12, day: 31)
        )
        let hkoJan1 = try await cache.loadDay(
            provider: .hongKongHKO, stationID: "TPK", date: LocalDate(year: 2027, month: 1, day: 1)
        )
        #expect(hkoDec31?.day.hourlySamples.isEmpty == false)
        #expect(hkoDec31?.day.events.isEmpty == false)
        #expect(hkoJan1?.day.hourlySamples.isEmpty == false)
        #expect(hkoJan1?.day.events.isEmpty == false)

        // Compiled JMA/HKO zones bypass geocoding entirely.
        #expect(resolver.resolveCount == 0)
    }

    // MARK: - Test support

    private func makeService(
        clients: [TideProvider: any TideProviderClient],
        cache: TideDiskCache,
        timeZoneResolver: FakeTimeZoneResolver = FakeTimeZoneResolver()
    ) -> TideService {
        TideService(
            enabledProviders: Set(clients.keys),
            clients: clients,
            cache: cache,
            timeZoneResolver: timeZoneResolver
        )
    }

    /// Schema-faithful 136-char JMA annual record (contract layout:
    /// 72-char hourly, 6-char YYMMDD space-padded, 2-char symbol, four
    /// 4-char HHMM + 3-char cm highs, same lows, 9999/999 sentinels).
    private static func jmaRecord(
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

    private static func hkoHourlyCSV(year: Int, month: Int, day: Int, baseHeight: Double) -> Data {
        let heights = (0..<24).map { String(format: "%.2f", baseHeight + Double($0) * 0.01) }
        let text = "\u{feff}MM,DD,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24\n"
            + "\(month),\(day)," + heights.joined(separator: ",") + "\n"
        return Data(text.utf8)
    }
}
