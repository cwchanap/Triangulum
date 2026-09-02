//
//  TideStationTimeZoneResolverTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

/// The resolver is stateless: an existing catalogue identifier short-circuits
/// (JMA/HKO compiled stations bypass geocoding); anything else is passed
/// through verbatim for the service layer to validate and persist. The
/// CLGeocoder path itself needs network and has no injection seam, so it is
/// exercised only in production.
struct TideStationTimeZoneResolverTests {

    @Test func returnsExistingZoneIdentifierImmediately() async throws {
        // JMA stations are compiled with their fixed zone.
        let tokyo = try #require(JapanTideStations.all.first { $0.providerStationCode == "TK" })
        let resolver = TideStationTimeZoneResolver()

        let identifier = try await resolver.resolveIdentifier(for: tokyo)

        #expect(identifier == "Asia/Tokyo")
    }

    @Test func returnsIdentifierVerbatimWithoutValidation() async throws {
        // Contract: the resolver returns the stored identifier as-is; the
        // service decides whether it names a valid IANA zone.
        let station = TideStation(
            id: "X",
            provider: .canadaCHS,
            providerStationCode: "X",
            name: "Odd",
            latitude: 49.2827,
            longitude: -123.1207,
            timeZoneIdentifier: "Not/AZone",
            datumLabel: "Chart Datum",
            supportsHourlyCurve: true
        )
        let resolver = TideStationTimeZoneResolver()

        let identifier = try await resolver.resolveIdentifier(for: station)

        #expect(identifier == "Not/AZone")
    }
}
