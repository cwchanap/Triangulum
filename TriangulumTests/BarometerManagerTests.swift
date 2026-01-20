//
//  BarometerManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 7/8/2025.
//

import Testing
import Foundation
import CoreMotion
import SwiftData
@testable import Triangulum

@Suite(.serialized)
struct BarometerManagerTests {

    @Test func testBarometerManagerInitialization() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        #expect(manager.pressure == 0.0)
        #expect(manager.attitude == nil)
        #expect(manager.seaLevelPressure == nil)
        #expect(manager.errorMessage == "")
    }

    @Test func testAvailabilityCheck() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        #expect(manager.isAvailable == CMAltimeter.isRelativeAltitudeAvailable())
        #expect(manager.isAttitudeAvailable == CMMotionManager().isDeviceMotionAvailable)
    }

    @Test func testPressureUpdatesWithoutValidLocation() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        locationManager.isAvailable = true
        locationManager.authorizationStatus = .authorizedWhenInUse

        manager.handlePressureUpdate(currentPressure: 1001.5)

        #expect(manager.pressure == 1001.5)
        #expect(manager.seaLevelPressure == nil)
        #expect(manager.errorMessage.isEmpty)
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

        #expect(seaLevelPressure < currentPressure)
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
        #expect(manager.seaLevelPressure == nil)
        #expect(manager.attitude == nil)
        #expect(manager.errorMessage.isEmpty)
        #expect(manager.isAvailable == CMAltimeter.isRelativeAltitudeAvailable())
        #expect(manager.isAttitudeAvailable == CMMotionManager().isDeviceMotionAvailable)
    }

    @MainActor
    @Test func testHistoryManagerConfiguration() throws {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        // historyManager should be nil before configuration
        #expect(manager.historyManager == nil)

        // Create in-memory SwiftData context for testing
        let schema = Schema([PressureReading.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Configure the history manager
        manager.configureHistory(with: context)

        // historyManager should be non-nil after configuration
        #expect(manager.historyManager != nil)
    }

    @MainActor
    @Test func testHistoryManagerConfigurationIdempotent() throws {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        // Create two different contexts
        let schema = Schema([PressureReading.self])
        let config1 = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container1 = try ModelContainer(for: schema, configurations: [config1])
        let context1 = ModelContext(container1)

        let config2 = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container2 = try ModelContainer(for: schema, configurations: [config2])
        let context2 = ModelContext(container2)

        // Configure once
        manager.configureHistory(with: context1)
        let firstHistoryManager = manager.historyManager

        // Configure again with different context
        manager.configureHistory(with: context2)

        // Should reuse the same historyManager instance (just reconfigure it)
        #expect(manager.historyManager === firstHistoryManager)
    }

    @Test func testHistoryRecordingErrorInitiallyNil() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        // historyRecordingError should be nil initially
        #expect(manager.historyRecordingError == nil)
    }
}
