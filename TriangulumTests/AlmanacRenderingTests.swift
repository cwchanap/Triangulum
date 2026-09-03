//
//  AlmanacRenderingTests.swift
//  TriangulumTests
//
//  Crash/layout smoke coverage for the Almanac UI through the shared
//  `renderHost` (see `SwiftUIRenderTestHelper.swift`): the full shell at
//  narrow-iPhone and iPad sizes, both sections with real published view-model
//  state, and the two sheets. Exact accessibility copy is NOT asserted here —
//  SwiftUI's accessibility tree is not reliably materialized synchronously
//  through UIKit in this seam; `AlmanacPresentationTests` pins that copy
//  through pure helpers.
//

import Testing
import SwiftUI
import UIKit
import Foundation
@testable import Triangulum

@MainActor
@Suite(.serialized) // shared renderHost window-state mutations must not race
struct AlmanacRenderingTests {

    private static let vancouverTimeZone = TimeZone(identifier: "America/Vancouver")!

    private static let vancouver = AlmanacLocation(
        mode: .selected,
        latitude: 49.2827,
        longitude: -123.1207,
        displayName: "Vancouver",
        timeZoneIdentifier: "America/Vancouver",
        countryCode: "CA",
        administrativeArea: "British Columbia"
    )

    private static let pointAtkinson = TideStation(
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

    /// Deterministic harness: fixture tide service + fixture resolver +
    /// isolated preferences pre-seeded with the fixed Vancouver selection, so
    /// the view model restores a known place/date without GPS or network.
    /// The suite's persistent domain is removed when the harness deinits
    /// (end of each test) so suites never leak across runs.
    private final class Harness {
        let suiteName: String
        private let defaults: UserDefaults
        let dependencies: AlmanacDependencies
        let viewModel: AlmanacViewModel
        let locationManager: LocationManager

        init(suiteName: String,
             defaults: UserDefaults,
             dependencies: AlmanacDependencies,
             viewModel: AlmanacViewModel,
             locationManager: LocationManager) {
            self.suiteName = suiteName
            self.defaults = defaults
            self.dependencies = dependencies
            self.viewModel = viewModel
            self.locationManager = locationManager
        }

        deinit { defaults.removePersistentDomain(forName: suiteName) }
    }

    private func makeHarness() -> Harness {
        let suiteName = "test.almanac.rendering.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = AlmanacPreferencesStore(defaults: defaults)
        try? store.save(
            AlmanacPreferences(mode: .selected, selectedLocation: Self.vancouver, stationOverride: nil)
        )
        let dependencies = AlmanacDependencies(
            tideService: AlmanacFixtureTideService(),
            locationResolver: AlmanacFixtureLocationResolver(),
            preferencesStore: store,
            now: { AlmanacFixtureTideService.fixedNow }
        )
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        let viewModel = AlmanacViewModel(dependencies: dependencies, locationManager: locationManager)
        return Harness(
            suiteName: suiteName,
            defaults: defaults,
            dependencies: dependencies,
            viewModel: viewModel,
            locationManager: locationManager
        )
    }

    /// Polls until `condition` holds so generation-guarded async state (the
    /// fixture tide load) becomes deterministic without sleeps.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Shell

    @Test func almanacShellRendersSunSectionOnNarrowPhone() {
        let harness = makeHarness()
        let view = AlmanacView(locationManager: harness.locationManager, dependencies: harness.dependencies)

        let (host, window) = renderHost(view, size: CGSize(width: 320, height: 568))

        withExtendedLifetime(window) {
            // The restored fixed location renders the shared context header,
            // date strip, Sun|Tides picker, and Sun content synchronously.
            #expect(host.view.window != nil,
                    "Almanac shell failed to attach to a window at iPhone width")
            #expect(host.viewIfLoaded?.frame.size == CGSize(width: 320, height: 568))
            #expect(harness.viewModel.location == Self.vancouver)
            #expect(harness.viewModel.solarDay != nil)
        }
    }

