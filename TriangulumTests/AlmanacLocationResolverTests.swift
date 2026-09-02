//
//  AlmanacLocationResolverTests.swift
//  TriangulumTests
//

import Testing
import Foundation
import CoreLocation
import MapKit
@testable import Triangulum

/// Tests for the pure mapping/policy core of `AlmanacLocationResolver`.
///
/// Untestable network paths (same seam limitation as Task 6): `MKLocalSearch`
/// and `CLGeocoder` are Apple classes with no injectable session or protocol
/// seam, so `resolveSearchCompletion`/`resolveCurrentCoordinate` network
/// entry points are kept to three thin lines each (start lookup, extract,
/// delegate to the policy core) and are exercised only in UI tests. What IS
/// pinned here: placemark-to-`AlmanacLocation` mapping, the
/// exactly-one-reverse-geocode fallback rule, and the stable rejection when
/// both lookups lack a time zone.
struct AlmanacLocationResolverTests {

    private static let coordinate = CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207)

    private func snapshot(
        timeZone: TimeZone? = nil,
        countryCode: String? = nil,
        administrativeArea: String? = nil,
        displayName: String? = nil,
        coordinate: CLLocationCoordinate2D = Self.coordinate
    ) -> AlmanacLocationResolver.PlacemarkSnapshot {
        AlmanacLocationResolver.PlacemarkSnapshot(
            coordinate: coordinate,
            timeZone: timeZone,
            countryCode: countryCode,
            administrativeArea: administrativeArea,
            displayName: displayName
        )
    }

    // MARK: - Mapping

    @Test func mapsPlacemarkFieldsIntoLocation() throws {
        let location = try AlmanacLocationResolver.assembleLocation(
            primary: snapshot(
                timeZone: TimeZone(identifier: "America/Vancouver"),
                countryCode: "CA",
                administrativeArea: "British Columbia",
                displayName: "Vancouver"
            ),
            fallback: nil,
            mode: .selected
        )

        #expect(location.mode == .selected)
        #expect(location.latitude == Self.coordinate.latitude)
        #expect(location.longitude == Self.coordinate.longitude)
        #expect(location.displayName == "Vancouver")
        #expect(location.timeZoneIdentifier == "America/Vancouver")
        #expect(location.countryCode == "CA")
        #expect(location.administrativeArea == "British Columbia")
    }

    @Test func keepsCurrentModeForCurrentCoordinateResolution() throws {
        let location = try AlmanacLocationResolver.assembleLocation(
            primary: snapshot(timeZone: TimeZone(identifier: "Asia/Tokyo"), displayName: "Tokyo"),
            fallback: nil,
            mode: .current
        )
        #expect(location.mode == .current)
    }

    // MARK: - Time-zone fallback policy

    @Test func primaryTimeZoneIsUsedWithoutConsultingFallback() throws {
        let fallback = snapshot(timeZone: TimeZone(identifier: "Europe/Paris"), displayName: "Fallback name")
        let location = try AlmanacLocationResolver.assembleLocation(
            primary: snapshot(timeZone: TimeZone(identifier: "America/Vancouver"), displayName: "Vancouver"),
            fallback: fallback,
            mode: .selected
        )
        #expect(location.timeZoneIdentifier == "America/Vancouver")
        #expect(location.displayName == "Vancouver")
    }

    @Test func fallbackTimeZoneIsUsedWhenPrimaryLacksOne() throws {
        let fallback = snapshot(
            timeZone: TimeZone(identifier: "America/Vancouver"),
            countryCode: "CA",
            administrativeArea: "British Columbia",
            displayName: "Fallback name"
        )
        let location = try AlmanacLocationResolver.assembleLocation(
            primary: snapshot(countryCode: nil, displayName: nil),
            fallback: fallback,
            mode: .selected
        )
        #expect(location.timeZoneIdentifier == "America/Vancouver")
        // Primary fields win; fallback only fills gaps.
        #expect(location.countryCode == "CA")
        #expect(location.administrativeArea == "British Columbia")
        #expect(location.displayName == "Fallback name")
    }

    @Test func remotePlaceWithoutResolvableTimeZoneIsRejected() {
        #expect(throws: AlmanacLocationError.timeZoneUnavailable) {
            try AlmanacLocationResolver.assembleLocation(
                primary: snapshot(timeZone: nil, displayName: "Nowhere"),
                fallback: snapshot(timeZone: nil, displayName: "Nowhere again"),
                mode: .selected
            )
        }
    }

    @Test func primaryTimeZoneNilWithNoFallbackIsRejected() {
        #expect(throws: AlmanacLocationError.timeZoneUnavailable) {
            try AlmanacLocationResolver.assembleLocation(
                primary: snapshot(timeZone: nil, displayName: "Nowhere"),
                fallback: nil,
                mode: .current
            )
        }
    }
}
