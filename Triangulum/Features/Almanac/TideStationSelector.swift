//
//  TideStationSelector.swift
//  Triangulum
//

import CoreLocation
import Foundation

/// Picks the nearest eligible tide station for a location and the sorted
/// alternatives shown for a manual override. Eligibility requires an hourly
/// curve; automatic matches beyond 250 km are rejected outright.
struct TideStationSelector {
    static let maximumAutomaticDistanceMetres = 250_000.0
    static let maximumAlternatives = 8

    func select(
        from stations: [TideStation],
        latitude: Double,
        longitude: Double
    ) -> (selected: TideStation?, alternatives: [TideStation]) {
        let origin = CLLocation(latitude: latitude, longitude: longitude)
        let eligible = stations
            .filter(\.supportsHourlyCurve)
            .map { (station: $0, distance: origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.distance <= Self.maximumAutomaticDistanceMetres }
            .sorted { $0.distance < $1.distance }

        guard let nearest = eligible.first else { return (nil, []) }
        let alternatives = eligible.dropFirst().prefix(Self.maximumAlternatives).map(\.station)
        return (nearest.station, alternatives)
    }
}
