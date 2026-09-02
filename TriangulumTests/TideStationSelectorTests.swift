//
//  TideStationSelectorTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct TideStationSelectorTests {

    // MARK: - Fixtures

    /// All fixtures share Vancouver's longitude so distances come purely from
    /// latitude offsets (1° ≈ 111 km).
    private func station(id: String, latitude: Double, supportsHourlyCurve: Bool = true) -> TideStation {
        TideStation(
            id: id,
            provider: .canadaCHS,
            providerStationCode: id,
            name: "Station \(id)",
            latitude: latitude,
            longitude: -123.1207,
            timeZoneIdentifier: "America/Vancouver",
            datumLabel: "Chart Datum",
            supportsHourlyCurve: supportsHourlyCurve
        )
    }

    // MARK: - Selection constants

    @Test func automaticLimitsMatchTheBrief() {
        #expect(TideStationSelector.maximumAutomaticDistanceMetres == 250_000.0)
        #expect(TideStationSelector.maximumAlternatives == 8)
    }

    // MARK: - Nearest eligible selection

    @Test func nearestEligibleStationWithin250kmIsSelected() {
        let selector = TideStationSelector()
        let noHourlyCurve = station(id: "no-hourly", latitude: 49.28, supportsHourlyCurve: false)
        let near = station(id: "near", latitude: 49.29)          // ≈ 1 km
        let farther = station(id: "farther", latitude: 49.31)    // ≈ 3 km
        let beyondLimit = station(id: "beyond", latitude: 52.5)  // ≈ 358 km

        let result = selector.select(
            from: [farther, beyondLimit, noHourlyCurve, near],
            latitude: 49.2827,
            longitude: -123.1207
        )

        // The nearest overall lacks an hourly curve and is filtered out;
        // the eligible nearest wins.
        #expect(result.selected?.id == "near")
        #expect(result.alternatives.map(\.id) == ["farther"])
    }

    @Test func stationBeyond250kmIsRejected() {
        let selector = TideStationSelector()
        let far = station(id: "far", latitude: 52.5) // ≈ 358 km from Vancouver

        let result = selector.select(from: [far], latitude: 49.2827, longitude: -123.1207)

        #expect(result.selected == nil)
        #expect(result.alternatives.isEmpty)
    }

    @Test func atMostEightSortedAlternativesAreReturned() {
        let selector = TideStationSelector()
        let stations = (0..<12).map { station(id: "s\($0)", latitude: 49.29 + Double($0) * 0.02) }

        let result = selector.select(from: stations, latitude: 49.2827, longitude: -123.1207)

        #expect(result.selected?.id == "s0")
        #expect(result.alternatives.count == TideStationSelector.maximumAlternatives)
        // Sorted by distance: the second- through ninth-nearest, nearest excluded.
        #expect(result.alternatives.map(\.id) == (1...8).map { "s\($0)" })
    }

    @Test func emptyInputSelectsNothing() {
        let selector = TideStationSelector()
        let result = selector.select(from: [], latitude: 49.2827, longitude: -123.1207)
        #expect(result.selected == nil)
        #expect(result.alternatives.isEmpty)
    }
}
