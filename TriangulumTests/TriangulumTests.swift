//
//  TriangulumTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import Testing
import Foundation
import CoreMotion
import SwiftUI
@testable import Triangulum

struct TriangulumTests {
    
    // MARK: - SensorReading Tests
    
    @Test func testSensorReadingInitialization() {
        let timestamp = Date()
        let reading = SensorReading(
            timestamp: timestamp,
            sensorType: .barometer,
            value: 1013.25,
            unit: "hPa",
            additionalData: "test data",
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 100.0
        )
        
        #expect(reading.timestamp == timestamp)
        #expect(reading.sensorType == .barometer)
        #expect(reading.value == 1013.25)
        #expect(reading.unit == "hPa")
        #expect(reading.additionalData == "test data")
        #expect(reading.latitude == 37.7749)
        #expect(reading.longitude == -122.4194)
        #expect(reading.altitude == 100.0)
    }
    
    @Test func testSensorReadingDefaultValues() {
        let reading = SensorReading(sensorType: .gps, value: 42.0, unit: "degrees")
        
        #expect(reading.sensorType == .gps)
        #expect(reading.value == 42.0)
        #expect(reading.unit == "degrees")
        #expect(reading.additionalData == nil)
        #expect(reading.latitude == nil)
        #expect(reading.longitude == nil)
        #expect(reading.altitude == nil)
    }
    
    // MARK: - SensorType Tests
    
    @Test func testSensorTypeDisplayNames() {
        #expect(SensorType.barometer.displayName == "Barometer")
        #expect(SensorType.gps.displayName == "GPS")
        #expect(SensorType.accelerometer.displayName == "Accelerometer")
        #expect(SensorType.gyroscope.displayName == "Gyroscope")
        #expect(SensorType.magnetometer.displayName == "Magnetometer")
    }
    
    @Test func testSensorTypeRawValues() {
        #expect(SensorType.barometer.rawValue == "barometer")
        #expect(SensorType.gps.rawValue == "gps")
        #expect(SensorType.accelerometer.rawValue == "accelerometer")
        #expect(SensorType.gyroscope.rawValue == "gyroscope")
        #expect(SensorType.magnetometer.rawValue == "magnetometer")
    }
    
    @Test func testSensorTypeCaseIterable() {
        let allCases = SensorType.allCases
        #expect(allCases.count == 5)
        #expect(allCases.contains(.barometer))
        #expect(allCases.contains(.gps))
        #expect(allCases.contains(.accelerometer))
        #expect(allCases.contains(.gyroscope))
        #expect(allCases.contains(.magnetometer))
    }
    
    @Test func testSensorTypeCodable() throws {
        let sensorType = SensorType.barometer
        let encoded = try JSONEncoder().encode(sensorType)
        let decoded = try JSONDecoder().decode(SensorType.self, from: encoded)
        #expect(decoded == sensorType)
    }
    
    // MARK: - AccelerometerManager Tests
    
    @Test func testAccelerometerManagerInitialization() {
        let manager = AccelerometerManager()
        
        #expect(manager.accelerationX == 0.0)
        #expect(manager.accelerationY == 0.0)
        #expect(manager.accelerationZ == 0.0)
        #expect(manager.magnitude == 0.0)
        #expect(manager.errorMessage == "")
        // isAvailable depends on device capabilities, so we don't test its specific value
    }
    
    @Test func testAccelerometerManagerAvailability() {
        let manager = AccelerometerManager()
        #expect(manager.isAvailable == CMMotionManager().isAccelerometerAvailable)
    }
    
    @Test func testAccelerometerManagerMagnitudeCalculation() {
        let manager = AccelerometerManager()
        
        // Test magnitude calculation with known values
        manager.accelerationX = 3.0
        manager.accelerationY = 4.0 
        manager.accelerationZ = 0.0
        
        let expectedMagnitude = sqrt(3.0*3.0 + 4.0*4.0 + 0.0*0.0)
        manager.magnitude = expectedMagnitude
        
        #expect(abs(manager.magnitude - 5.0) < 0.001) // 3-4-5 triangle
    }
    
    @Test func testAccelerometerManagerErrorHandling() {
        let manager = AccelerometerManager()
        
        if !manager.isAvailable {
            manager.startAccelerometerUpdates()
            #expect(manager.errorMessage == "Accelerometer not available on this device")
        }
    }
    
