import Testing
import Foundation
import UIKit
@testable import Triangulum

@Suite struct LevelPageViewTests {

    // MARK: - isLevel threshold

    @Test func isLevelWhenBothAxesAtZero() {
        #expect(LevelMath.isLevel(roll: 0.0, pitch: 0.0, threshold: 2.0))
    }

    @Test func isLevelWhenExactlyAtThreshold() {
        #expect(LevelMath.isLevel(roll: 2.0, pitch: 0.0, threshold: 2.0))
    }

    @Test func notLevelWhenRollExceedsThreshold() {
        #expect(!LevelMath.isLevel(roll: 2.1, pitch: 0.0, threshold: 2.0))
    }

    @Test func notLevelWhenPitchExceedsThreshold() {
        #expect(!LevelMath.isLevel(roll: 0.0, pitch: -2.1, threshold: 2.0))
    }

    @Test func notLevelWhenEitherAxisExceedsThreshold() {
        #expect(!LevelMath.isLevel(roll: 1.5, pitch: 2.5, threshold: 2.0))
    }

    @Test func notLevelWhenNegativeAnglesExceedThreshold() {
        // sqrt(1.9^2 + 1.9^2) ≈ 2.687, outside the 2.0 threshold
        #expect(!LevelMath.isLevel(roll: -1.9, pitch: -1.9, threshold: 2.0))
    }

    @Test func isLevelWhenRadialDistanceEqualsThresholdOnDiagonal() {
        // sqrt(d^2 + d^2) == 2.0 exactly when d == sqrt(2)
        let diagonalComponent = sqrt(2.0)
        #expect(LevelMath.isLevel(roll: diagonalComponent, pitch: diagonalComponent, threshold: 2.0))
        #expect(!LevelMath.isLevel(roll: diagonalComponent + 0.001, pitch: diagonalComponent + 0.001, threshold: 2.0))
    }

    @Test func isLevelWhenRadialMagnitudeIsWithinThreshold() {
        #expect(LevelMath.isLevel(roll: 1.0, pitch: 1.0, threshold: 2.0))
    }

    @Test func negativeThresholdIsClampedToZero() {
        #expect(LevelMath.clampedThreshold(-2.0) == 0.0)
        #expect(LevelMath.isLevel(roll: 0.0, pitch: 0.0, threshold: -2.0))
        #expect(!LevelMath.isLevel(roll: 0.1, pitch: 0.0, threshold: -2.0))
    }

    @Test func displayStateIsUnavailableWhenAttitudeIsUnavailable() {
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: false,
            hasAttitude: false,
            errorMessage: "Motion sensor error: unavailable"
        )

