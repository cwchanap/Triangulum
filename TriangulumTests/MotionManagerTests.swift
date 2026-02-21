//
//  MotionManagerTests.swift
//  TriangulumTests
//

import Testing
import Foundation
import CoreMotion
@testable import Triangulum

// MARK: - AccelerometerManager Tests

@Suite(.serialized)
struct AccelerometerManagerTests {

    @Test func testInitialValues() {
        let manager = AccelerometerManager()
        #expect(manager.accelerationX == 0.0)
        #expect(manager.accelerationY == 0.0)
        #expect(manager.accelerationZ == 0.0)
        #expect(manager.magnitude == 0.0)
        #expect(manager.errorMessage == "")
    }

    @Test func testAvailabilityReflectsMotionManager() {
        let motionManager = CMMotionManager()
        let manager = AccelerometerManager(motionManager: motionManager)
        #expect(manager.isAvailable == motionManager.isAccelerometerAvailable)
    }

    @Test func testStartUpdatesWhenUnavailableSetsError() {
        let motionManager = CMMotionManager()
        let manager = AccelerometerManager(motionManager: motionManager)

        // If the simulator doesn't have an accelerometer, startAccelerometerUpdates
        // should set an informative error rather than a misleading "access denied" message.
        if !manager.isAvailable {
            manager.startAccelerometerUpdates()
            #expect(manager.errorMessage == "Accelerometer not available on this device")
            #expect(!manager.errorMessage.contains("access denied"))
        }
    }

    @Test func testStopUpdatesDoesNotCrash() {
        let manager = AccelerometerManager()
        // stopAccelerometerUpdates should be callable even if updates were never started
        manager.stopAccelerometerUpdates()
        #expect(manager.errorMessage == "")
    }
}

// MARK: - GyroscopeManager Tests

@Suite(.serialized)
struct GyroscopeManagerTests {

    @Test func testInitialValues() {
        let manager = GyroscopeManager()
        #expect(manager.rotationX == 0.0)
        #expect(manager.rotationY == 0.0)
        #expect(manager.rotationZ == 0.0)
        #expect(manager.magnitude == 0.0)
        #expect(manager.errorMessage == "")
    }

    @Test func testAvailabilityReflectsMotionManager() {
        let motionManager = CMMotionManager()
        let manager = GyroscopeManager(motionManager: motionManager)
        #expect(manager.isAvailable == motionManager.isGyroAvailable)
    }

    @Test func testStartUpdatesWhenUnavailableSetsError() {
        let motionManager = CMMotionManager()
        let manager = GyroscopeManager(motionManager: motionManager)

        if !manager.isAvailable {
            manager.startGyroscopeUpdates()
            #expect(manager.errorMessage == "Gyroscope not available on this device")
            // Error must not falsely claim authorization was denied — gyroscope has no explicit auth
            #expect(!manager.errorMessage.contains("access denied"))
        }
    }

    @Test func testStopUpdatesDoesNotCrash() {
        let manager = GyroscopeManager()
        manager.stopGyroscopeUpdates()
        #expect(manager.errorMessage == "")
    }
}

// MARK: - MagnetometerManager Tests

@Suite(.serialized)
struct MagnetometerManagerTests {

    @Test func testInitialValues() {
        let manager = MagnetometerManager()
        #expect(manager.magneticFieldX == 0.0)
        #expect(manager.magneticFieldY == 0.0)
        #expect(manager.magneticFieldZ == 0.0)
        #expect(manager.magnitude == 0.0)
        #expect(manager.heading == 0.0)
        #expect(manager.errorMessage == "")
    }

    @Test func testAvailabilityReflectsMotionManager() {
        let motionManager = CMMotionManager()
        let manager = MagnetometerManager(motionManager: motionManager)
        #expect(manager.isAvailable == motionManager.isMagnetometerAvailable)
    }

    @Test func testStartUpdatesWhenUnavailableSetsError() {
        let motionManager = CMMotionManager()
        let manager = MagnetometerManager(motionManager: motionManager)

        if !manager.isAvailable {
            manager.startMagnetometerUpdates()
            #expect(manager.errorMessage == "Magnetometer not available on this device")
            // Error must not falsely claim authorization was denied — magnetometer has no explicit auth
            #expect(!manager.errorMessage.contains("access denied"))
        }
    }

    @Test func testStopUpdatesDoesNotCrash() {
        let manager = MagnetometerManager()
        manager.stopMagnetometerUpdates()
        #expect(manager.errorMessage == "")
    }
}
