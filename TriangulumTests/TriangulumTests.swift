//
//  TriangulumTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import Testing
import Foundation
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

}
