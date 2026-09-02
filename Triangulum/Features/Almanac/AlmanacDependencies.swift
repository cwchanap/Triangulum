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

    /// Production wiring. `enabledProviders` drives both the coverage model
    /// and client construction (Ruling A: one shared `TideDiskCache` threads
    /// into `TideService` AND the annual-source clients).
    static func live(enabledProviders: Set<TideProvider> = TideProvider.enabled) -> AlmanacDependencies {
        let cache = TideDiskCache(rootURL: cacheRootURL)
        var clients: [TideProvider: any TideProviderClient] = [:]
        if enabledProviders.contains(.canadaCHS) {
            clients[.canadaCHS] = CanadaTideClient(session: .shared)
        }
        if enabledProviders.contains(.unitedStatesNOAA) {
            clients[.unitedStatesNOAA] = UnitedStatesTideClient(session: .shared)
        }
        if enabledProviders.contains(.japanJMA) {
            clients[.japanJMA] = JapanTideClient(session: .shared, cache: cache)
        }
        if enabledProviders.contains(.hongKongHKO) {
            clients[.hongKongHKO] = HongKongTideClient(session: .shared, cache: cache)
        }
        return AlmanacDependencies(
            tideService: TideService(
                enabledProviders: enabledProviders,
                clients: clients,
                cache: cache,
                timeZoneResolver: TideStationTimeZoneResolver()
            ),
            locationResolver: AlmanacLocationResolver(),
            preferencesStore: AlmanacPreferencesStore(),
            now: Date.init
        )
    }

    /// Deterministic dependencies for UI tests: fixed Vancouver location and
    /// September 2026 clock, no network, no sensors.
    static func uiTestFixture() -> AlmanacDependencies {
        AlmanacDependencies(
            tideService: AlmanacFixtureTideService(),
            locationResolver: AlmanacFixtureLocationResolver(),
            preferencesStore: AlmanacPreferencesStore(),
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
