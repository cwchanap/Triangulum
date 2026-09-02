//
//  AlmanacPreferencesStoreTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct AlmanacPreferencesStoreTests {

    // Private suite per test so UserDefaults state never leaks between tests
    // and never touches .standard.
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test.almanac.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    private func makeSampleLocation() -> AlmanacLocation {
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

    @Test func loadReturnsDefaultWhenNothingStored() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(AlmanacPreferencesStore(defaults: defaults).load() == .default)
    }

    @Test func defaultIsCurrentModeWithoutSelection() {
        #expect(AlmanacPreferences.default.mode == .current)
        #expect(AlmanacPreferences.default.selectedLocation == nil)
        #expect(AlmanacPreferences.default.stationOverride == nil)
    }

    @Test func roundTripsPreferences() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AlmanacPreferencesStore(defaults: defaults)
        let preferences = AlmanacPreferences(
            mode: .selected,
            selectedLocation: makeSampleLocation(),
            stationOverride: TideStationOverride(
                stationID: "CHS-07385",
                anchorLatitude: 49.3,
                anchorLongitude: -123.2
            )
        )

        try store.save(preferences)
        #expect(store.load() == preferences)
    }

    @Test func stationOverridePersistsAcrossStoreInstances() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let override = TideStationOverride(
            stationID: "NOAA-9447130",
            anchorLatitude: 47.6062,
            anchorLongitude: -122.3321
        )
        try AlmanacPreferencesStore(defaults: defaults).save(
            AlmanacPreferences(mode: .selected, selectedLocation: nil, stationOverride: override)
        )

        let reloaded = AlmanacPreferencesStore(defaults: defaults).load()
        #expect(reloaded.stationOverride == override)
        #expect(reloaded.mode == .selected)
    }

    @Test func corruptJSONFallsBackToDefault() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not json".utf8), forKey: AlmanacPreferencesStore.key)
        #expect(AlmanacPreferencesStore(defaults: defaults).load() == .default)
    }

    @Test func timeZoneResolvesFromIdentifier() {
        #expect(makeSampleLocation().timeZone?.identifier == "America/Vancouver")

        let unknown = AlmanacLocation(
            mode: .current,
            latitude: 0,
            longitude: 0,
            displayName: "Nowhere",
            timeZoneIdentifier: "Not/AZone",
            countryCode: nil,
            administrativeArea: nil
        )
        #expect(unknown.timeZone == nil)
    }
}
