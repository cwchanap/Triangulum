//
//  AlmanacViewModelTests.swift
//  TriangulumTests
//

import Testing
import Foundation
import CoreLocation
import MapKit
@testable import Triangulum

@MainActor
struct AlmanacViewModelTests {

    // MARK: - Fixtures

    private static let vancouverTimeZone = TimeZone(identifier: "America/Vancouver")!

    /// 2026-09-15 02:00 UTC == 2026-09-14 19:00 Vancouver (PDT, UTC-7), so
    /// destination-local today differs from UTC's calendar date. (tzdb note:
    /// this machine's Vancouver is permanent UTC-7 from 2026-11-01; September
    /// is safely DST.)
    private nonisolated static let now = Self.utcDate(2026, 9, 15, 2)
    private static let todayLocal = LocalDate(year: 2026, month: 9, day: 14)

    private nonisolated static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let vancouver = AlmanacLocation(
        mode: .selected,
        latitude: 49.2827,
        longitude: -123.1207,
        displayName: "Vancouver",
        timeZoneIdentifier: "America/Vancouver",
        countryCode: "CA",
        administrativeArea: "British Columbia"
    )

    private static let victoria = AlmanacLocation(
        mode: .selected,
        latitude: 48.4284,
        longitude: -123.3656,
        displayName: "Victoria",
        timeZoneIdentifier: "America/Vancouver",
        countryCode: "CA",
        administrativeArea: "British Columbia"
    )

    private static let paris = AlmanacLocation(
        mode: .selected,
        latitude: 48.8566,
        longitude: 2.3522,
        displayName: "Paris",
        timeZoneIdentifier: "Europe/Paris",
        countryCode: "FR",
        administrativeArea: "Île-de-France"
    )

    private static let resolvedCurrent = AlmanacLocation(
        mode: .current,
        latitude: 49.0,
        longitude: -123.0,
        displayName: "Current Place",
        timeZoneIdentifier: "America/Vancouver",
        countryCode: "CA",
        administrativeArea: "British Columbia"
    )

    private static let station = TideStation(
        id: "CHS-07385",
        provider: .canadaCHS,
        providerStationCode: "07385",
        name: "Vancouver Point Atkinson",
        latitude: 49.3299,
        longitude: -123.2594,
        timeZoneIdentifier: "America/Vancouver",
        datumLabel: "Chart Datum",
        supportsHourlyCurve: true
    )

    private nonisolated static func stationContext(station: TideStation = station) -> TideStationContext {
        TideStationContext(
            coverage: .provider(.canadaCHS),
            selected: station,
            nearbyStations: [],
            distanceMetres: 0,
            timeZone: Self.vancouverTimeZone
        )
    }

    private nonisolated static func tideDay(date: LocalDate, fetchedAt: Date = now) -> TideDay {
        TideDay(
            station: station,
            localDate: date,
            hourlySamples: [TideSample(instant: fetchedAt, heightMetres: 3.0)],
            events: [TideEvent(kind: .high, instant: fetchedAt, heightMetres: 4.0)],
            fetchedAt: fetchedAt,
            sourceAttribution: "test"
        )
    }

    // MARK: - Scaffolding

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test.almanac.viewmodel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @MainActor
    private struct Harness {
        let store: AlmanacPreferencesStore
        let defaults: UserDefaults
        let suiteName: String
        let tideService: FakeTideService
        let resolver: FakeLocationResolver
        let locationManager: LocationManager

        var viewModel: AlmanacViewModel {
            AlmanacViewModel(
                dependencies: AlmanacDependencies(
                    tideService: tideService,
                    locationResolver: resolver,
                    preferencesStore: store,
                    now: { AlmanacViewModelTests.now }
                ),
                locationManager: locationManager
            )
        }
    }

    private func makeHarness(
        preferences: AlmanacPreferences = .default,
        resolveResult: Result<TideStationContext, Error> = .success(Self.stationContext()),
        resolverLocation: AlmanacLocation = Self.resolvedCurrent
    ) -> Harness {
        let (defaults, suiteName) = makeDefaults()
        try? AlmanacPreferencesStore(defaults: defaults).save(preferences)
        return Harness(
            store: AlmanacPreferencesStore(defaults: defaults),
            defaults: defaults,
            suiteName: suiteName,
            tideService: FakeTideService(resolveResult: resolveResult),
            resolver: FakeLocationResolver(result: resolverLocation),
            locationManager: LocationManager(skipAvailabilityCheck: true)
        )
    }

    /// Polls until `condition` holds so coalesced/generation-guarded async
    /// application becomes deterministic without sleeps on the happy path.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    // MARK: - Fakes

