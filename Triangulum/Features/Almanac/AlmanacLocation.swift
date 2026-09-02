//
//  AlmanacLocation.swift
//  Triangulum
//

import Foundation

/// Whether the Almanac follows the device's current location or a
/// user-selected destination.
enum AlmanacLocationMode: String, Codable {
    case current
    case selected
}

/// A named destination with the time zone needed to compute destination-local
/// dates for sun and tide events.
struct AlmanacLocation: Codable, Hashable {
    let mode: AlmanacLocationMode
    let latitude: Double
    let longitude: Double
    let displayName: String
    let timeZoneIdentifier: String
    let countryCode: String?
    let administrativeArea: String?

    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
}

/// A user-pinned tide station near the selected location, so predictions come
/// from an authoritative station instead of the nearest interpolated point.
struct TideStationOverride: Codable, Hashable {
    let stationID: String
    let anchorLatitude: Double
    let anchorLongitude: Double
}

/// The persisted Almanac selection state.
struct AlmanacPreferences: Codable, Hashable {
    let mode: AlmanacLocationMode
    let selectedLocation: AlmanacLocation?
    let stationOverride: TideStationOverride?

    static let `default` = AlmanacPreferences(
        mode: .current,
        selectedLocation: nil,
        stationOverride: nil
    )
}

/// Loads and saves `AlmanacPreferences` as one JSON value in UserDefaults.
struct AlmanacPreferencesStore {
    static let key = "almanac.preferences.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AlmanacPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(AlmanacPreferences.self, from: data) else {
            return .default
        }
        return value
    }

    func save(_ value: AlmanacPreferences) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: Self.key)
    }
}
