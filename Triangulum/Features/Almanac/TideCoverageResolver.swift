//
//  TideCoverageResolver.swift
//  Triangulum
//

import Foundation

/// Routes a destination to its tide provider using the injected enabled set,
/// so disabled-provider behavior stays directly testable and decoupled from
/// `TideProvider.enabled` (which is only the production default).
struct TideCoverageResolver {
    let enabledProviders: Set<TideProvider>

    func coverage(for location: AlmanacLocation) -> TideCoverage {
        guard let provider = provider(for: location) else { return .unsupportedRegion }
        return enabledProviders.contains(provider) ? .provider(provider) : .providerUnavailable(provider)
    }

    /// Hong Kong is resolved before the broader country so a Hong Kong
    /// administrative area attached to a "CN" country code still routes to
    /// HKO. Mainland China itself has no supported provider.
    private func provider(for location: AlmanacLocation) -> TideProvider? {
        if location.countryCode?.uppercased() == "HK" { return .hongKongHKO }
        if let area = location.administrativeArea,
           area.localizedCaseInsensitiveContains("Hong Kong") {
            return .hongKongHKO
        }
        switch location.countryCode?.uppercased() {
        case "CA": return .canadaCHS
        case "US": return .unitedStatesNOAA
        case "JP": return .japanJMA
        default: return nil
        }
    }
}
