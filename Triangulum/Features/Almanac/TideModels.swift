//
//  TideModels.swift
//  Triangulum
//

import Foundation

// MARK: - Event and source kinds

/// Whether a tide event is a high or a low water.
enum TideEventKind: String, Codable, Hashable { case high, low }

/// Which annual-source file shape a cached raw source came from: JMA's annual
/// text file (`annual`), or HKO's hourly / high-low CSV pair.
enum TideSourceKind: String, Codable, Hashable { case annual, hourly, hilo }

// MARK: - Coverage

/// The tide provider outcome for a destination, resolved from the injected
/// enabled set so disabled providers stay distinguishable from geography the
/// app simply cannot serve.
enum TideCoverage: Equatable {
    case provider(TideProvider)
    case providerUnavailable(TideProvider)
    case unsupportedRegion
}

// MARK: - Load errors

enum TideLoadError: Error, Equatable {
    case unsupportedRegion
    case providerUnavailable
    case noStationNearby
    case networkUnavailable
    case invalidProviderResponse
    case noPredictions
}

// MARK: - Stations and readings

/// One official tide station from a provider catalogue. `timeZoneIdentifier`
/// is optional because some catalogues omit it; it gets enriched after fetch
/// and persisted back into the station cache.
struct TideStation: Identifiable, Codable, Hashable {
    let id: String
    let provider: TideProvider
    let providerStationCode: String
    let name: String
    let latitude: Double
    let longitude: Double
    var timeZoneIdentifier: String?
    let datumLabel: String
    let supportsHourlyCurve: Bool

    var timeZone: TimeZone? { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) }
}

struct TideSample: Codable, Hashable { let instant: Date; let heightMetres: Double }
struct TideEvent: Codable, Hashable { let kind: TideEventKind; let instant: Date; let heightMetres: Double }

/// The provider fetch result: one station's predictions covering a
/// destination-local date range.
struct TideWeek: Codable, Hashable {
    let station: TideStation
    let localDateRange: LocalDateRange
    let hourlySamples: [TideSample]
    let events: [TideEvent]
    let fetchedAt: Date
    let sourceAttribution: String
}

/// The selected-day/display and normalized disk-cache unit: one destination
/// local calendar day of tide data for one station.
struct TideDay: Codable, Hashable {
    let station: TideStation
    let localDate: LocalDate
    let hourlySamples: [TideSample]
    let events: [TideEvent]
    let fetchedAt: Date
    let sourceAttribution: String
}
