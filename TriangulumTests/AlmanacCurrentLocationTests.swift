//
//  AlmanacCurrentLocationTests.swift
//  TriangulumTests
//
//  Focused suite for Current-mode (GPS-following) behavior: placemark reuse,
//  persisted-fixed-location preservation, authorization gating, and the
//  first-fix calendar reset. Split from AlmanacViewModelTests.swift to keep
//  that file under the repo's SwiftLint file_length limit (900 lines).
//

import Testing
import Foundation
import CoreLocation
import MapKit
@testable import Triangulum

@MainActor
struct AlmanacCurrentLocationTests {

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

    /// Tokyo is UTC+9: at the injected `now` (2026-09-15 02:00 UTC) Tokyo's
    /// calendar date is Sep 15 while Vancouver's is Sep 14 — used to verify
    /// the Current-mode calendar reset across a date boundary.
    private static let tokyo = AlmanacLocation(
        mode: .selected,
        latitude: 35.6762,
        longitude: 139.6503,
        displayName: "Tokyo",
        timeZoneIdentifier: "Asia/Tokyo",
        countryCode: "JP",
        administrativeArea: "Tokyo"
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

    // MARK: - Scaffolding

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test.almanac.current.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @MainActor
    private final class Harness {
        let store: AlmanacPreferencesStore
        let defaults: UserDefaults
        private let suiteName: String
        let tideService: FakeTideService
        let resolver: FakeLocationResolver
        let locationManager: LocationManager

        init(store: AlmanacPreferencesStore,
             defaults: UserDefaults,
             suiteName: String,
             tideService: FakeTideService,
             resolver: FakeLocationResolver,
             locationManager: LocationManager) {
            self.store = store
            self.defaults = defaults
            self.suiteName = suiteName
            self.tideService = tideService
            self.resolver = resolver
            self.locationManager = locationManager
        }

        /// The generated suite is removed when the harness deinits (end of
        /// each test) so persistent domains never leak across runs.
        deinit { defaults.removePersistentDomain(forName: suiteName) }

        var viewModel: AlmanacViewModel {
            AlmanacViewModel(
                dependencies: AlmanacDependencies(
                    tideService: tideService,
                    locationResolver: resolver,
                    preferencesStore: store,
                    now: { AlmanacCurrentLocationTests.now }
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
        // The shared live manager is observed only in Current mode, where the
        // view model now gates on authorization/availability. Reflect a
        // valid, authorized state so Current-mode tests process injected
        // coordinates; denied/revoked tests mutate these directly.
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        locationManager.isAvailable = true
        locationManager.authorizationStatus = .authorizedWhenInUse
        return Harness(
            store: AlmanacPreferencesStore(defaults: defaults),
            defaults: defaults,
            suiteName: suiteName,
            tideService: FakeTideService(resolveResult: resolveResult),
            resolver: FakeLocationResolver(result: resolverLocation),
            locationManager: locationManager
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

    /// Deterministic fakes: day/refresh outcomes are pure functions of their
    /// inputs, so repeated (generation-superseded) calls cannot corrupt state.
    private final class FakeTideService: TideServing {
        var resolveResult: Result<TideStationContext, Error>
        var cachedHandler: ((TideStation, LocalDate) -> TideDaySnapshot?)?
        var refreshHandler: ((TideStation, LocalDateRange) throws -> TideWeek)?

        private(set) var resolveRequests: [(location: AlmanacLocation, override: TideStationOverride?)] = []
        private(set) var cachedRequests: [(stationID: String, date: LocalDate)] = []
        private(set) var refreshRequests: [(stationID: String, range: LocalDateRange)] = []

        init(resolveResult: Result<TideStationContext, Error>) {
            self.resolveResult = resolveResult
        }

        func resolveStation(for location: AlmanacLocation, override: TideStationOverride?) async throws -> TideStationContext {
            resolveRequests.append((location, override))
            return try resolveResult.get()
        }

        func cachedDay(station: TideStation, date: LocalDate) async throws -> TideDaySnapshot? {
            cachedRequests.append((station.id, date))
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

    // MARK: - Current-mode placemark reuse

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

    // MARK: - Current mode never clobbers the persisted fixed location

    /// Regression (I3): Current-mode GPS fixes are displayed but never
    /// persisted as the last fixed location.
    @Test func currentModeFixesNeverOverwriteThePersistedFixedLocation() async {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        let viewModel = harness.viewModel

        viewModel.useCurrentLocation()
        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        await waitUntil { harness.resolver.currentCoordinateCalls.count == 1 }

        #expect(viewModel.location == Self.resolvedCurrent)
        #expect(harness.store.load().mode == .current)
        #expect(harness.store.load().selectedLocation == Self.vancouver,
                "A Current-mode fix must not overwrite the persisted fixed location")

        // Movement beyond 5 km resolves again; still never persisted.
        harness.locationManager.longitude = -123.16
        await waitUntil { harness.resolver.currentCoordinateCalls.count == 2 }
        #expect(viewModel.lastFixedLocation == Self.vancouver)
        #expect(harness.store.load().selectedLocation == Self.vancouver)
    }

    /// Regression (I3): the sheet derives its "last selected place" from the
    /// persisted last FIXED place, which a Current-mode launch restores even
    /// while the display follows the device.
    @Test func currentModeRestoreKeepsTheLastFixedLocationForTheSheet() {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .current, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        let viewModel = harness.viewModel

        #expect(viewModel.location == nil, "Current mode pins no location")
        #expect(viewModel.lastFixedLocation == Self.vancouver)
    }

    // MARK: - Current-mode authorization gating (P1)

    /// Regression: `LocationManager` keeps its last lat/long when permission
    /// becomes denied/restricted, so without an authorization gate Current
    /// mode would resolve and keep showing a stale GPS coordinate, and
    /// `AlmanacView` (which only surfaces the denied remediation when
    /// `location == nil`) would hide the denied state. Denied permission
    /// must invalidate the Current-mode display so the denied remediation
    /// surfaces. (The `CLLocationManager` delegate fires asynchronously and
    /// can override a pre-observation `.denied` setting, so the test sets
    /// `.denied` after the observation starts to test the invalidation
    /// path deterministically.)
    @Test func deniedPermissionInvalidatesTheCurrentModeDisplay() async {
        let harness = makeHarness()
        let viewModel = harness.viewModel

        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }

        // Deny permission while in Current mode. The display must clear so
        // the denied remediation surfaces, rather than showing a stale fix.
        harness.locationManager.authorizationStatus = .denied
        await waitUntil { viewModel.location == nil }

        #expect(viewModel.location == nil,
                "Denied permission must clear the stale GPS display")
        #expect(viewModel.selectedDate == nil)
        #expect(viewModel.solarDay == nil)
        #expect(viewModel.tideDay == nil)
    }

    /// Regression: revoking permission while already in Current mode (with a
    /// live fix on screen) must clear the display so the denied remediation
    /// surfaces, rather than leaving the stale GPS coordinate visible.
    @Test func revokingPermissionWhileInCurrentModeClearsTheDisplay() async {
        let harness = makeHarness()
        let viewModel = harness.viewModel

        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }
        #expect(viewModel.location != nil)

        // Revoke permission while already following the device.
        harness.locationManager.authorizationStatus = .denied
        await waitUntil { viewModel.location == nil }

        #expect(viewModel.location == nil,
                "Revoked permission must clear the stale GPS display")
        #expect(viewModel.selectedDate == nil)
        #expect(viewModel.solarDay == nil)
        #expect(viewModel.tideDay == nil)
    }

    /// Regression: revoking permission preserves `lastFixedLocation` so the
    /// location sheet still offers the last chosen place after the
    /// Current-mode display is cleared.
    @Test func revokingPermissionPreservesTheLastFixedLocationForTheSheet() async {
        let harness = makeHarness(
            preferences: AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        let viewModel = harness.viewModel
        #expect(viewModel.location == Self.vancouver)
        #expect(viewModel.lastFixedLocation == Self.vancouver)

        viewModel.useCurrentLocation()
        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        await waitUntil { viewModel.location == Self.resolvedCurrent }

        harness.locationManager.authorizationStatus = .denied
        await waitUntil { viewModel.location == nil }

        #expect(viewModel.location == nil)
        #expect(viewModel.lastFixedLocation == Self.vancouver,
                "The sheet must still offer the last fixed place after revocation")
    }

    /// Regression: a restricted authorization status (parental controls,
    /// MDM) is treated identically to denied — the display is invalidated.
    @Test func restrictedPermissionInvalidatesTheCurrentModeDisplay() async {
        let harness = makeHarness()
        let viewModel = harness.viewModel

        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }

        harness.locationManager.authorizationStatus = .restricted
        await waitUntil { viewModel.location == nil }

        #expect(viewModel.location == nil)
    }

    /// Regression (P1): re-granting permission must NOT resolve
    /// `LocationManager`'s stored (pre-revocation) coordinate. The auth/
    /// availability sinks are invalidate-only; after invalidation the
    /// coordinate publisher drives resolution when Core Location delivers a
    /// fresh fix. Forwarding the stored coordinate on re-grant would
    /// repopulate the display with a stale placemark, and if the real
    /// post-grant fix moved <5 km the reuse guard would then suppress it and
    /// leave the stale placemark indefinitely.
    @Test func regrantingPermissionDoesNotResolveTheStalePreRevocationCoordinate() async {
        let harness = makeHarness()
        let viewModel = harness.viewModel

        // Establish a Current-mode fix.
        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }
        let callsBeforeRevoke = harness.resolver.currentCoordinateCalls.count

        // Revoke permission: display clears (lastResolvedCoordinate is nil).
        harness.locationManager.authorizationStatus = .denied
        await waitUntil { viewModel.location == nil }
        #expect(viewModel.location == nil)

        // Re-grant permission. The stored coordinate is still the
        // pre-revocation (49.0, -123.0); the auth sink must not forward it.
        harness.locationManager.authorizationStatus = .authorizedWhenInUse
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(viewModel.location == nil,
                "Re-granting permission must not resolve the stale pre-revocation coordinate")
        #expect(harness.resolver.currentCoordinateCalls.count == callsBeforeRevoke,
                "No new resolution should occur on re-grant until a fresh fix arrives")

        // A fresh fix moved <5 km from the pre-revocation coordinate must now
        // resolve — invalidateCurrentLocationDisplay cleared
        // lastResolvedCoordinate, so the reuse guard must not suppress it.
        harness.locationManager.latitude = 49.004  // ~0.4 km north, well under 5 km
        await waitUntil { viewModel.location == Self.resolvedCurrent }

        #expect(viewModel.location == Self.resolvedCurrent,
                "A fresh post-grant fix under 5 km must resolve, not be suppressed by the reuse guard")
        #expect(harness.resolver.currentCoordinateCalls.count > callsBeforeRevoke,
                "The fresh post-grant fix must reach the resolver")
    }

    // MARK: - Current-mode calendar reset on first fix (P1)

    /// Regression: switching to Current mode from an already-fixed location
    /// must reset the calendar to the new Current destination's today. Without
    /// the mode-transition flag, the first GPS placemark kept the old
    /// destination's `selectedDate`/`windowStart`, so selecting Tokyo and then
    /// switching to Current in Vancouver computed Sun/Tides for Vancouver
    /// using Tokyo's calendar date (a cross-time-zone date-boundary bug).
    @Test func switchingToCurrentFromAFixedLocationResetsCalendarToCurrentDestinationToday() async {
        let harness = makeHarness()  // resolverLocation = resolvedCurrent (Vancouver)
        let viewModel = harness.viewModel

        viewModel.selectLocation(Self.tokyo)
        // Tokyo (UTC+9) today at the injected instant is Sep 15.
        #expect(viewModel.selectedDate == LocalDate(year: 2026, month: 9, day: 15),
                "Tokyo today at the injected instant is Sep 15")
        #expect(viewModel.location == Self.tokyo)

        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }

        // Vancouver (UTC-7) today at the injected instant is Sep 14. The first
        // Current-mode fix resets to Vancouver's today, not Tokyo's Sep 15.
        #expect(viewModel.location == Self.resolvedCurrent)
        #expect(viewModel.selectedDate == Self.todayLocal,
                "First Current-mode fix should reset to Vancouver today (Sep 14), not keep Tokyo's Sep 15")
    }

    /// Companion: later ≥5 km fixes after the first Current-mode fix preserve
    /// the user's chosen date (the reset is first-fix only, not every fix).
    @Test func laterCurrentModeFixesPreserveTheChosenDate() async {
        let harness = makeHarness()
        let viewModel = harness.viewModel

        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }
        #expect(viewModel.selectedDate == Self.todayLocal)

        // User picks a different day.
        let chosen = LocalDate(year: 2026, month: 9, day: 20)
        viewModel.selectDate(chosen)
        #expect(viewModel.selectedDate == chosen)

        // A ≥5 km move resolves again; the chosen date is preserved (not reset
        // to today).
        harness.locationManager.longitude = -123.16
        await waitUntil { harness.resolver.currentCoordinateCalls.count == 2 }
        #expect(viewModel.selectedDate == chosen,
                "Later Current-mode fixes must preserve the user's chosen date")
    }

    /// Regression (P1): Current → fixed → Current with UNCHANGED GPS
    /// coordinates must resolve the first fix of the new session. Without
    /// clearing `lastResolvedCoordinate` on re-entry, `stopCurrentLocationObservation`
    /// (called from `selectLocation` when leaving Current) leaves the old
    /// Current fix in `lastResolvedCoordinate`, so the replayed current
    /// coordinate is rejected by the <5 km reuse guard and the UI stays on
    /// the fixed location (and its calendar date) while preferences say
    /// Current until the device moves ≥5 km.
    @Test func currentToFixedToCurrentWithUnchangedGPSResolvesTheFirstFix() async {
        let harness = makeHarness()  // resolverLocation = resolvedCurrent (49.0, -123.0)
        let viewModel = harness.viewModel

        // Current(Vancouver): first fix resolves.
        harness.locationManager.latitude = 49.0
        harness.locationManager.longitude = -123.0
        viewModel.useCurrentLocation()
        await waitUntil { viewModel.location == Self.resolvedCurrent }
        #expect(viewModel.location == Self.resolvedCurrent)
        let callsAfterFirstCurrent = harness.resolver.currentCoordinateCalls.count
        #expect(callsAfterFirstCurrent >= 1)

        // fixed(Tokyo): leave Current mode. stopCurrentLocationObservation
        // does NOT clear lastResolvedCoordinate, so the Vancouver fix lingers.
        viewModel.selectLocation(Self.tokyo)
        #expect(viewModel.location == Self.tokyo)

        // Current(Vancouver) again with UNCHANGED GPS coordinates. The
        // replayed (49.0, -123.0) is <5 km from the lingering
        // lastResolvedCoordinate; without the session-start reset the reuse
        // guard would suppress it and the UI would stay on Tokyo.
        viewModel.useCurrentLocation()
        await waitUntil { harness.resolver.currentCoordinateCalls.count > callsAfterFirstCurrent }
        await waitUntil { viewModel.location == Self.resolvedCurrent }

        #expect(viewModel.location == Self.resolvedCurrent,
                "Re-entering Current with unchanged GPS must resolve the first fix, not stay on the previous fixed location")
        #expect(viewModel.selectedDate == Self.todayLocal,
                "The new Current session must reset to the Current destination's today, not keep Tokyo's date")
    }
}
