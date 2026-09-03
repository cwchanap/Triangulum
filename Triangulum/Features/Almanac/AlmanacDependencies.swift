//
//  AlmanacDependencies.swift
//

import CoreLocation
import Foundation
import MapKit

/// Feature-local dependency value for the Almanac: one tide service, one
/// location resolver, the preferences store, and the clock. Constructed once
/// per app launch; `-ui-testing` alone selects `.uiTestFixture()` (wired in
/// ContentView during Task 9).
struct AlmanacDependencies {
    let tideService: any TideServing
    let locationResolver: any AlmanacLocationResolving
    let preferencesStore: AlmanacPreferencesStore
    let now: () -> Date

    /// Production wiring. `enabledProviders` drives the coverage model and
    /// gates dispatch; clients are cheap to construct, so every provider gets
    /// one unconditionally and the enabled set decides which are ever used
    /// (Ruling A: one shared `TideDiskCache` threads into `TideService` AND
    /// the annual-source clients).
    static func live(enabledProviders: Set<TideProvider> = TideProvider.enabled) -> AlmanacDependencies {
        let cache = TideDiskCache(rootURL: cacheRootURL)
        return AlmanacDependencies(
            tideService: TideService(
                enabledProviders: enabledProviders,
                chsClient: CanadaTideClient(session: .shared),
                noaaClient: UnitedStatesTideClient(session: .shared),
                jmaClient: JapanTideClient(session: .shared, cache: cache),
                hkoClient: HongKongTideClient(session: .shared, cache: cache),
                cache: cache,
                timeZoneResolver: TideStationTimeZoneResolver()
            ),
            locationResolver: AlmanacLocationResolver(),
            preferencesStore: AlmanacPreferencesStore(),
            now: Date.init
        )
    }

    /// Deterministic dependencies for UI tests: fixed Vancouver location and
    /// September 2026 clock, no network, no sensors. The fixed Vancouver
    /// selection is persisted before the view model loads, so a fresh
    /// `-ui-testing` launch restores the same place/date the smoke test
    /// asserts — no GPS fix, permission prompt, or extra launch flag needed.
    static func uiTestFixture() -> AlmanacDependencies {
        let store = AlmanacPreferencesStore()
        try? store.save(
            AlmanacPreferences(
                mode: .selected,
                selectedLocation: AlmanacFixtureLocationResolver.vancouver,
                stationOverride: nil
            )
        )
        return AlmanacDependencies(
            tideService: AlmanacFixtureTideService(),
            locationResolver: AlmanacFixtureLocationResolver(),
            preferencesStore: store,
            now: { AlmanacFixtureTideService.fixedNow }
        )
    }

    private static var cacheRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Almanac/Tides", isDirectory: true)
    }
}

/// Network-free resolver always answering with the fixture Vancouver place.
struct AlmanacFixtureLocationResolver: AlmanacLocationResolving {
    static let vancouver = AlmanacLocation(
        mode: .selected,
        latitude: 49.2827,
        longitude: -123.1207,
        displayName: "Vancouver",
        timeZoneIdentifier: "America/Vancouver",
        countryCode: "CA",
        administrativeArea: "British Columbia"
    )

    func resolveSearchCompletion(_ completion: MKLocalSearchCompletion) async throws -> AlmanacLocation {
        Self.vancouver
    }

    func resolveCurrentCoordinate(_ coordinate: CLLocationCoordinate2D) async throws -> AlmanacLocation {
        Self.vancouver
    }
}