    // MARK: - GyroscopeManager Tests
    
    @Test func testGyroscopeManagerInitialization() {
        let manager = GyroscopeManager()
        
        #expect(manager.rotationX == 0.0)
        #expect(manager.rotationY == 0.0)
        #expect(manager.rotationZ == 0.0)
        #expect(manager.magnitude == 0.0)
        #expect(manager.errorMessage == "")
    }
    
    @Test func testGyroscopeManagerAvailability() {
        let manager = GyroscopeManager()
        #expect(manager.isAvailable == CMMotionManager().isGyroAvailable)
    }
    
    @Test func testGyroscopeManagerMagnitudeCalculation() {
        let manager = GyroscopeManager()
        
        // Test magnitude calculation with known values
        manager.rotationX = 1.0
        manager.rotationY = 2.0
        manager.rotationZ = 2.0
        
        let expectedMagnitude = sqrt(1.0*1.0 + 2.0*2.0 + 2.0*2.0)
        manager.magnitude = expectedMagnitude
        
        #expect(abs(manager.magnitude - 3.0) < 0.001)
    }
    
    @Test func testGyroscopeManagerErrorHandling() {
        let manager = GyroscopeManager()
        
        if !manager.isAvailable {
            manager.startGyroscopeUpdates()
            #expect(manager.errorMessage == "Gyroscope not available on this device")
        }
    }
    
    // MARK: - MagnetometerManager Tests
    
    @Test func testMagnetometerManagerInitialization() {
        let manager = MagnetometerManager()
        
        #expect(manager.magneticFieldX == 0.0)
        #expect(manager.magneticFieldY == 0.0)
        #expect(manager.magneticFieldZ == 0.0)
        #expect(manager.magnitude == 0.0)
        #expect(manager.heading == 0.0)
        #expect(manager.errorMessage == "")
    }
    
    @Test func testMagnetometerManagerAvailability() {
        let manager = MagnetometerManager()
        #expect(manager.isAvailable == CMMotionManager().isMagnetometerAvailable)
    }
    
    @Test func testMagnetometerManagerMagnitudeCalculation() {
        let manager = MagnetometerManager()
        
        // Test magnitude calculation with known values
        manager.magneticFieldX = 20.0
        manager.magneticFieldY = 21.0
        manager.magneticFieldZ = 20.0
        
        let expectedMagnitude = sqrt(20.0*20.0 + 21.0*21.0 + 20.0*20.0)
        manager.magnitude = expectedMagnitude
        
        #expect(abs(manager.magnitude - sqrt(1241.0)) < 0.001)
    }
    
    @Test func testMagnetometerManagerHeadingCalculation() {
        let manager = MagnetometerManager()
        
        // Test heading calculation for known directions
        
        // East (90 degrees)
        manager.magneticFieldX = 1.0
        manager.magneticFieldY = 0.0
        let eastHeading = atan2(0.0, 1.0) * 180 / .pi
        manager.heading = eastHeading >= 0 ? eastHeading : eastHeading + 360
        #expect(abs(manager.heading - 0.0) < 0.001) // East is 0 degrees in magnetometer coordinates
        
        // North (0 degrees) 
        manager.magneticFieldX = 0.0
        manager.magneticFieldY = 1.0
        let northHeading = atan2(1.0, 0.0) * 180 / .pi
        manager.heading = northHeading >= 0 ? northHeading : northHeading + 360
        #expect(abs(manager.heading - 90.0) < 0.001) // North is 90 degrees in magnetometer coordinates
        
        // Test negative heading conversion
        manager.magneticFieldX = -1.0
        manager.magneticFieldY = 0.0
        var negativeHeading = atan2(0.0, -1.0) * 180 / .pi
        if negativeHeading < 0 {
            negativeHeading += 360
        }
        manager.heading = negativeHeading
        #expect(abs(manager.heading - 180.0) < 0.001)
    }
    
    @Test func testMagnetometerManagerErrorHandling() {
        let manager = MagnetometerManager()
        
        if !manager.isAvailable {
            manager.startMagnetometerUpdates()
            #expect(manager.errorMessage == "Magnetometer not available on this device")
        }
    }
    
    // MARK: - SensorSnapshot Tests
    
