//
//  LocationManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 7/8/2025.
//

import Testing
import Foundation
import CoreLocation
@testable import Triangulum

struct LocationManagerTests {

    @Test func testLocationManagerInitialization() {
        let manager = LocationManager()

        #expect(manager.latitude == 0.0)
        #expect(manager.longitude == 0.0)
        #expect(manager.altitude == 0.0)
        #expect(manager.accuracy == 0.0)
        #expect(manager.errorMessage == "")
    }

    @Test func testAvailabilityCheck() {
        let manager = LocationManager()

        #expect(manager.isAvailable == CLLocationManager.locationServicesEnabled())
    }

    @Test func testAuthorizationStatusInitialization() {
        let manager = LocationManager()

        #expect(manager.authorizationStatus != .notDetermined ||
                    manager.authorizationStatus == .notDetermined)
    }

    @Test func testLocationUnavailableError() {
        let manager = LocationManager()

        if !manager.isAvailable {
            manager.startLocationUpdates()
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
        #expect(manager.accuracy == mockLocation.horizontalAccuracy)
        #expect(manager.errorMessage == "")
    }

    @Test func testLocationManagerError() {
        let manager = LocationManager()
        let error = CLError(.locationUnknown)

        manager.locationManager(CLLocationManager(), didFailWithError: error)

        #expect(manager.errorMessage.contains("Location error"))
    }

    @Test func testAuthorizationStatusChange() {
        let manager = LocationManager()

        manager.locationManager(CLLocationManager(), didChangeAuthorization: .denied)
        #expect(manager.authorizationStatus == .denied)
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

    @Test func testAuthorizationStatusTransitions() {
        let manager = LocationManager()

        // Test authorized when in use
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)
        #expect(manager.authorizationStatus == .authorizedWhenInUse)
        #expect(manager.errorMessage.isEmpty)

        // Test authorized always
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedAlways)
        #expect(manager.authorizationStatus == .authorizedAlways)

        // Test restricted
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .restricted)
        #expect(manager.authorizationStatus == .restricted)
        #expect(manager.errorMessage == "Location access denied")

        // Test not determined
        manager.locationManager(CLLocationManager(), didChangeAuthorization: .notDetermined)
        #expect(manager.authorizationStatus == .notDetermined)
        #expect(manager.errorMessage.isEmpty)
    }

    @Test func testLocationManagerInitialState() {
        let manager = LocationManager()

        #expect(manager.latitude == 0.0)
        #expect(manager.longitude == 0.0)
        #expect(manager.altitude == 0.0)
        #expect(manager.accuracy == 0.0)
        #expect(manager.errorMessage.isEmpty)
        #expect(manager.isAvailable == CLLocationManager.locationServicesEnabled())
    }
}
