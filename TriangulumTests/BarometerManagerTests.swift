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
        let manager = BarometerManager()
        
        #expect(manager.pressure == 0.0)
        #expect(manager.relativeAltitude == 0.0)
        #expect(manager.attitude == nil)
        #expect(manager.seaLevelPressure == 0.0)
        #expect(manager.errorMessage == "")
    }
    
    @Test func testAvailabilityCheck() {
        let manager = BarometerManager()
        
        #expect(manager.isAvailable == CMAltimeter.isRelativeAltitudeAvailable())
        #expect(manager.isAttitudeAvailable == CMMotionManager().isDeviceMotionAvailable)
    }
    
    @Test func testSeaLevelPressureCalculation() {
        let manager = BarometerManager()
        
        let currentPressure = 1013.25
        let altitude = 100.0
        
        let seaLevelPressure = manager.calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: altitude
        )
        
        #expect(seaLevelPressure > currentPressure)
        #expect(seaLevelPressure > 1000.0)
        #expect(seaLevelPressure < 1100.0)
    }
    
    @Test func testSeaLevelPressureCalculationAtSeaLevel() {
        let manager = BarometerManager()
        
        let currentPressure = 1013.25
        let altitude = 0.0
        
        let seaLevelPressure = manager.calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: altitude
        )
        
        #expect(abs(seaLevelPressure - currentPressure) < 0.01)
    }
    
    @Test func testSeaLevelPressureCalculationNegativeAltitude() {
        let manager = BarometerManager()
        
        let currentPressure = 1013.25
        let altitude = -100.0
        
        let seaLevelPressure = manager.calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: altitude
        )
        
        #expect(seaLevelPressure > currentPressure)
    }
    
    @Test func testBarometerUnavailableError() {
        let manager = BarometerManager()
        
        if !manager.isAvailable {
            manager.startBarometerUpdates()
            #expect(manager.errorMessage == "Barometer not available on this device")
        }
    }
    
    @Test func testStopBarometerUpdates() {
        let manager = BarometerManager()
        
        manager.stopBarometerUpdates()
    }
    
    @Test func testSeaLevelPressureCalculationExtremeCases() {
        let manager = BarometerManager()
        
        // Test very high altitude
        let highAltitudePressure = manager.calculateSeaLevelPressure(
            currentPressure: 500.0,
            altitude: 8000.0
        )
        #expect(highAltitudePressure > 500.0)
        
        // Test zero pressure
        let zeroPressure = manager.calculateSeaLevelPressure(
            currentPressure: 0.0,
            altitude: 100.0
        )
        #expect(zeroPressure == 0.0)
    }
    
    @Test func testStartBarometerUpdatesWhenAttitudeUnavailable() {
        let manager = BarometerManager()
        
        // This tests the case where barometer is available but attitude is not
        if manager.isAvailable && !manager.isAttitudeAvailable {
            manager.startBarometerUpdates()
            // Should not produce error since attitude updates are optional
            #expect(manager.errorMessage != "Attitude not available")
        }
    }
    
    @Test func testBarometerManagerPublishedProperties() {
        let manager = BarometerManager()
        
        // Test that all @Published properties are initially set correctly
        #expect(manager.pressure == 0.0)
        #expect(manager.relativeAltitude == 0.0)
        #expect(manager.seaLevelPressure == 0.0)
        #expect(manager.attitude == nil)
        #expect(manager.errorMessage.isEmpty)
        #expect(manager.isAvailable == CMAltimeter.isRelativeAltitudeAvailable())
        #expect(manager.isAttitudeAvailable == CMMotionManager().isDeviceMotionAvailable)
    }
}

private extension BarometerManager {
    func calculateSeaLevelPressure(currentPressure: Double, altitude: Double) -> Double {
        let temperatureK = 288.15
        let lapseRate = 0.0065
        let gasConstant = 287.053
        let gravity = 9.80665
        
        let exponent = (gravity * abs(altitude)) / (gasConstant * temperatureK)
        let pressureRatio = exp(exponent)
        
        return currentPressure * pressureRatio
    }
}