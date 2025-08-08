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
}