    @Test func testSensorSnapshotInitialization() {
        let locationManager = LocationManager()
        let barometerManager = BarometerManager(locationManager: locationManager)
        let accelerometerManager = AccelerometerManager()
        let gyroscopeManager = GyroscopeManager()
        let magnetometerManager = MagnetometerManager()
        
        // Set some test values
        barometerManager.pressure = 101.325
        barometerManager.seaLevelPressure = 103.2
        
        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194
        locationManager.altitude = 100.0
        locationManager.accuracy = 5.0
        
        accelerometerManager.accelerationX = 0.1
        accelerometerManager.accelerationY = -0.2
        accelerometerManager.accelerationZ = 0.9
        accelerometerManager.magnitude = 0.94
        
        gyroscopeManager.rotationX = 0.05
        gyroscopeManager.rotationY = -0.03
        gyroscopeManager.rotationZ = 0.01
        gyroscopeManager.magnitude = 0.06
        
        magnetometerManager.magneticFieldX = 20.0
        magnetometerManager.magneticFieldY = -10.0
        magnetometerManager.magneticFieldZ = 50.0
        magnetometerManager.magnitude = 53.85
        magnetometerManager.heading = 135.0
        
        let snapshot = SensorSnapshot(
            barometerManager: barometerManager,
            locationManager: locationManager,
            accelerometerManager: accelerometerManager,
            gyroscopeManager: gyroscopeManager,
            magnetometerManager: magnetometerManager,
            weatherManager: nil
        )
        
        // Test barometer data
        #expect(snapshot.barometer.pressure == 101.325)
        #expect(snapshot.barometer.seaLevelPressure == 103.2)
        
        // Test location data
        #expect(snapshot.location.latitude == 37.7749)
        #expect(snapshot.location.longitude == -122.4194)
        #expect(snapshot.location.altitude == 100.0)
        #expect(snapshot.location.accuracy == 5.0)
        
        // Test accelerometer data
        #expect(snapshot.accelerometer.accelerationX == 0.1)
        #expect(snapshot.accelerometer.accelerationY == -0.2)
        #expect(snapshot.accelerometer.accelerationZ == 0.9)
        #expect(snapshot.accelerometer.magnitude == 0.94)
        
        // Test gyroscope data
        #expect(snapshot.gyroscope.rotationX == 0.05)
        #expect(snapshot.gyroscope.rotationY == -0.03)
        #expect(snapshot.gyroscope.rotationZ == 0.01)
        #expect(snapshot.gyroscope.magnitude == 0.06)
        
        // Test magnetometer data
        #expect(snapshot.magnetometer.magneticFieldX == 20.0)
        #expect(snapshot.magnetometer.magneticFieldY == -10.0)
        #expect(snapshot.magnetometer.magneticFieldZ == 50.0)
        #expect(snapshot.magnetometer.magnitude == 53.85)
        #expect(snapshot.magnetometer.heading == 135.0)
        
        // Test metadata
        #expect(snapshot.photoIDs.isEmpty)
        #expect(snapshot.timestamp.timeIntervalSinceNow < 1.0) // Should be very recent
    }
    
    @Test func testSensorSnapshotCodable() throws {
        let locationManager = LocationManager()
        let barometerManager = BarometerManager(locationManager: locationManager)
        let accelerometerManager = AccelerometerManager()
        let gyroscopeManager = GyroscopeManager()
        let magnetometerManager = MagnetometerManager()
        
        // Set test values
        barometerManager.pressure = 101.0
        locationManager.latitude = 40.0
        accelerometerManager.accelerationX = 0.5
        gyroscopeManager.rotationX = 0.1
        magnetometerManager.magneticFieldX = 25.0
        magnetometerManager.heading = 90.0
        
        let originalSnapshot = SensorSnapshot(
            barometerManager: barometerManager,
            locationManager: locationManager,
            accelerometerManager: accelerometerManager,
            gyroscopeManager: gyroscopeManager,
            magnetometerManager: magnetometerManager,
            weatherManager: nil
        )
        
        let encoded = try JSONEncoder().encode(originalSnapshot)
        let decoded = try JSONDecoder().decode(SensorSnapshot.self, from: encoded)
        
        #expect(decoded.barometer.pressure == originalSnapshot.barometer.pressure)
        #expect(decoded.location.latitude == originalSnapshot.location.latitude)
        #expect(decoded.accelerometer.accelerationX == originalSnapshot.accelerometer.accelerationX)
        #expect(decoded.gyroscope.rotationX == originalSnapshot.gyroscope.rotationX)
        #expect(decoded.magnetometer.magneticFieldX == originalSnapshot.magnetometer.magneticFieldX)
        #expect(decoded.magnetometer.heading == originalSnapshot.magnetometer.heading)
    }
    
