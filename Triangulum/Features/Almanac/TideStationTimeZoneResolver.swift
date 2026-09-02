//
//  TideStationTimeZoneResolver.swift
//

import CoreLocation
import Foundation

/// Resolves a station's IANA time-zone identifier. Stateless by design: an
/// identifier already present in the station row is returned immediately
/// (JMA/HKO compiled catalogues bypass geocoding this way), and otherwise the
/// selected station's coordinate is reverse geocoded exactly once. The
/// resolver stores nothing — `TideService` persists the result through
/// `TideDiskCache.updateCatalogTimeZone`, making the cached catalogue the
/// single persistence source of truth for enrichment.
protocol TideStationTimeZoneResolving {
    func resolveIdentifier(for station: TideStation) async throws -> String
}

final class TideStationTimeZoneResolver: TideStationTimeZoneResolving {

    func resolveIdentifier(for station: TideStation) async throws -> String {
        if let existing = station.timeZoneIdentifier {
            return existing
        }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: station.latitude, longitude: station.longitude)
            )
            guard let identifier = placemarks.first?.timeZone?.identifier else {
                // A successful lookup that still yields no zone is the same
                // user-facing outcome as a failed one.
                throw TideLoadError.networkUnavailable
            }
            return identifier
        } catch let error as TideLoadError {
            throw error
        } catch {
            // No dedicated geocode case exists in `TideLoadError`; reverse
            // geocoding is network-backed, so `.networkUnavailable` is the
            // closest stable category. Add a dedicated case only if the view
            // model ever needs to distinguish geocoding from provider fetches.
            throw TideLoadError.networkUnavailable
        }
    }
}
