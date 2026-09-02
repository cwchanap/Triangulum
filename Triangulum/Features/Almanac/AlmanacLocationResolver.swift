//
//  AlmanacLocationResolver.swift
//

import CoreLocation
import Foundation
import MapKit

/// Stable location-resolution failures for the Almanac. Kept separate from
/// `TideLoadError`: a place whose zone cannot be resolved is not a network
/// problem, and the location sheet distinguishes lookup failure from
/// rejection.
enum AlmanacLocationError: Error, Equatable {
    /// The search or geocode lookup returned nothing usable.
    case lookupFailed
    /// Both the primary lookup and the one reverse-geocode fallback lacked a
    /// time zone — the selection is rejected. Never substitute
    /// `TimeZone.current` for a remote place.
    case timeZoneUnavailable
}

protocol AlmanacLocationResolving {
    func resolveSearchCompletion(_ completion: MKLocalSearchCompletion) async throws -> AlmanacLocation
    func resolveCurrentCoordinate(_ coordinate: CLLocationCoordinate2D) async throws -> AlmanacLocation
}

/// Resolves MapKit search completions and current GPS coordinates into
/// `AlmanacLocation` values: coordinate, display name, country/administrative
/// area, and placemark time zone. When the first lookup lacks a time zone, one
/// reverse-geocode fallback runs; a still-zoneless place is rejected.
final class AlmanacLocationResolver: AlmanacLocationResolving {

    /// What the resolver learned from one placemark lookup, decoupled from
    /// `CLPlacemark`/`MKPlacemark` so the fallback/rejection policy is testable
    /// without hitting Apple's un-stubbable network classes.
    struct PlacemarkSnapshot {
        let coordinate: CLLocationCoordinate2D
        let timeZone: TimeZone?
        let countryCode: String?
        let administrativeArea: String?
        let displayName: String?
    }

    func resolveSearchCompletion(_ completion: MKLocalSearchCompletion) async throws -> AlmanacLocation {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try await search.start().mapItems.first,
              let coordinate = item.placemark.location?.coordinate else {
            throw AlmanacLocationError.lookupFailed
        }
        let primary = PlacemarkSnapshot(
            coordinate: coordinate,
            timeZone: item.placemark.timeZone,
            countryCode: item.placemark.isoCountryCode,
            administrativeArea: item.placemark.administrativeArea,
            displayName: item.name
        )
        return try await assemble(primary: primary, mode: .selected)
    }

    func resolveCurrentCoordinate(_ coordinate: CLLocationCoordinate2D) async throws -> AlmanacLocation {
        let primary = try await reverseGeocode(coordinate: coordinate, displayName: nil)
        return try await assemble(primary: primary, mode: .current)
    }

    /// Shared tail: the primary lookup usually carries a zone; only its
    /// absence triggers the single reverse-geocode fallback.
    private func assemble(primary: PlacemarkSnapshot, mode: AlmanacLocationMode) async throws -> AlmanacLocation {
        if primary.timeZone != nil {
            return try Self.assembleLocation(primary: primary, fallback: nil, mode: mode)
        }
        let fallback = try await reverseGeocode(coordinate: primary.coordinate, displayName: nil)
        return try Self.assembleLocation(primary: primary, fallback: fallback, mode: mode)
    }

    /// Pure mapping/policy core (unit-tested): primary fields win, the one
    /// fallback fills gaps, and a zoneless outcome is a stable rejection.
    static func assembleLocation(
        primary: PlacemarkSnapshot,
        fallback: PlacemarkSnapshot?,
        mode: AlmanacLocationMode
    ) throws -> AlmanacLocation {
        guard let timeZone = primary.timeZone ?? fallback?.timeZone else {
            throw AlmanacLocationError.timeZoneUnavailable
        }
        return AlmanacLocation(
            mode: mode,
            latitude: primary.coordinate.latitude,
            longitude: primary.coordinate.longitude,
            displayName: primary.displayName ?? fallback?.displayName ?? "Unnamed place",
            timeZoneIdentifier: timeZone.identifier,
            countryCode: primary.countryCode ?? fallback?.countryCode,
            administrativeArea: primary.administrativeArea ?? fallback?.administrativeArea
        )
    }

    private func reverseGeocode(coordinate: CLLocationCoordinate2D, displayName: String?) async throws -> PlacemarkSnapshot {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            guard let placemark = placemarks.first, placemark.location != nil else {
                throw AlmanacLocationError.lookupFailed
            }
            return PlacemarkSnapshot(
                coordinate: coordinate,
                timeZone: placemark.timeZone,
                countryCode: placemark.isoCountryCode,
                administrativeArea: placemark.administrativeArea,
                displayName: displayName ?? placemark.name
            )
        } catch let error as AlmanacLocationError {
            throw error
        } catch {
            throw AlmanacLocationError.lookupFailed
        }
    }
}