    private final class Gate: @unchecked Sendable {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            isOpen = true
            continuations.forEach { $0.resume() }
            continuations.removeAll()
        }
    }

    /// Deterministic fakes: day/refresh outcomes are pure functions of their
    /// inputs, so repeated (generation-superseded) calls cannot corrupt state.
    private final class FakeTideService: TideServing {
        var resolveResult: Result<TideStationContext, Error>
        var cachedHandler: ((TideStation, LocalDate) -> TideDaySnapshot?)?
        var refreshHandler: ((TideStation, LocalDateRange) throws -> TideWeek)?
        /// While set, `cachedDay` suspends every call numbered below the
        /// barrier so the generation guard can be exercised against a
        /// genuinely in-flight superseded load.
        var cachedGate: Gate?
        var cachedGateBarrier = Int.max

        private(set) var resolveRequests: [(location: AlmanacLocation, override: TideStationOverride?)] = []
        private(set) var cachedRequests: [(stationID: String, date: LocalDate)] = []
        private(set) var refreshRequests: [(stationID: String, range: LocalDateRange)] = []
        private var cachedCallCount = 0

        init(resolveResult: Result<TideStationContext, Error>) {
            self.resolveResult = resolveResult
        }

        func resolveStation(for location: AlmanacLocation, override: TideStationOverride?) async throws -> TideStationContext {
            resolveRequests.append((location, override))
            return try resolveResult.get()
        }

        func cachedDay(station: TideStation, date: LocalDate) async throws -> TideDaySnapshot? {
            cachedRequests.append((station.id, date))
            cachedCallCount += 1
            if cachedCallCount < cachedGateBarrier, let cachedGate {
                await cachedGate.wait()
            }
            return cachedHandler?(station, date)
        }

        func refreshRange(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
            refreshRequests.append((station.id, range))
            if let refreshHandler { return try refreshHandler(station, range) }
            struct Unimplemented: Error {}
            throw Unimplemented()
        }
    }

    private final class FakeLocationResolver: AlmanacLocationResolving {
        let result: AlmanacLocation
        private(set) var currentCoordinateCalls: [CLLocationCoordinate2D] = []

        init(result: AlmanacLocation) {
            self.result = result
        }

        func resolveSearchCompletion(_ completion: MKLocalSearchCompletion) async throws -> AlmanacLocation {
            result
        }

        func resolveCurrentCoordinate(_ coordinate: CLLocationCoordinate2D) async throws -> AlmanacLocation {
            currentCoordinateCalls.append(coordinate)
            return result
        }
    }

    // MARK: - Launch restore

    @Test func launchRestoresLocationModeButSelectedDateBecomesDestinationLocalToday() {
        let harness = makeHarness(
            preferences: AlmanacPreferences(
                mode: .selected,
                selectedLocation: Self.vancouver,
                stationOverride: TideStationOverride(stationID: "CHS-07385", anchorLatitude: 49.3, anchorLongitude: -123.2)
            )
        )
        let viewModel = harness.viewModel

        #expect(viewModel.location == Self.vancouver)
        // Destination-local today from the injected clock, not a persisted date.
        #expect(viewModel.selectedDate == Self.todayLocal)
        #expect(viewModel.visibleDates == (try? Self.todayLocal.rollingSevenDays(in: Self.vancouverTimeZone).dates(in: Self.vancouverTimeZone)))
        #expect(viewModel.section == .sun)
        #expect(viewModel.solarDay != nil)
        // Tides load lazily when the section is shown.
        #expect(viewModel.stationContext == nil)
        #expect(harness.tideService.resolveRequests.isEmpty)
    }

    // MARK: - Live manager isolation

    @Test func fixedLocationNeverMutatesLiveLocationManagerCoordinates() {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        harness.locationManager.latitude = 49.26
        harness.locationManager.longitude = -123.11

        let viewModel = harness.viewModel
        viewModel.selectLocation(Self.paris)

        #expect(harness.locationManager.latitude == 49.26)
        #expect(harness.locationManager.longitude == -123.11)
    }

    // MARK: - Section switching

    @Test func switchingSunTidesPreservesSelectedDayAndLocation() {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        let viewModel = harness.viewModel
        let locationBefore = viewModel.location
        let dateBefore = viewModel.selectedDate

        viewModel.section = .tides

        #expect(viewModel.location == locationBefore)
        #expect(viewModel.selectedDate == dateBefore)
        viewModel.section = .sun
        #expect(viewModel.location == locationBefore)
        #expect(viewModel.selectedDate == dateBefore)
    }

    // MARK: - Override lifecycle

    @Test func changingFixedLocationClearsManualStationOverride() async {
        let override = TideStationOverride(stationID: "CHS-07385", anchorLatitude: 49.3, anchorLongitude: -123.2)
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: override)
        )
        let viewModel = harness.viewModel
        viewModel.selectLocation(Self.victoria)
        viewModel.section = .tides
        await viewModel.loadTides()
        #expect(harness.tideService.resolveRequests.allSatisfy { $0.override == nil })
        #expect(harness.store.load().stationOverride == nil)
    }

    @Test func currentLocationMovementUnder5kmReusesPlacemarkOver5kmResolvesAgain() async {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0

        viewModel.useCurrentLocation()
        await waitUntil { harness.resolver.currentCoordinateCalls.count == 1 }
        #expect(viewModel.location != nil)

        // ~1 km north: placemark reused.
        harness.locationManager.latitude = 49.009
        try? await Task.sleep(nanoseconds: 250_000_000)
        #expect(harness.resolver.currentCoordinateCalls.count == 1)

        // ~11 km more: placemark resolved again.
        harness.locationManager.longitude = -123.16
        await waitUntil { harness.resolver.currentCoordinateCalls.count == 2 }
    }

    @Test func manualOverrideSurvivesMovementWithin25kmAndClearsBeyond() async {
        let home = CLLocation(latitude: 49.0, longitude: -123.0)
        let override = TideStationOverride(
            stationID: "CHS-07385",
            anchorLatitude: home.coordinate.latitude,
            anchorLongitude: home.coordinate.longitude
        )
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .current, selectedLocation: nil, stationOverride: override)
        )
        let viewModel = harness.viewModel
        viewModel.section = .tides
        harness.locationManager.latitude = home.coordinate.latitude
        harness.locationManager.longitude = home.coordinate.longitude

        viewModel.useCurrentLocation()
        await waitUntil { harness.tideService.resolveRequests.count == 1 }
        #expect(harness.tideService.resolveRequests[0].override?.stationID == "CHS-07385")

        // ~10 km north: override retained.
        harness.locationManager.latitude = 49.09
        await waitUntil { harness.tideService.resolveRequests.count == 2 }
        #expect(harness.tideService.resolveRequests[1].override?.stationID == "CHS-07385")

        // ~30 km north of the anchor: override cleared.
        harness.locationManager.latitude = 49.27
        await waitUntil { harness.tideService.resolveRequests.count == 3 }
        #expect(harness.tideService.resolveRequests[2].override == nil)
        #expect(harness.store.load().stationOverride == nil)
    }

    // MARK: - Solar/tide independence

    @Test func unsupportedTideRegionStillComputesSolarDay() async {
        let harness = makeHarness(
            resolveResult: .failure(TideLoadError.unsupportedRegion)
        )
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.paris)
        viewModel.section = .tides
        await viewModel.loadTides()

        #expect(viewModel.tideWarning == .unsupportedRegion)
        #expect(viewModel.tideDay == nil)
        #expect(viewModel.stationContext == nil)
        #expect(viewModel.solarDay != nil)
        // Paris-local today from the same instant: 2026-09-15 04:00 CEST.
        #expect(viewModel.selectedDate == LocalDate(year: 2026, month: 9, day: 15))
    }

    // MARK: - Cache-first tide loading

    private func cachedTideHarness(
        cachedHandler: @escaping (TideStation, LocalDate) -> TideDaySnapshot?
    ) -> Harness {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        harness.tideService.cachedHandler = cachedHandler
        return harness
    }

    @Test func freshCachedTideDayPublishesWithoutRefresh() async {
        let day = Self.tideDay(date: Self.todayLocal)
        let harness = cachedTideHarness { _, _ in TideDaySnapshot(day: day, isStale: false) }
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.vancouver)
        viewModel.section = .tides
        await viewModel.loadTides()

        #expect(viewModel.tideDay == day)
        #expect(viewModel.tideIsStale == false)
        #expect(viewModel.tideWarning == nil)
        #expect(harness.tideService.refreshRequests.isEmpty)
    }

    @Test func staleTideDayPublishesBeforeOneRefreshAttempt() async {
        let day = Self.tideDay(date: Self.todayLocal, fetchedAt: Self.utcDate(2026, 6, 1))
        let harness = cachedTideHarness { _, _ in TideDaySnapshot(day: day, isStale: true) }
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.vancouver)
        viewModel.section = .tides
        await viewModel.loadTides()

        #expect(viewModel.tideDay == day)
        #expect(viewModel.tideIsStale == true)
        #expect(!harness.tideService.refreshRequests.isEmpty)
    }

    @Test func refreshFailurePreservesCachedTideDayWithWarning() async {
        let day = Self.tideDay(date: Self.todayLocal, fetchedAt: Self.utcDate(2026, 6, 1))
        let harness = cachedTideHarness { _, _ in TideDaySnapshot(day: day, isStale: true) }
        harness.tideService.refreshHandler = { _, _ in throw TideLoadError.networkUnavailable }
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.vancouver)
        viewModel.section = .tides
        await viewModel.loadTides()

        #expect(viewModel.tideDay == day)
        #expect(viewModel.tideWarning == .networkUnavailable)
    }

    @Test func missingSelectedDayTriggersRefreshOfCurrentRollingSevenDayRange() async throws {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        let refreshedDay = Self.tideDay(date: Self.todayLocal)
        harness.tideService.refreshHandler = { station, range in
            TideWeek(
                station: station,
                localDateRange: range,
                hourlySamples: [TideSample(instant: Self.now, heightMetres: 2.0)],
                events: [],
                fetchedAt: Self.now,
                sourceAttribution: "test"
            )
        }
        // The selected day is missing on the first cache read; after the
        // refresh writes the range, re-reading the cache hits.
        harness.tideService.cachedHandler = { _, date in
            guard date == Self.todayLocal else { return nil }
            return harness.tideService.cachedRequests.count <= 1
                ? nil
                : TideDaySnapshot(day: refreshedDay, isStale: false)
        }
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.vancouver)
        viewModel.section = .tides
        await viewModel.loadTides()

        let expectedRange = try Self.todayLocal.rollingSevenDays(in: Self.vancouverTimeZone)
        #expect(!harness.tideService.refreshRequests.isEmpty)
        #expect(harness.tideService.refreshRequests.allSatisfy { $0.range == expectedRange })
        #expect(viewModel.tideDay == refreshedDay)
        #expect(viewModel.tideWarning == nil)
    }

    // MARK: - Generation guard

    @Test func olderAsyncResponseCannotOverwriteNewerSelection() async {
        let harness = cachedTideHarness { _, _ in nil }
        let gate = Gate()
        harness.tideService.cachedGate = gate
        harness.tideService.cachedGateBarrier = 3
        let laterDate = LocalDate(year: 2026, month: 9, day: 15)
        let laterDay = Self.tideDay(date: laterDate)
        harness.tideService.cachedHandler = { _, date in
            date == laterDate ? TideDaySnapshot(day: laterDay, isStale: false) : nil
        }
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.vancouver)
        viewModel.section = .tides

        // The section-triggered load stalls in the gated cache read; an
        // explicit stale task stalls beside it, having captured the old
        // generation.
        await waitUntil { harness.tideService.cachedRequests.count >= 1 }
        let staleTask = Task { await viewModel.loadTides() }
        await waitUntil { harness.tideService.cachedRequests.count >= 2 }

        viewModel.selectDate(laterDate)
        await waitUntil { harness.tideService.cachedRequests.count >= 3 }
        await waitUntil { viewModel.tideDay?.localDate == laterDate }

        gate.open()
        await staleTask.value

        #expect(viewModel.selectedDate == laterDate)
        #expect(viewModel.tideDay?.localDate == laterDate)
    }

    /// Regression: a superseded load that completes after its post-refresh
    /// cache read must not clear the state (e.g. the warning) a newer load
    /// published while it was in flight. The tail of `performTideLoad` runs
    /// after `publishCachedDay`'s own internal guard, so it needs its own
    /// generation check immediately before applying.
    @Test func olderGenerationLatePostRefreshCompletionCannotClearNewerWarning() async {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        harness.tideService.cachedHandler = { _, _ in nil }
        harness.tideService.refreshHandler = { station, range in
            TideWeek(
                station: station,
                localDateRange: range,
                hourlySamples: [],
                events: [],
                fetchedAt: Self.now,
                sourceAttribution: "test"
            )
        }
        // Staged gates: the first stalls the load's initial cache read; the
        // second, armed only after the first opens, stalls the same load's
        // post-refresh cache read while it still holds the current generation.
        let initialReadGate = Gate()
        let postRefreshReadGate = Gate()
        harness.tideService.cachedGate = initialReadGate
        harness.tideService.cachedGateBarrier = 3
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.vancouver)
        viewModel.section = .tides
        await waitUntil { harness.tideService.cachedRequests.count == 1 }

        // Release the first read; the load refreshes and stalls again in the
        // post-refresh cache read, still holding the current generation.
        harness.tideService.cachedGate = postRefreshReadGate
        initialReadGate.open()
        await waitUntil { harness.tideService.cachedRequests.count == 2 }

        // A newer selection supersedes the stalled load; its station resolve
        // fails fast (Paris is an unsupported tide region) and publishes its
        // own warning while the older load is still in flight.
        harness.tideService.resolveResult = .failure(TideLoadError.unsupportedRegion)
        viewModel.selectLocation(Self.paris)
        await waitUntil { viewModel.tideWarning == .unsupportedRegion }

        // The stale load's post-refresh read now completes; without a guard
        // after it, its tail would clear the newer warning.
        postRefreshReadGate.open()
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(viewModel.tideWarning == .unsupportedRegion)
    }
}
