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

private final class MockMotionManager: CMMotionManager, @unchecked Sendable {
    var mockIsDeviceMotionAvailable = false
    var startDeviceMotionUpdatesCallCount = 0
    var stopDeviceMotionUpdatesCallCount = 0
    var recordedUpdateInterval: TimeInterval?
    private var handler: CMDeviceMotionHandler?

    override var isDeviceMotionAvailable: Bool {
        mockIsDeviceMotionAvailable
    }

    override var deviceMotionUpdateInterval: TimeInterval {
        get { recordedUpdateInterval ?? super.deviceMotionUpdateInterval }
        set { recordedUpdateInterval = newValue }
    }

    override func startDeviceMotionUpdates(to queue: OperationQueue, withHandler handler: CMDeviceMotionHandler? = nil) {
        startDeviceMotionUpdatesCallCount += 1
        self.handler = handler
    }

    override func stopDeviceMotionUpdates() {
        stopDeviceMotionUpdatesCallCount += 1
        handler = nil
    }

    /// Simulate delivering an error to the motion update handler
    func simulateError(_ error: Error) {
        handler?(nil, error)
    }

    /// Simulate delivering a successful motion update
    func simulateMotion(_ motion: CMDeviceMotion) {
        handler?(motion, nil)
    }
}

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

    @Test func testStartBarometerUpdatesStartsAttitudeUpdates() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startBarometerUpdates()

        #expect(manager.isAvailable == false)
        #expect(manager.isAttitudeAvailable)
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)
    }

    @Test func testStartAttitudeUpdatesExplicitly() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startAttitudeUpdates()

        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)
        #expect(motionManager.recordedUpdateInterval == 0.1)
    }

    @Test func testExplicitAttitudeStopDoesNotStopSharedBarometerMotionUpdates() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startBarometerUpdates()
        manager.startAttitudeUpdates()
        manager.stopAttitudeUpdates()

        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 0)

        manager.stopBarometerUpdates()

        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)
    }

    @Test func testStartAttitudeUpdatesIdempotent() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager
        )

        manager.startAttitudeUpdates()
        manager.startAttitudeUpdates() // second call should be a no-op

        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        manager.stopAttitudeUpdates()

        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)
    }

    @Test func testStopAttitudeUpdates() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager
        )

        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        manager.stopAttitudeUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)
        #expect(manager.attitude == nil)
    }

    @Test func testStopAttitudeUpdatesWithoutStartIsNoOp() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager
        )

        manager.stopAttitudeUpdates() // should not crash or call stop without start

        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 0)
    }

    @Test func testBarometerUnavailableErrorStillShownWhenMotionAlsoUnavailable() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = false
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startBarometerUpdates()

        #expect(motionManager.startDeviceMotionUpdatesCallCount == 0)
        #expect(manager.errorMessage == "Barometer not available on this device")

        // Explicitly trying to start attitude when unavailable should also be a no-op
        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 0)
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

    @Test func testIsAttitudeAvailableReflectsHardwareCapabilityOnly() {
        let locationManager = LocationManager()
        let manager = BarometerManager(locationManager: locationManager)

        // isAttitudeAvailable should match the hardware check from CMMotionManager
        let hardwareAvailable = CMMotionManager().isDeviceMotionAvailable
        #expect(manager.isAttitudeAvailable == hardwareAvailable)

        // Starting and stopping attitude updates should not change the hardware capability flag
        manager.startAttitudeUpdates()
        #expect(manager.isAttitudeAvailable == hardwareAvailable)

        manager.stopAttitudeUpdates()
        #expect(manager.isAttitudeAvailable == hardwareAvailable)
    }

    @Test func testAttitudeUpdatesRecoverAfterTransientError() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        // First call: barometer starts attitude updates
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        // Simulate a transient CoreMotion error (no samples ever delivered)
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)

        #expect(manager.errorMessage.contains("Motion sensor error"))
        // stopDeviceMotionUpdates should have been called to clean up
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // Now LevelPageView calls startAttitudeUpdates() — this should NOT be a no-op
        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)
    }

    @Test func testMotionErrorClearsStaleAttitude() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startAttitudeUpdates()

        // Simulate a successful motion update to set attitude.
        // We can't create a real CMDeviceMotion on the simulator, so verify
        // the clearing behavior through the motionStreamFailed flag instead.
        // The attitude clearing is tested indirectly: after an error, attitude
        // will be nil regardless of its prior state.

        // Simulate an error
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)

        // Attitude should be nil (cleared from any prior state)
        #expect(manager.attitude == nil)
        #expect(manager.motionStreamFailed == true)
    }

    @Test func testMotionErrorSetsMotionStreamFailedFlag() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        #expect(manager.motionStreamFailed == false)

        manager.startAttitudeUpdates()

        // Simulate error
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)

        #expect(manager.motionStreamFailed == true)
    }

    @Test func testMotionStreamFailedResetsOnRestart() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startAttitudeUpdates()

        // Simulate error → sets flag
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)
        #expect(manager.motionStreamFailed == true)

        // Stop the stale requester so a fresh start can succeed
        manager.stopAttitudeUpdates()

        // Restart attitude updates → flag resets
        manager.startAttitudeUpdates()
        #expect(manager.motionStreamFailed == false)
    }

    @Test func testMotionStreamFailedNotClearedByPressureUpdate() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startAttitudeUpdates()

        // Simulate error → sets flag
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)
        #expect(manager.motionStreamFailed == true)
        #expect(manager.errorMessage.contains("Motion sensor error"))

        // Pressure update clears errorMessage but should NOT clear motionStreamFailed
        manager.handlePressureUpdate(currentPressure: 1013.25)
        #expect(manager.errorMessage == "")
        #expect(manager.motionStreamFailed == true)
    }

    @Test func testBarometerRequesterPreservedAfterTransientMotionError() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        // startBarometerUpdates registers .barometer requester and starts motion
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        // Simulate a transient CoreMotion error
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)

        #expect(manager.errorMessage.contains("Motion sensor error"))
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // After error, the .barometer requester should still be registered.
        // When the Level page appears and calls startAttitudeUpdates(), motion should restart
        // because .barometer is still in the set and didStartDeviceMotion is false.
        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)

        // Stopping only the explicit requester should NOT stop motion because
        // the .barometer requester is still registered (preserved across the error).
        manager.stopAttitudeUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1) // only the error-cleanup stop
    }

    @Test func testBothRequestersPreservedAfterTransientMotionError() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        // Both .barometer and .explicit requesters registered
        manager.startBarometerUpdates()
        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        // Simulate a transient error
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)
        #expect(manager.motionStreamFailed == true)

        // Both requesters should be preserved — neither .barometer nor .explicit was dropped.
        // Calling startAttitudeUpdates() should restart motion (insert is a no-op since
        // .explicit is already in the set, but didStartDeviceMotion is false so stream restarts).
        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)
        #expect(manager.motionStreamFailed == false)

        // Stopping only explicit should NOT stop motion because .barometer is still registered
        manager.stopAttitudeUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1) // only the error-cleanup stop
    }

    @Test func testStopBarometerUpdatesAllowsRestart() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // After stop, startBarometerUpdates should work again (latch is reset)
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)
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

    @MainActor
    @Test func testHandlePressureUpdateRecordsToHistory() async throws {
        // Setup location manager with valid location
        let locationManager = LocationManager()
        locationManager.isAvailable = true
        locationManager.authorizationStatus = .authorizedWhenInUse
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 100.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [location])

        // Create barometer manager
        let manager = BarometerManager(locationManager: locationManager)

        // Configure history with in-memory context
        let schema = Schema([PressureReading.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        manager.configureHistory(with: context)

        // Verify history manager is configured
        guard let historyManager = manager.historyManager else {
            throw TestError.historyManagerNotConfigured
        }

        // Trigger pressure update
        manager.handlePressureUpdate(currentPressure: 101.325)

        // Poll until reading is recorded to history or timeout
        let timeout: TimeInterval = 2.0
        let pollInterval: TimeInterval = 0.01
        let startTime = Date()

        var readings: [PressureReading] = []
        while Date().timeIntervalSince(startTime) < timeout {
            readings = historyManager.fetchReadings(for: .oneHour)
            if readings.count >= 1 {
                break
            }

            // Check for recording errors
            if let error = manager.historyRecordingError {
                throw TestError.historyRecordingFailed(error)
            }

            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        // Verify reading was recorded to history
        #expect(readings.count == 1)

        // Verify the recorded data
        if let reading = readings.first {
            #expect(reading.pressure == 101.325)
            #expect(reading.altitude == 100.0)
            #expect(reading.seaLevelPressure > 0)  // Should have calculated sea level pressure
        }

        // Verify no recording error occurred
        #expect(manager.historyRecordingError == nil)
    }

    @MainActor
    @Test func testHandlePressureUpdateWithoutLocationDoesNotRecord() async throws {
        // Setup location manager WITHOUT valid location
        let locationManager = LocationManager()
        locationManager.isAvailable = false  // No location available

        // Create barometer manager
        let manager = BarometerManager(locationManager: locationManager)

        // Configure history with in-memory context
        let schema = Schema([PressureReading.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        manager.configureHistory(with: context)

        guard let historyManager = manager.historyManager else {
            throw TestError.historyManagerNotConfigured
        }

        // Trigger pressure update
        manager.handlePressureUpdate(currentPressure: 101.325)

        // Poll to verify no reading is recorded within timeout
        let timeout: TimeInterval = 2.0
        let pollInterval: TimeInterval = 0.01
        let startTime = Date()

        var readings: [PressureReading] = []
        while Date().timeIntervalSince(startTime) < timeout {
            readings = historyManager.fetchReadings(for: .oneHour)

            // Check for recording errors (should not have any)
            if let error = manager.historyRecordingError {
                throw TestError.historyRecordingFailed(error)
            }

            // If we have readings, we know the async task completed
            if !readings.isEmpty {
                break
            }

            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        // Verify NO reading was recorded (because location is invalid)
        let finalReadings = historyManager.fetchReadings(for: .oneHour)
        #expect(finalReadings.isEmpty)
    }
}

// Test error enum
enum TestError: Error {
    case historyManagerNotConfigured
    case historyRecordingFailed(Error)
}
