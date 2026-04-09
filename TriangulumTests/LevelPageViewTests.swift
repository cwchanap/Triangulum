import Testing
import Foundation
@testable import Triangulum

@Suite struct LevelPageViewTests {

    // MARK: - isLevel threshold

    @Test func isLevelWhenBothAxesAtZero() {
        #expect(isLevel(roll: 0.0, pitch: 0.0, threshold: 2.0))
    }

    @Test func isLevelWhenExactlyAtThreshold() {
        #expect(isLevel(roll: 2.0, pitch: 2.0, threshold: 2.0))
    }

    @Test func notLevelWhenRollExceedsThreshold() {
        #expect(!isLevel(roll: 2.1, pitch: 0.0, threshold: 2.0))
    }

    @Test func notLevelWhenPitchExceedsThreshold() {
        #expect(!isLevel(roll: 0.0, pitch: -2.1, threshold: 2.0))
    }

    @Test func notLevelWhenEitherAxisExceedsThreshold() {
        #expect(!isLevel(roll: 1.5, pitch: 2.5, threshold: 2.0))
    }

    @Test func isLevelWithNegativeAnglesWithinThreshold() {
        #expect(isLevel(roll: -1.9, pitch: -1.9, threshold: 2.0))
    }

    // MARK: - Calibration offset arithmetic

    @Test func calibrationZeroesAdjustedAngle() {
        let raw = 15.0
        let calibration = 15.0
        #expect(adjusted(raw: raw, calibration: calibration) == 0.0)
    }

    @Test func calibrationSubtractsOffset() {
        let raw = 12.5
        let calibration = 5.0
        #expect(adjusted(raw: raw, calibration: calibration) == 7.5)
    }

    @Test func calibrationWorksWithNegativeValues() {
        let raw = -8.0
        let calibration = -3.0
        #expect(adjusted(raw: raw, calibration: calibration) == -5.0)
    }

    @Test func noCalibrationLeavesValueUnchanged() {
        let raw = 30.0
        #expect(adjusted(raw: raw, calibration: 0.0) == 30.0)
    }

    // MARK: - Radians to degrees conversion

    @Test func radiansToDegreesPiOverTwo() {
        let degrees = Double.pi / 2.0 * 180.0 / .pi
        #expect(abs(degrees - 90.0) < 0.0001)
    }

    @Test func radiansToDegreesPiOverFour() {
        let degrees = Double.pi / 4.0 * 180.0 / .pi
        #expect(abs(degrees - 45.0) < 0.0001)
    }

    @Test func radiansToDegreesZero() {
        let degrees = 0.0 * 180.0 / .pi
        #expect(degrees == 0.0)
    }

    // MARK: - Helpers

    private func isLevel(roll: Double, pitch: Double, threshold: Double) -> Bool {
        abs(roll) <= threshold && abs(pitch) <= threshold
    }

    private func adjusted(raw: Double, calibration: Double) -> Double {
        raw - calibration
    }
}
