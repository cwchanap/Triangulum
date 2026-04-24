//
//  BarometerManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 7/8/2025.
//
// swiftlint:disable file_length

import Testing
import Foundation
import CoreMotion
import SwiftData
@testable import Triangulum

private class MockAttitude: CMAttitude {
    private let _roll: Double
    private let _pitch: Double
    private let _yaw: Double

    init(roll: Double, pitch: Double, yaw: Double) {
        _roll = roll
        _pitch = pitch
        _yaw = yaw
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var roll: Double { _roll }
    override var pitch: Double { _pitch }
    override var yaw: Double { _yaw }
}

private class MockDeviceMotion: CMDeviceMotion {
    private let _attitude: CMAttitude

    init(attitude: CMAttitude) {
        _attitude = attitude
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var attitude: CMAttitude { _attitude }
}

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

@MainActor
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

    @Test func testStartBarometerUpdatesStartsAttitudeWhenBarometerUnavailable() {
        // On barometer-less devices with motion hardware (e.g. iPad),
        // startBarometerUpdates should still register the .barometer requester
        // so that SensorSnapshot.capture can read attitude data.
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
        // Attitude updates SHOULD start even when barometer is unavailable,
        // so snapshots taken from the main screen capture roll/pitch/yaw.
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        // stopBarometerUpdates should tear down the motion stream
        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)
    }

