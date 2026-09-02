//
//  TideCoverageResolverTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct TideCoverageResolverTests {

    // MARK: - Fixtures

    private func location(countryCode: String?, administrativeArea: String?) -> AlmanacLocation {
        AlmanacLocation(
            mode: .selected,
            latitude: 49.2827,
            longitude: -123.1207,
            displayName: "Test Location",
            timeZoneIdentifier: "America/Vancouver",
            countryCode: countryCode,
            administrativeArea: administrativeArea
        )
    }

    // MARK: - Jurisdiction routing with the injected enabled set

    @Test func canadaRoutesToCHSWhenInjectedSetContainsCHS() {
        let resolver = TideCoverageResolver(enabledProviders: [.canadaCHS])
        #expect(resolver.coverage(for: location(countryCode: "CA", administrativeArea: "British Columbia"))
            == .provider(.canadaCHS))
    }

    @Test func unitedStatesAndJapanRouteWhenEnabled() {
        let resolver = TideCoverageResolver(enabledProviders: [.unitedStatesNOAA, .japanJMA])
        #expect(resolver.coverage(for: location(countryCode: "US", administrativeArea: "California"))
            == .provider(.unitedStatesNOAA))
        #expect(resolver.coverage(for: location(countryCode: "JP", administrativeArea: "Tokyo"))
            == .provider(.japanJMA))
    }

    @Test func supportedProviderAbsentFromInjectedSetIsUnavailable() {
        let resolver = TideCoverageResolver(enabledProviders: [.japanJMA])
        #expect(resolver.coverage(for: location(countryCode: "CA", administrativeArea: nil))
            == .providerUnavailable(.canadaCHS))
        #expect(resolver.coverage(for: location(countryCode: "US", administrativeArea: nil))
            == .providerUnavailable(.unitedStatesNOAA))
    }

    @Test func outsideSupportedRegionsIsUnsupportedRegion() {
        let resolver = TideCoverageResolver(enabledProviders: TideProvider.enabled)
        #expect(resolver.coverage(for: location(countryCode: "FR", administrativeArea: nil)) == .unsupportedRegion)
        // Mainland China has no supported provider.
        #expect(resolver.coverage(for: location(countryCode: "CN", administrativeArea: "Guangdong"))
            == .unsupportedRegion)
        #expect(resolver.coverage(for: location(countryCode: nil, administrativeArea: nil)) == .unsupportedRegion)
    }

    @Test func hongKongFallbackRoutesBeforeBroaderChina() {
        let resolver = TideCoverageResolver(enabledProviders: TideProvider.enabled)
        // HK country code routes HKO…
        #expect(resolver.coverage(for: location(countryCode: "HK", administrativeArea: nil))
            == .provider(.hongKongHKO))
        // …and so does a Hong Kong administrative area attached to a "CN" country code.
        #expect(resolver.coverage(for: location(countryCode: "CN", administrativeArea: "Hong Kong"))
            == .provider(.hongKongHKO))
    }
}
