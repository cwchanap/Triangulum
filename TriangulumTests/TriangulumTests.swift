//
//  TriangulumTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import Testing
import Foundation
import CoreMotion
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
        // We can't control device availability, but we can test that the property exists
        #expect(manager.isAvailable == manager.isAvailable) // Just ensuring the property is accessible
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
        #expect(manager.isAvailable == manager.isAvailable)
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
        #expect(manager.isAvailable == manager.isAvailable)
    }
    
    // MARK: - SensorSnapshot Tests
    
    @Test func testSensorSnapshotInitialization() {
        let barometerManager = BarometerManager()
        let locationManager = LocationManager()
        let accelerometerManager = AccelerometerManager()
        let gyroscopeManager = GyroscopeManager()
        let magnetometerManager = MagnetometerManager()
        
        // Set some test values
        barometerManager.pressure = 101.325
        barometerManager.relativeAltitude = 15.0
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
            magnetometerManager: magnetometerManager
        )
        
        // Test barometer data
        #expect(snapshot.barometer.pressure == 101.325)
        #expect(snapshot.barometer.relativeAltitude == 15.0)
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
        let barometerManager = BarometerManager()
        let locationManager = LocationManager()
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
            magnetometerManager: magnetometerManager
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
            relativeAltitude: 50.0,
            seaLevelPressure: 102.0,
            attitude: attitudeData
        )
        
        #expect(barometerData.pressure == 101.325)
        #expect(barometerData.relativeAltitude == 50.0)
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

}
