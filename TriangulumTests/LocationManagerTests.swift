//
//  LocationManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 7/8/2025.
//

import Testing
import Foundation
import CoreLocation
import UIKit
@testable import Triangulum

@Suite(.serialized)
struct LocationManagerTests {

    private func waitForAvailabilityToMatchSystem(_ manager: LocationManager) async {
        for _ in 0..<50 {
            if manager.isAvailable == CLLocationManager.locationServicesEnabled() {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func assertAuthorizationStatus(_ manager: LocationManager, expected: CLAuthorizationStatus) {
        #expect(manager.authorizationStatus == expected)

        switch expected {
        case .authorizedWhenInUse, .authorizedAlways, .notDetermined:
            #expect(manager.errorMessage.isEmpty)
        case .denied, .restricted:
            #expect(manager.errorMessage.isEmpty == false)
        @unknown default:
            break
        }
    }

    @Test func testLocationManagerInitialization() {
        let manager = LocationManager()

        #expect(manager.latitude == 0.0)
        #expect(manager.longitude == 0.0)
        #expect(manager.altitude == 0.0)
        #expect(manager.accuracy == 0.0)
        #expect(manager.errorMessage == "")
    }

    @Test func testAvailabilityCheck() async {
        let manager = LocationManager()

        // Wait for async availability check to settle against the current system state.
        await waitForAvailabilityToMatchSystem(manager)

        #expect(manager.isAvailable == CLLocationManager.locationServicesEnabled())
    }

    @Test func testAuthorizationStatusInitialization() {
        let manager = LocationManager()
        let validStatuses: [CLAuthorizationStatus] = [
            .notDetermined,
            .authorizedWhenInUse,
            .authorizedAlways,
            .restricted,
            .denied
        ]
        #expect(validStatuses.contains(manager.authorizationStatus))
    }

    @Test func testLocationUnavailableError() async {
        let manager = LocationManager()

        await waitForAvailabilityToMatchSystem(manager)

        if !CLLocationManager.locationServicesEnabled() {
            manager.startLocationUpdates()
            // Wait for async error message to be set
            try? await Task.sleep(for: .milliseconds(100))
            #expect(manager.errorMessage == "Location services not available")
        }
    }

    @Test func testLocationPermissionDeniedError() {
        let manager = LocationManager()

        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            manager.startLocationUpdates()
            #expect(manager.errorMessage.contains("permission") ||
                        manager.errorMessage.contains("denied"))
        }
    }

    @Test func testStopLocationUpdates() {
        let manager = LocationManager()

        manager.stopLocationUpdates()
    }

    @Test func testLocationManagerDelegate() {
        let manager = LocationManager()
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        manager.locationManager(CLLocationManager(), didUpdateLocations: [mockLocation])

        #expect(manager.latitude == 37.7749)
        #expect(manager.longitude == -122.4194)
        #expect(manager.altitude == mockLocation.altitude)
        #expect(manager.accuracy == max(0, mockLocation.horizontalAccuracy))
        #expect(manager.errorMessage == "")
    }

    @Test func testLocationManagerError() {
        let manager = LocationManager()
        let error = CLError(.locationUnknown)

        manager.locationManager(CLLocationManager(), didFailWithError: error)

        #expect(manager.errorMessage.contains("Location error"))
    }

    @Test func testAuthorizationStatusChange() {
        let manager = LocationManager(skipAvailabilityCheck: true)

        // With skipAvailabilityCheck: true, checkAvailability() is never called,
        // so authorizationStatus is set synchronously by the delegate method.
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        assertAuthorizationStatus(manager, expected: .denied)
    }

    @Test func testLocationUpdateWithAccuracy() {
        let manager = LocationManager()
        let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let location2 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                                   altitude: 10.0,
                                   horizontalAccuracy: 5.0,
                                   verticalAccuracy: 3.0,
                                   timestamp: Date())

        manager.locationManager(CLLocationManager(), didUpdateLocations: [location1, location2])

        // Should use the last location
        #expect(manager.latitude == 40.7128)
        #expect(manager.longitude == -74.0060)
        #expect(manager.altitude == 10.0)
        #expect(manager.accuracy == 5.0)
    }

    @Test func testValidLocationAllowsZeroAccuracy() {
        let manager = LocationManager(skipAvailabilityCheck: true)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                                  altitude: 0.0,
                                  horizontalAccuracy: 0.0,
                                  verticalAccuracy: 5.0,
                                  timestamp: Date())

        manager.isAvailable = true
        manager.authorizationStatus = .authorizedWhenInUse
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location])

        #expect(manager.hasValidLocation)
        #expect(manager.accuracy == 0.0)
    }

    @Test func testInvalidLocationRejectsNegativeAccuracy() {
        let manager = LocationManager(skipAvailabilityCheck: true)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                                  altitude: 0.0,
                                  horizontalAccuracy: -1.0,
                                  verticalAccuracy: 5.0,
                                  timestamp: Date())

        manager.isAvailable = true
        manager.authorizationStatus = .authorizedWhenInUse
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location])

        #expect(manager.hasValidLocation == false)
        #expect(manager.accuracy == 0.0)
    }

    @Test func testLocationUpdateWithEmptyArray() {
        let manager = LocationManager()

        manager.locationManager(CLLocationManager(), didUpdateLocations: [])

        // Values should remain at defaults
        #expect(manager.latitude == 0.0)
        #expect(manager.longitude == 0.0)
    }

    @Test func testLocationManagerErrorHandling() {
        let manager = LocationManager()

        // Test different types of location errors
        let networkError = CLError(.network)
        manager.locationManager(CLLocationManager(), didFailWithError: networkError)
        #expect(manager.errorMessage.contains("Location error"))

        let deniedError = CLError(.denied)
        manager.locationManager(CLLocationManager(), didFailWithError: deniedError)
        #expect(manager.errorMessage.contains("Location error"))
    }

    @Test func testAuthorizationStatusTransitions() async {
        let manager = LocationManager(skipAvailabilityCheck: true)

        // Wait for initial async availability check to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Test authorized when in use
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)
        assertAuthorizationStatus(manager, expected: .authorizedWhenInUse)

        // Test authorized always
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedAlways)
        assertAuthorizationStatus(manager, expected: .authorizedAlways)

        // Test restricted
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .restricted)
        assertAuthorizationStatus(manager, expected: .restricted)

        // Test not determined
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .notDetermined)
        assertAuthorizationStatus(manager, expected: .notDetermined)
    }

    @Test func testLocationManagerInitialState() async {
        let manager = LocationManager()

        // Wait for async availability check to settle against the current system state.
        await waitForAvailabilityToMatchSystem(manager)

        #expect(manager.latitude == 0.0)
        #expect(manager.longitude == 0.0)
        #expect(manager.altitude == 0.0)
        #expect(manager.accuracy == 0.0)
        #expect(manager.errorMessage.isEmpty)
        #expect(manager.isAvailable == CLLocationManager.locationServicesEnabled())
    }

    @Test func testAppSettingsURLIsValidDeepLink() {
        // When permission is denied/restricted the UI opens Settings via this URL.
        // UIApplication.openSettingsURLString is documented to be non-empty.
        let manager = LocationManager(skipAvailabilityCheck: true)

        let url = manager.appSettingsURL
        #expect(url.absoluteString.isEmpty == false)
        #expect(url.absoluteString == UIApplication.openSettingsURLString)
        #expect(url.scheme != nil) // must be an openable app:// or prefs:// style URL
    }
}