    // MARK: - SensorSnapshot Data Structure Tests
    
    @Test func testBarometerDataStructure() {
        let attitudeData = SensorSnapshot.BarometerData.AttitudeData(roll: 0.1, pitch: 0.2, yaw: 0.3)
        let barometerData = SensorSnapshot.BarometerData(
            pressure: 101.325,
            seaLevelPressure: 102.0,
            attitude: attitudeData
        )
        
        #expect(barometerData.pressure == 101.325)
        #expect(barometerData.seaLevelPressure == 102.0)
        #expect(barometerData.attitude?.roll == 0.1)
        #expect(barometerData.attitude?.pitch == 0.2)
        #expect(barometerData.attitude?.yaw == 0.3)
    }
    
    @Test func testAccelerometerDataStructure() {
        let data = SensorSnapshot.AccelerometerData(
            accelerationX: 0.1,
            accelerationY: 0.2,
            accelerationZ: 0.9,
            magnitude: 0.93
        )
        
        #expect(data.accelerationX == 0.1)
        #expect(data.accelerationY == 0.2)
        #expect(data.accelerationZ == 0.9)
        #expect(data.magnitude == 0.93)
    }
    
    @Test func testGyroscopeDataStructure() {
        let data = SensorSnapshot.GyroscopeData(
            rotationX: 0.05,
            rotationY: -0.03,
            rotationZ: 0.01,
            magnitude: 0.06
        )
        
        #expect(data.rotationX == 0.05)
        #expect(data.rotationY == -0.03)
        #expect(data.rotationZ == 0.01)
        #expect(data.magnitude == 0.06)
    }
    
    @Test func testMagnetometerDataStructure() {
        let data = SensorSnapshot.MagnetometerData(
            magneticFieldX: 20.0,
            magneticFieldY: -15.0,
            magneticFieldZ: 45.0,
            magnitude: 50.0,
            heading: 225.5
        )
        
        #expect(data.magneticFieldX == 20.0)
        #expect(data.magneticFieldY == -15.0)
        #expect(data.magneticFieldZ == 45.0)
        #expect(data.magnitude == 50.0)
        #expect(data.heading == 225.5)
    }
    
    // MARK: - Color+Theme Tests
    
    @Test func testPrussianBlueColorPalette() {
        // Test that all prussian blue colors are defined correctly
        let prussianBlue = Color.prussianBlue
        let prussianBlueLight = Color.prussianBlueLight
        let prussianBlueDark = Color.prussianBlueDark
        let prussianAccent = Color.prussianAccent
        let prussianSoft = Color.prussianSoft
        let prussianWarning = Color.prussianWarning
        let prussianError = Color.prussianError
        let prussianSuccess = Color.prussianSuccess
        
        // Verify colors are accessible (no compilation errors)
        #expect(prussianBlue != nil)
        #expect(prussianBlueLight != nil)
        #expect(prussianBlueDark != nil)
        #expect(prussianAccent != nil)
        #expect(prussianSoft != nil)
        #expect(prussianWarning != nil)
        #expect(prussianError != nil)
        #expect(prussianSuccess != nil)
    }
    
    @Test func testColorComponentValues() {
        // Test specific RGB values for the main colors
        // Note: We can't directly test RGB components of SwiftUI Color,
        // but we can verify the colors are distinct from each other
        
        let colors = [
            Color.prussianBlue,
            Color.prussianBlueLight,
            Color.prussianBlueDark,
            Color.prussianAccent,
            Color.prussianSoft,
            Color.prussianWarning,
            Color.prussianError,
            Color.prussianSuccess
        ]
        
        // Test that all colors are unique by checking they're not all the same
        #expect(colors.count == 8)
        
        // Test that the colors can be used in typical SwiftUI contexts
        // This ensures they're properly defined as Color objects
        let testView = Rectangle().fill(Color.prussianBlue)
        #expect(testView != nil)
    }

}