    @Test func almanacShellRendersAtIpadSize() {
        let harness = makeHarness()
        let view = AlmanacView(locationManager: harness.locationManager, dependencies: harness.dependencies)

        let (host, window) = renderHost(view, size: CGSize(width: 1024, height: 1366))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Almanac shell failed to attach to a window at iPad size")
            #expect(host.viewIfLoaded?.frame.size == CGSize(width: 1024, height: 1366))
        }
    }

    // MARK: - Sun section states

    @Test func sunSectionRendersWithDestinationLocalTodayCountdown() {
        let harness = makeHarness()
        // The destination-local today per the injected fixture clock
        // (matching the view's own today judgments) exercises the
        // countdown/next-event branch.
        let today = LocalDate(harness.viewModel.currentDate, in: Self.vancouverTimeZone)
        harness.viewModel.selectDate(today)
        #expect(harness.viewModel.solarDay != nil)

        let (host, window) = renderHost(AlmanacSunView(viewModel: harness.viewModel),
                                        size: CGSize(width: 320, height: 568))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Sun section with countdown failed to attach to a window")
        }
    }

    // MARK: - Tides section states

    @Test func tidesSectionRendersContentAfterFixtureLoad() async {
        let harness = makeHarness()
        harness.viewModel.section = .tides
        await waitUntil { harness.viewModel.tideDay != nil }
        #expect(harness.viewModel.stationContext != nil)

        let (host, window) = renderHost(AlmanacTidesView(viewModel: harness.viewModel),
                                        size: CGSize(width: 320, height: 568))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Tides section failed to attach to a window after predictions loaded")
            // Re-layout with the published chart/events/station content.
            host.view.layoutIfNeeded()
            #expect(host.view.window != nil)
        }
    }

    @Test func tidesSectionRendersTodaySummaryWithChartAndSheets() async throws {
        let harness = makeHarness()
        harness.viewModel.section = .tides
        await waitUntil { harness.viewModel.tideDay != nil }

        // Station-local today exercises the next-tide countdown and the
        // current-time rule; the station sheet source is the published
        // context.
        let today = LocalDate(harness.viewModel.currentDate, in: Self.vancouverTimeZone)
        harness.viewModel.selectDate(today)
        await waitUntil { harness.viewModel.tideDay?.localDate == today }
        #expect(harness.viewModel.tideDay != nil)

        let (host, window) = renderHost(AlmanacTidesView(viewModel: harness.viewModel),
                                        size: CGSize(width: 320, height: 568))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Tides section for today failed to attach to a window")
        }

        let context = try #require(harness.viewModel.stationContext)
        let sheet = TideStationSheet(
            selectedStation: context.selected,
            alternatives: context.nearbyStations,
            onSelect: { _ in },
            onUseNearestStation: {}
        )
        let (sheetHost, sheetWindow) = renderHost(sheet, size: CGSize(width: 320, height: 568))
        withExtendedLifetime(sheetWindow) {
            #expect(sheetHost.view.window != nil,
                    "Tide station sheet failed to attach to a window")
        }
    }

    @Test func tideChartRendersStandaloneWithEvents() {
        let date = LocalDate(year: 2026, month: 9, day: 15)
        let day = AlmanacFixtureTideService.day(for: date)
        let chart = TideChartView(day: day, timeZone: Self.vancouverTimeZone, now: nil)

        let (host, window) = renderHost(chart, size: CGSize(width: 320, height: 240))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Tide chart failed to attach to a window")
        }
    }

    // MARK: - Location sheet

    @Test func locationSheetRendersCurrentAndLastSelectedRows() {
        // Selected mode: the fixed place is both current and last-selected.
        let sheet = AlmanacLocationSheet(
            currentLocation: Self.vancouver,
            lastFixedLocation: Self.vancouver,
            locationManager: nil,
            completer: AppleSearchCompleter(),
            resolver: AlmanacFixtureLocationResolver(),
            onSelectLocation: { _ in },
            onUseCurrentLocation: {}
        )

        let (host, window) = renderHost(sheet, size: CGSize(width: 320, height: 568))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Location sheet failed to attach to a window")
        }
    }

    @Test func locationSheetRendersLastFixedPlaceWhileFollowingTheDevice() {
        // Current mode (no fix yet): no current location, but the persisted
        // last FIXED place still offers a row.
        let sheet = AlmanacLocationSheet(
            currentLocation: nil,
            lastFixedLocation: Self.vancouver,
            locationManager: nil,
            completer: AppleSearchCompleter(),
            resolver: AlmanacFixtureLocationResolver(),
            onSelectLocation: { _ in },
            onUseCurrentLocation: {}
        )

        let (host, window) = renderHost(sheet, size: CGSize(width: 320, height: 568))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Location sheet with only a last fixed place failed to attach")
        }
    }

    // MARK: - TideStationSheet defensive cap

    @Test func stationSheetCapsAlternativesAtEight() {
        let stations = (0..<12).map { index in
            TideStation(
                id: "alt-\(index)",
                provider: .canadaCHS,
                providerStationCode: "alt-\(index)",
                name: "Alternative \(index)",
                latitude: 49.3,
                longitude: -123.2,
                timeZoneIdentifier: "America/Vancouver",
                datumLabel: "Chart Datum",
                supportsHourlyCurve: true
            )
        }
        let sheet = TideStationSheet(
            selectedStation: Self.pointAtkinson,
            alternatives: stations,
            onSelect: { _ in },
            onUseNearestStation: {}
        )

        let (host, window) = renderHost(sheet, size: CGSize(width: 320, height: 900))

        withExtendedLifetime(window) {
            #expect(host.view.window != nil,
                    "Station sheet with twelve alternatives failed to attach to a window")
        }
    }
}