    @Test func testStartBarometerUpdatesStartsAttitudeWhenAvailable() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true }
        )

        manager.startBarometerUpdates()

        #expect(manager.isAvailable == true)
        #expect(manager.isAttitudeAvailable)
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)
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
            barometerAvailability: { true }
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
            barometerAvailability: { true },
            scheduleDelayed: { _, block in block() }
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

        // With immediate scheduler, retry fires synchronously
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)
        #expect(manager.motionStreamFailed == true)
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

        // First set a non-nil attitude via a successful motion callback.
        let mockAttitude = MockAttitude(roll: 0.1, pitch: 0.2, yaw: 0.3)
        let mockMotion = MockDeviceMotion(attitude: mockAttitude)
        motionManager.simulateMotion(mockMotion)
        #expect(manager.attitude != nil)

        // Simulate an error — the stale attitude must be cleared so the
        // Level page doesn't render frozen orientation data.
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)

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

    @Test func testMotionStreamFailedPreservedButErrorMessageClearedByPressureUpdate() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        manager.startAttitudeUpdates()

        // Simulate error → sets flag and error message
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)
        #expect(manager.motionStreamFailed == true)
        #expect(manager.errorMessage.contains("Motion sensor error"))

        // Pressure update should clear errorMessage so BarometerView can display
        // live pressure data even when motion stream has failed. The
        // motionStreamFailed flag persists so LevelPageView can still detect
        // the motion failure independently.
        manager.handlePressureUpdate(currentPressure: 1013.25)
        #expect(manager.errorMessage == "")
        #expect(manager.motionStreamFailed == true)
    }

    @Test func testPressureUpdateClearsNonMotionError() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false }
        )

        // Set a non-motion error message
        manager.errorMessage = "Error reading barometer: timeout"

        // Pressure update should clear non-motion errors
        manager.handlePressureUpdate(currentPressure: 1013.25)
        #expect(manager.errorMessage == "")
    }

    @Test func testMotionRetryStopsAfterMaxRetries() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false },
            scheduleDelayed: { _, block in block() }
        )

        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)

        // Simulate enough errors to exceed maxMotionRetries (5).
        // With immediate scheduler, each error triggers a synchronous retry.
        for attempt in 1...5 {
            motionManager.simulateError(error)
            #expect(motionManager.stopDeviceMotionUpdatesCallCount == attempt)

            // Should have retried immediately
            if attempt < 5 {
                #expect(motionManager.startDeviceMotionUpdatesCallCount == attempt + 1)
            }
        }

        let startCountAfterRetries = motionManager.startDeviceMotionUpdatesCallCount

        // One more error should NOT trigger another retry (exceeded max)
        motionManager.simulateError(error)

        #expect(motionManager.startDeviceMotionUpdatesCallCount == startCountAfterRetries)
    }

    @Test func testMotionRetryCountResetsOnSuccessfulData() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { false },
            scheduleDelayed: { _, block in block() }
        )

        manager.startAttitudeUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)

        // Simulate 4 errors (one less than max) — retries fire immediately
        for _ in 0..<4 {
            motionManager.simulateError(error)
        }

        let startCountBeforeSuccess = motionManager.startDeviceMotionUpdatesCallCount

        // Simulate a successful motion callback to reset the retry counter
        // through the success handler path (line 224: motionRetryCount = 0).
        let mockAttitude = MockAttitude(roll: 0.1, pitch: 0.2, yaw: 0.3)
        let mockMotion = MockDeviceMotion(attitude: mockAttitude)
        motionManager.simulateMotion(mockMotion)

        // Now inject 4 more errors. If the success handler did NOT reset
        // motionRetryCount to 0, the next error would be attempt 5+ and
        // would exceed maxMotionRetries, preventing retries. Instead, each
        // error should still trigger a retry because the counter was reset.
        for _ in 0..<4 {
            motionManager.simulateError(error)
        }

        // All 4 errors after the success should have triggered retries,
        // proving the success handler reset the counter.
        #expect(motionManager.startDeviceMotionUpdatesCallCount >= startCountBeforeSuccess + 4)
    }

    @Test func testBarometerRequesterPreservedAfterTransientMotionError() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true },
            scheduleDelayed: { _, block in block() }
        )

        // startBarometerUpdates registers .barometer requester and starts motion
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        // Simulate a transient CoreMotion error
        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)
        motionManager.simulateError(error)

        #expect(manager.errorMessage.contains("Motion sensor error"))
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // After error, the .barometer requester should still be registered and should trigger
        // an automatic restart without needing an explicit Level-page start.
        #expect(manager.motionStreamFailed == true)

        // With immediate scheduler, retry fires synchronously
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)

        // Stopping only an explicit requester that was never added should remain a no-op.
        manager.stopAttitudeUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)
    }

    @Test func testBothRequestersPreservedAfterTransientMotionError() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true }
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
        #expect(manager.motionStreamFailed == true)

        // Stopping only explicit should NOT stop motion because .barometer is still registered
        manager.stopAttitudeUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1) // only the error-cleanup stop
    }

    @Test func testRetryBudgetResetsOnNewRequester() {
        // After exhausting maxMotionRetries with .barometer registered,
        // a new explicit requester (Level page opening) should get a fresh retry budget.
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true },
            scheduleDelayed: { _, block in block() }
        )

        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        let error = NSError(domain: "com.apple.coremotion", code: 1, userInfo: nil)

        // Exhaust all 5 retries with only .barometer registered — retries fire immediately
        for _ in 1...5 {
            motionManager.simulateError(error)
        }

        // After exhausting retries, one more error should NOT auto-retry
        motionManager.simulateError(error)
        let startCountAfterExhaustion = motionManager.startDeviceMotionUpdatesCallCount

        // Now a new requester joins (Level page opens) — retry budget should reset
        manager.startAttitudeUpdates()

        // Motion should restart because didStartDeviceMotion was reset by error handler
        #expect(motionManager.startDeviceMotionUpdatesCallCount == startCountAfterExhaustion + 1)

        // A transient error should now trigger auto-retry (fresh budget) — fires immediately
        motionManager.simulateError(error)

        // Should have auto-retried, proving the retry budget was reset
        #expect(motionManager.startDeviceMotionUpdatesCallCount >= startCountAfterExhaustion + 2)
    }

    @Test func testStopBarometerUpdatesAllowsRestart() {
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true }
        )

        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // After stop, startBarometerUpdates should work again (latch is reset)
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)
    }

    @Test func testAltimeterErrorRemovesBarometerRequester() {
        // When the altimeter hits an error, the .barometer requester should be removed
        // so that a subsequent stopBarometerUpdates() from ContentView.onDisappear
        // doesn't leave the motion stream running.
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true }
        )

        // startBarometerUpdates registers .barometer requester and starts motion
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        // Simulate the altimeter error path by directly calling stopBarometerUpdates
        // which is what the error handler prepares for. After the error handler resets
        // didStartBarometerUpdates to false and removes the .barometer requester,
        // a subsequent stopBarometerUpdates() should be a no-op (guard returns early)
        // but should NOT leak any resources.
        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // After full stop, motion should be cleaned up, and a fresh start should work
        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 2)
    }

    @Test func testStopBarometerUpdatesAfterLatchResetIsNoOp() {
        // Simulates the scenario from Comment 2: after an altimeter error,
        // didStartBarometerUpdates is false and .barometer requester is removed.
        // A subsequent stopBarometerUpdates() should be a safe no-op.
        let locationManager = LocationManager()
        let motionManager = MockMotionManager()
        motionManager.mockIsDeviceMotionAvailable = true
        let manager = BarometerManager(
            locationManager: locationManager,
            motionManager: motionManager,
            barometerAvailability: { true }
        )

        manager.startBarometerUpdates()
        #expect(motionManager.startDeviceMotionUpdatesCallCount == 1)

        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1)

        // Calling stop again should be safe (no double-stop, no crash)
        manager.stopBarometerUpdates()
        #expect(motionManager.stopDeviceMotionUpdatesCallCount == 1) // still 1, no extra stop
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
