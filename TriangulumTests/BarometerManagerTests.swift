//
//  BarometerManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 7/8/2025.
//

import Testing
import Foundation
import CoreMotion
@testable import Triangulum

struct BarometerManagerTests {
    
    @Test func testBarometerManagerInitialization() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        #expect(manager.pressure == 0.0)
        #expect(manager.attitude == nil)
        #expect(manager.seaLevelPressure == 0.0)
        #expect(manager.errorMessage == "")
    }
    
    @Test func testAvailabilityCheck() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        #expect(manager.isAvailable == CMAltimeter.isRelativeAltitudeAvailable())
        #expect(manager.isAttitudeAvailable == CMMotionManager().isDeviceMotionAvailable)
    }
    
    @Test func testSeaLevelPressureCalculation() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        let currentPressure = 1013.25
        locationManager.altitude = 100.0
        
        let seaLevelPressure = manager.calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: locationManager.altitude
        )
        
        #expect(seaLevelPressure > currentPressure)
        #expect(seaLevelPressure > 1000.0)
        #expect(seaLevelPressure < 1100.0)
    }
    
    @Test func testSeaLevelPressureCalculationAtSeaLevel() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        let currentPressure = 1013.25
        locationManager.altitude = 0.0
        
        let seaLevelPressure = manager.calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: locationManager.altitude
        )
        
        #expect(abs(seaLevelPressure - currentPressure) < 0.01)
    }
    
    @Test func testSeaLevelPressureCalculationNegativeAltitude() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        let currentPressure = 1013.25
        locationManager.altitude = -100.0
        
        let seaLevelPressure = manager.calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: locationManager.altitude
        )
        
        #expect(seaLevelPressure > currentPressure)
    }
    
    @Test func testBarometerUnavailableError() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        if !manager.isAvailable {
            manager.startBarometerUpdates()
            #expect(manager.errorMessage == "Barometer not available on this device")
        }
    }
    
    @Test func testStopBarometerUpdates() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        manager.stopBarometerUpdates()
    }
    
    @Test func testSeaLevelPressureCalculationExtremeCases() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        // Test very high altitude
        locationManager.altitude = 8000.0
        let highAltitudePressure = manager.calculateSeaLevelPressure(
            currentPressure: 500.0,
            altitude: locationManager.altitude
        )
        #expect(highAltitudePressure > 500.0)
        
        // Test zero pressure
        locationManager.altitude = 100.0
        let zeroPressure = manager.calculateSeaLevelPressure(
            currentPressure: 0.0,
            altitude: locationManager.altitude
        )
        #expect(zeroPressure == 0.0)
    }
    
    @Test func testStartBarometerUpdatesWhenAttitudeUnavailable() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        // This tests the case where barometer is available but attitude is not
        if manager.isAvailable && !manager.isAttitudeAvailable {
            manager.startBarometerUpdates()
            // Should not produce error since attitude updates are optional
            #expect(manager.errorMessage != "Attitude not available")
        }
    }
    
    @Test func testBarometerManagerPublishedProperties() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)
        
        // Test that all @Published properties are initially set correctly
        #expect(manager.pressure == 0.0)
        #expect(manager.seaLevelPressure == 0.0)
        #expect(manager.attitude == nil)
        #expect(manager.errorMessage.isEmpty)
        #expect(manager.isAvailable == CMAltimeter.isRelativeAltitudeAvailable())
        #expect(manager.isAttitudeAvailable == CMMotionManager().isDeviceMotionAvailable)
    }
}