        #expect(state == .unavailable)
    }

    @Test func displayStatePrefersLevelWhenAttitudeExists() {
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: true,
            hasAttitude: true,
            errorMessage: "Motion sensor error: transient"
        )

        #expect(state == .level)
    }

    @Test func displayStateShowsMotionSensorErrorsBeforeLoading() {
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: true,
            hasAttitude: false,
            errorMessage: " Motion sensor error: failed to start "
        )

        #expect(state == .error("Motion sensor error: failed to start"))
    }

    @Test func displayStateIgnoresNonMotionErrorsWhileWaitingForAttitude() {
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: true,
            hasAttitude: false,
            errorMessage: "Barometer not available on this device"
        )

        #expect(state == .loading)
    }

    // MARK: - motionStreamFailed flag handling

    @Test func displayStateShowsErrorWhenMotionStreamFailedEvenWithoutErrorMessage() {
        // After a motion error, a subsequent pressure update clears errorMessage.
        // The motionStreamFailed flag ensures we still show an error, not loading.
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: true,
            hasAttitude: false,
            errorMessage: "",
            motionStreamFailed: true
        )

        #expect(state == .error("Motion sensor error: updates stopped unexpectedly"))
    }

    @Test func displayStateShowsSpecificErrorWhenMotionStreamFailedWithErrorMessage() {
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: true,
            hasAttitude: false,
            errorMessage: "Motion sensor error: hardware failure",
            motionStreamFailed: true
        )

        #expect(state == .error("Motion sensor error: hardware failure"))
    }

    @Test func displayStateShowsLoadingWhenMotionStreamNotFailed() {
        let state = LevelPageDisplayState.resolve(
            isAttitudeAvailable: true,
            hasAttitude: false,
            errorMessage: "",
            motionStreamFailed: false
        )

        #expect(state == .loading)
    }

    // MARK: - Calibration offset arithmetic

    @Test func calibrationZeroesAdjustedAngle() {
        let raw = 15.0
        let calibration = 15.0
        #expect(LevelMath.adjusted(raw: raw, calibration: calibration) == 0.0)
    }

    @Test func calibrationSubtractsOffset() {
        let raw = 12.5
        let calibration = 5.0
        #expect(LevelMath.adjusted(raw: raw, calibration: calibration) == 7.5)
    }

    @Test func calibrationWorksWithNegativeValues() {
        let raw = -8.0
        let calibration = -3.0
        #expect(LevelMath.adjusted(raw: raw, calibration: calibration) == -5.0)
    }

    @Test func noCalibrationLeavesValueUnchanged() {
        let raw = 30.0
        #expect(LevelMath.adjusted(raw: raw, calibration: 0.0) == 30.0)
    }

    // MARK: - Screen-space calibration pipeline (remap → adjust)

    /// Simulates the full pipeline: raw device-frame → remap → subtract calibration.
    /// Verifies that calibrating in a given orientation zeroes the output when the
    /// device stays in that same orientation.
    @Test func screenSpaceCalibrationZeroesInSameOrientation() {
        // Device reports roll=5, pitch=-3 in portrait.
        let rawRoll = 5.0, rawPitch = -3.0

        // Calibrate in portrait: remap(identity) → store screen-space (5, -3)
        let calScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .portrait
        )
        #expect(calScreen.screenRoll == 5.0)
        #expect(calScreen.screenPitch == -3.0)

        // Display in portrait (same orientation): remap(identity) → (5, -3)
        let displayScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .portrait
        )
        let adjustedRoll = LevelMath.adjusted(
            raw: displayScreen.screenRoll, calibration: calScreen.screenRoll
        )
        let adjustedPitch = LevelMath.adjusted(
            raw: displayScreen.screenPitch, calibration: calScreen.screenPitch
        )
        #expect(adjustedRoll == 0.0)
        #expect(adjustedPitch == 0.0)
    }

    /// Verifies that calibrating in landscape-left correctly zeroes when displayed
    /// in landscape-left (same orientation).
    @Test func screenSpaceCalibrationZeroesInLandscapeLeft() {
        let rawRoll = 5.0, rawPitch = -3.0

        // Calibrate in landscape-left: remap → (pitch, roll) = (-3, 5)
        let calScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .landscapeLeft
        )
        #expect(calScreen.screenRoll == -3.0)
        #expect(calScreen.screenPitch == 5.0)

        // Display in landscape-left (same orientation, same raw values)
        let displayScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .landscapeLeft
        )
        let adjustedRoll = LevelMath.adjusted(
            raw: displayScreen.screenRoll, calibration: calScreen.screenRoll
        )
        let adjustedPitch = LevelMath.adjusted(
            raw: displayScreen.screenPitch, calibration: calScreen.screenPitch
        )
        #expect(adjustedRoll == 0.0)
        #expect(adjustedPitch == 0.0)
    }

    /// Verifies that calibrating in one orientation and displaying in another
    /// produces a meaningful (non-zero) screen-space offset. This is the expected
    /// behaviour for a spirit level: rotating on a tilted surface changes the reading.
    @Test func screenSpaceCalibrationAcrossOrientationsIsNonZero() {
        let rawRoll = 5.0, rawPitch = -3.0

        // Calibrate in portrait
        let calScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .portrait
        )

        // Display in landscape-left (same raw device-frame values)
        let displayScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .landscapeLeft
        )
        let adjustedRoll = LevelMath.adjusted(
            raw: displayScreen.screenRoll, calibration: calScreen.screenRoll
        )
        let adjustedPitch = LevelMath.adjusted(
            raw: displayScreen.screenPitch, calibration: calScreen.screenPitch
        )

        // The device has rotated on the same surface, so screen-space tilt changes.
        // This is physically correct for a 2D bubble level.
        // portrait screen: (5, -3), landscape-left screen: (-3, 5)
        // adjusted: (-3 - 5, 5 - (-3)) = (-8, 8)
        #expect(adjustedRoll == -8.0)
        #expect(adjustedPitch == 8.0)
    }

    /// Verifies that with zero calibration the output equals the raw remapped value.
    @Test func screenSpaceZeroCalibrationIsIdentity() {
        let rawRoll = 7.0, rawPitch = 2.0

        let displayScreen = LevelMath.remapForOrientation(
            roll: rawRoll, pitch: rawPitch, orientation: .landscapeRight
        )
        let adjustedRoll = LevelMath.adjusted(
            raw: displayScreen.screenRoll, calibration: 0.0
        )
        let adjustedPitch = LevelMath.adjusted(
            raw: displayScreen.screenPitch, calibration: 0.0
        )
        // landscapeRight remap: (-pitch, -roll) = (-2, -7)
        #expect(adjustedRoll == -2.0)
        #expect(adjustedPitch == -7.0)
    }

    // MARK: - Bubble offset (bubble drifts to the HIGH side)

    @Test func bubbleOffsetAtLevelIsZero() {
        let offset = LevelMath.bubbleOffset(rollDeg: 0.0, pitchDeg: 0.0, scale: 1.0)
        #expect(offset.x == 0.0)
        #expect(offset.y == 0.0)
    }

    @Test func bubbleOffsetPositiveRollMovesBubbleLeft() {
        // Positive roll = right side down → high side is LEFT → bubble goes left (negative x)
        let offset = LevelMath.bubbleOffset(rollDeg: 10.0, pitchDeg: 0.0, scale: 1.0)
        #expect(offset.x < 0)
        #expect(offset.y == 0.0)
    }

    @Test func bubbleOffsetNegativeRollMovesBubbleRight() {
        // Negative roll = left side down → high side is RIGHT → bubble goes right (positive x)
        let offset = LevelMath.bubbleOffset(rollDeg: -10.0, pitchDeg: 0.0, scale: 1.0)
        #expect(offset.x > 0)
        #expect(offset.y == 0.0)
    }

    @Test func bubbleOffsetPositivePitchMovesBubbleDown() {
        // Positive pitch = top tilts away → bottom is high → bubble goes down (positive y)
        let offset = LevelMath.bubbleOffset(rollDeg: 0.0, pitchDeg: 10.0, scale: 1.0)
        #expect(offset.x == 0.0)
        #expect(offset.y > 0)
    }

    @Test func bubbleOffsetNegativePitchMovesBubbleUp() {
        // Negative pitch = top tilts toward user → top is high → bubble goes up (negative y)
        let offset = LevelMath.bubbleOffset(rollDeg: 0.0, pitchDeg: -10.0, scale: 1.0)
        #expect(offset.x == 0.0)
        #expect(offset.y < 0)
    }

    @Test func bubbleOffsetScalesWithScaleFactor() {
        let offset1 = LevelMath.bubbleOffset(rollDeg: 10.0, pitchDeg: 0.0, scale: 1.0)
        let offset2 = LevelMath.bubbleOffset(rollDeg: 10.0, pitchDeg: 0.0, scale: 2.0)
        #expect(offset2.x == offset1.x * 2)
    }

    // MARK: - Orientation remap

    @Test func remapPortraitIsIdentity() {
        let result = LevelMath.remapForOrientation(roll: 5.0, pitch: -3.0, orientation: .portrait)
        #expect(result.screenRoll == 5.0)
        #expect(result.screenPitch == -3.0)
    }

    @Test func remapUnknownIsIdentity() {
        let result = LevelMath.remapForOrientation(roll: 5.0, pitch: -3.0, orientation: .unknown)
        #expect(result.screenRoll == 5.0)
        #expect(result.screenPitch == -3.0)
    }

    @Test func remapFaceUpDefaultsToPortraitWithoutFallback() {
        let result = LevelMath.remapForOrientation(roll: 5.0, pitch: -3.0, orientation: .faceUp)
        #expect(result.screenRoll == 5.0)
        #expect(result.screenPitch == -3.0)
    }

    @Test func remapUsesInterfaceOrientationOverDeviceOrientation() {
        let result = LevelMath.remapForOrientation(
            roll: 5.0,
            pitch: -3.0,
            orientation: .landscapeLeft,
            interfaceOrientation: .portrait
        )
        #expect(result.screenRoll == 5.0)
        #expect(result.screenPitch == -3.0)
    }

    @Test func remapFaceUpUsesLandscapeFallback() {
        let result = LevelMath.remapForOrientation(
            roll: 5.0,
            pitch: -3.0,
            orientation: .faceUp,
            interfaceOrientation: .landscapeRight
        )
        #expect(result.screenRoll == -3.0)
        #expect(result.screenPitch == 5.0)
    }

    @Test func remapFaceDownUsesLandscapeFallback() {
        let result = LevelMath.remapForOrientation(
            roll: 5.0,
            pitch: -3.0,
            orientation: .faceDown,
            interfaceOrientation: .landscapeLeft
        )
        #expect(result.screenRoll == 3.0)
        #expect(result.screenPitch == -5.0)
    }

    @Test func remapUnknownUsesPortraitUpsideDownFallback() {
        let result = LevelMath.remapForOrientation(
            roll: 5.0,
            pitch: -3.0,
            orientation: .unknown,
            interfaceOrientation: .portraitUpsideDown
        )
        #expect(result.screenRoll == -5.0)
        #expect(result.screenPitch == 3.0)
    }

    @Test func remapLandscapeLeftSwapsAxes() {
        // LandscapeLeft: (screenRoll, screenPitch) = (devicePitch, deviceRoll)
        let result = LevelMath.remapForOrientation(roll: 5.0, pitch: -3.0, orientation: .landscapeLeft)
        #expect(result.screenRoll == -3.0)
        #expect(result.screenPitch == 5.0)
    }

    @Test func remapLandscapeRightSwapsAndNegatesAxes() {
        // LandscapeRight: (screenRoll, screenPitch) = (-devicePitch, -deviceRoll)
        let result = LevelMath.remapForOrientation(roll: 5.0, pitch: -3.0, orientation: .landscapeRight)
        #expect(result.screenRoll == 3.0)
        #expect(result.screenPitch == -5.0)
    }

    @Test func remapPortraitUpsideDownNegatesBothAxes() {
        let result = LevelMath.remapForOrientation(roll: 5.0, pitch: -3.0, orientation: .portraitUpsideDown)
        #expect(result.screenRoll == -5.0)
        #expect(result.screenPitch == 3.0)
    }

    // Verify that the remap produces correct bubble behaviour in landscape-left:
    // Device roll positive (right side down) → physical right is screen-top →
    // bubble should move screen-down → screenPitch positive → y positive.
    @Test func landscapeLeftDeviceRollPositiveBubbleMovesScreenDown() {
        let remapped = LevelMath.remapForOrientation(
            roll: 10.0, pitch: 0.0, orientation: .landscapeLeft
        )
        let offset = LevelMath.bubbleOffset(
            rollDeg: remapped.screenRoll, pitchDeg: remapped.screenPitch, scale: 1.0
        )
        #expect(offset.x == 0.0)   // no horizontal drift
        #expect(offset.y > 0)      // bubble moves toward screen bottom
    }

    // Device pitch positive (top tilts away) → physical top is screen-left →
    // screen-left tilts away → screen-right goes down → screen-left is high →
    // bubble moves screen-LEFT.
    @Test func landscapeLeftDevicePitchPositiveBubbleMovesScreenLeft() {
        let remapped = LevelMath.remapForOrientation(
            roll: 0.0, pitch: 10.0, orientation: .landscapeLeft
        )
        let offset = LevelMath.bubbleOffset(
            rollDeg: remapped.screenRoll, pitchDeg: remapped.screenPitch, scale: 1.0
        )
        #expect(offset.x < 0)      // bubble moves toward screen left (high side)
        #expect(offset.y == 0.0)   // no vertical drift
    }

    // MARK: - LevelMath.isLevel with raw zeros (nil-attitude guard)

    // When attitude is nil, rawRollDeg/rawPitchDeg return 0 and adjusted values
    // become -(calibration). With default calibration (0,0), LevelMath.isLevel
    // would report true for (0,0). The view's isLevel property guards against
    // this by checking attitude != nil first. This test documents that LevelMath
    // alone cannot distinguish "truly level" from "no data (0,0)".
    @Test func levelMathReportsLevelForZeroZero() {
        // This is correct math; the nil-attitude guard lives in the view layer.
        #expect(LevelMath.isLevel(roll: 0.0, pitch: 0.0, threshold: 2.0))
    }

    @Test func levelMathReportsNotLevelWhenCalibratedOffsetExceedsThreshold() {
        // If calibrated at 5°, a nil-attitude fallback (raw=0) gives adjusted = -5,
        // which correctly exceeds the 2° threshold.
        let adjustedFromNil = LevelMath.adjusted(raw: 0.0, calibration: 5.0)
        #expect(!LevelMath.isLevel(roll: adjustedFromNil, pitch: 0.0, threshold: 2.0))
    }

}
