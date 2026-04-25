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
        // Safety net: if errorMessage is empty but motionStreamFailed is true
        // (e.g. external state manipulation), still show error rather than loading.
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

    /// Calibrating on a tilted surface and then performing an in-plane (body-frame)
    /// rotation should preserve the calibrated zero, because the surface normal
    /// hasn't changed. This test uses body-frame yaw via quaternion composition
    /// (Q_cal * Rz_body(90°)), which represents the real physical scenario of
    /// rotating the phone on a table.
    @Test func quaternionCalibrationZeroesAcrossOrientations() {
        // Calibration quaternion: portrait with roll=5°, pitch=-3°
        let calRollRad = 5.0 * .pi / 180.0
        let calPitchRad = -3.0 * .pi / 180.0
        let calQ = eulerToQuat(roll: calRollRad, pitch: calPitchRad, yaw: 0.0)

        // Body-frame 90° CW rotation (in-plane on the surface):
        // Q_cur = Q_cal * Rz_body(-90°)
        let yaw90 = eulerToQuat(roll: 0.0, pitch: 0.0, yaw: -Double.pi / 2.0)
        let currentQ = LevelMath.quatMultiply(calQ, yaw90)

        let result = LevelMath.relativeAttitudeDegrees(current: currentQ, calibration: calQ)

        // Relative roll/pitch should be ~0 — the surface hasn't changed, only in-plane rotation.
        #expect(abs(result.rollDeg) < 0.01)
        #expect(abs(result.pitchDeg) < 0.01)
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

    /// With rotation lock enabled the UI stays portrait while the device is
    /// physically landscape.  The remap must follow the physical orientation so
    /// the bubble drifts in the direction the user expects.
    @Test func remapPrefersPhysicalDeviceOrientationOverUI() {
        // Device physically landscape-left, UI locked to portrait
        let result = LevelMath.remapForOrientation(
            roll: 5.0,
            pitch: -3.0,
            orientation: .landscapeLeft,
            interfaceOrientation: .portrait
        )
        // Should use landscape-left mapping, NOT portrait
        #expect(result.screenRoll == -3.0)
        #expect(result.screenPitch == 5.0)
    }

    /// Rotation-lock scenario: device physically landscape-right, UI portrait.
    @Test func remapPrefersPhysicalLandscapeRightOverUIPortrait() {
        let result = LevelMath.remapForOrientation(
            roll: 5.0,
            pitch: -3.0,
            orientation: .landscapeRight,
            interfaceOrientation: .portrait
        )
        // Should use landscape-right mapping, NOT portrait
        #expect(result.screenRoll == 3.0)
        #expect(result.screenPitch == -5.0)
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

    // MARK: - rotateVector

    @Test func rotateVectorIdentityLeavesVectorUnchanged() {
        let vector = (x: 1.0, y: 2.0, z: 3.0)
        let result = LevelMath.rotateVector(vector, by: .identity)
        #expect(abs(result.x - 1.0) < 1e-12)
        #expect(abs(result.y - 2.0) < 1e-12)
        #expect(abs(result.z - 3.0) < 1e-12)
    }

    @Test func rotateVectorZAxisByRollTiltY() {
        // 90° roll: Z axis rotates to -Y direction
        let quaternion = eulerToQuat(roll: .pi / 2.0, pitch: 0.0, yaw: 0.0)
        let result = LevelMath.rotateVector((x: 0, y: 0, z: 1), by: quaternion)
        #expect(abs(result.x) < 1e-12)
        #expect(abs(result.y - (-1.0)) < 1e-12)
        #expect(abs(result.z) < 1e-12)
    }

    @Test func rotateVectorZAxisByPitchTiltX() {
        // 90° pitch: Z axis rotates to +X direction
        let quaternion = eulerToQuat(roll: 0.0, pitch: .pi / 2.0, yaw: 0.0)
        let result = LevelMath.rotateVector((x: 0, y: 0, z: 1), by: quaternion)
        #expect(abs(result.x - 1.0) < 1e-12)
        #expect(abs(result.y) < 1e-12)
        #expect(abs(result.z) < 1e-12)
    }

    // MARK: - Quaternion math

    @Test func quatIdentityMultiplicationIsIdentity() {
        let quaternion = LevelMath.Quat(x: 0.3, y: -0.5, z: 0.1, w: 0.8)
        let result = LevelMath.quatMultiply(quaternion, .identity)
        #expect(abs(result.x - quaternion.x) < 1e-12)
        #expect(abs(result.y - quaternion.y) < 1e-12)
        #expect(abs(result.z - quaternion.z) < 1e-12)
        #expect(abs(result.w - quaternion.w) < 1e-12)
    }

    @Test func quatConjugateOfIdentityIsIdentity() {
        let conj = LevelMath.quatConjugate(.identity)
        #expect(conj.x == 0.0)
        #expect(conj.y == 0.0)
        #expect(conj.z == 0.0)
        #expect(conj.w == 1.0)
    }

    @Test func quatSelfConjugateMultiplyIsIdentity() {
        // Must use a unit quaternion for q * conj(q) = identity
        var quaternion = LevelMath.Quat(x: 0.3, y: -0.5, z: 0.1, w: 0.8)
        let norm = sqrt(
            quaternion.x * quaternion.x +
            quaternion.y * quaternion.y +
            quaternion.z * quaternion.z +
            quaternion.w * quaternion.w
        )
        quaternion.x /= norm
        quaternion.y /= norm
        quaternion.z /= norm
        quaternion.w /= norm
        let result = LevelMath.quatMultiply(quaternion, LevelMath.quatConjugate(quaternion))
        #expect(abs(result.x) < 1e-12)
        #expect(abs(result.y) < 1e-12)
        #expect(abs(result.z) < 1e-12)
        #expect(abs(result.w - 1.0) < 1e-12)
    }

    @Test func relativeAttitudeWithSelfCalibrationIsZero() {
        // If current == calibration, relative roll/pitch should be zero.
        let quaternion = eulerToQuat(roll: 0.1, pitch: -0.05, yaw: 0.3)
        let result = LevelMath.relativeAttitudeDegrees(current: quaternion, calibration: quaternion)
        #expect(abs(result.rollDeg) < 0.001)
        #expect(abs(result.pitchDeg) < 0.001)
    }

    @Test func relativeAttitudeWithIdentityCalibrationMatchesEuler() {
        // With identity calibration, relative roll/pitch should equal the
        // quaternion's own roll/pitch extraction.
        let rollDeg = 10.0
        let pitchDeg = -5.0
        let quaternion = eulerToQuat(
            roll: rollDeg * .pi / 180.0,
            pitch: pitchDeg * .pi / 180.0,
            yaw: 0.0
        )
        let result = LevelMath.relativeAttitudeDegrees(current: quaternion, calibration: .identity)
        #expect(abs(result.rollDeg - rollDeg) < 0.01)
        #expect(abs(result.pitchDeg - pitchDeg) < 0.01)
    }

    /// Documents that the uncalibrated path always uses quaternion math
    /// rather than raw Euler angles. This avoids gimbal-lock artefacts near
    /// ±90° pitch and keeps the pipeline consistent regardless of calibration
    /// state. With identity calibration the result matches the device's own
    /// roll/pitch for small tilts (proven above), and the single-path approach
    /// ensures calibrated and uncalibrated modes use identical math.
    @Test func uncalibratedPathUsesQuaternionMath() {
        // 45° tilt in both axes — moderate tilt where Euler is still fine,
        // but this test locks in the "always quaternion" behaviour.
        let rollDeg = 45.0
        let pitchDeg = 30.0
        let quaternion = eulerToQuat(
            roll: rollDeg * .pi / 180.0,
            pitch: pitchDeg * .pi / 180.0,
            yaw: 0.0
        )
        let result = LevelMath.relativeAttitudeDegrees(
            current: quaternion,
            calibration: .identity
        )
        #expect(abs(result.rollDeg - rollDeg) < 0.1)
        #expect(abs(result.pitchDeg - pitchDeg) < 0.1)
    }

    @Test func relativeAttitudeTiltChangeAfterCalibration() {
        // Calibrate at 5° roll, 0° pitch. Then tilt to 10° roll, 0° pitch.
        // Relative should show ~5° roll, ~0° pitch.
        let calQ = eulerToQuat(
            roll: 5.0 * .pi / 180.0,
            pitch: 0.0,
            yaw: 0.0
        )
        let curQ = eulerToQuat(
            roll: 10.0 * .pi / 180.0,
            pitch: 0.0,
            yaw: 0.0
        )
        let result = LevelMath.relativeAttitudeDegrees(current: curQ, calibration: calQ)
        #expect(abs(result.rollDeg - 5.0) < 0.1)
        #expect(abs(result.pitchDeg) < 0.1)
    }

    @Test func quaternionCalibrationSurvivesNinetyDegreeYawRotation() {
        // Calibrate at roll=8°, pitch=3°, yaw=0. Then device rotates 90° CW
        // in-plane (body-frame rotation on the same surface).
        let rollRad = 8.0 * .pi / 180.0
        let pitchRad = 3.0 * .pi / 180.0

        let calQ = eulerToQuat(roll: rollRad, pitch: pitchRad, yaw: 0.0)
        // Body-frame 90° rotation: Q_cur = Q_cal * Rz_body(-90°)
        let yaw90 = eulerToQuat(roll: 0.0, pitch: 0.0, yaw: -.pi / 2.0)
        let curQ = LevelMath.quatMultiply(calQ, yaw90)

        let result = LevelMath.relativeAttitudeDegrees(current: curQ, calibration: calQ)
        #expect(abs(result.rollDeg) < 0.1)
        #expect(abs(result.pitchDeg) < 0.1)
    }

    /// Reviewer's scenario: calibrate at 20°/10°, then 90° in-plane rotation.
    /// The old implementation read ~(-29°, 11°) instead of (0°, 0°).
    @Test func calibrationPreservesZeroOnLargeTiltWithNinetyDegreeInPlaneRotation() {
        let calQ = eulerToQuat(
            roll: 20.0 * .pi / 180.0,
            pitch: 10.0 * .pi / 180.0,
            yaw: 0.0
        )
        let yaw90 = eulerToQuat(roll: 0.0, pitch: 0.0, yaw: -.pi / 2.0)
        let curQ = LevelMath.quatMultiply(calQ, yaw90)

        let result = LevelMath.relativeAttitudeDegrees(current: curQ, calibration: calQ)
        #expect(abs(result.rollDeg) < 0.1)
        #expect(abs(result.pitchDeg) < 0.1)
    }

    // MARK: - Face-down surface equivalence

    /// With identity calibration (flat face-up), placing the phone face-down on
    /// the same flat surface should read as level. Without the normal-flip fix,
    /// this would report ~180° roll.
    @Test func faceDownOnFlatSurfaceIsLevel() {
        // Identity calibration (phone face-up, flat)
        let calQ = LevelMath.Quat.identity

        // Face-down: 180° rotation around device X axis (roll = π)
        let faceDownQ = eulerToQuat(roll: .pi, pitch: 0.0, yaw: 0.0)

        let result = LevelMath.relativeAttitudeDegrees(current: faceDownQ, calibration: calQ)
        #expect(abs(result.rollDeg) < 0.1)
        #expect(abs(result.pitchDeg) < 0.1)
    }

    /// Calibrate face-up on a tilted surface (5° roll), then flip face-down on
    /// the same surface. Should still read ~0° (same plane).
    @Test func faceDownOnTiltedSurfaceMatchesCalibration() {
        let calQ = eulerToQuat(roll: 5.0 * .pi / 180.0, pitch: 0.0, yaw: 0.0)

        // Face-down on the same tilted surface: calibrate orientation + flip
        let flipQ = eulerToQuat(roll: .pi, pitch: 0.0, yaw: 0.0)
        let faceDownQ = LevelMath.quatMultiply(calQ, flipQ)

        let result = LevelMath.relativeAttitudeDegrees(current: faceDownQ, calibration: calQ)
        #expect(abs(result.rollDeg) < 0.1)
        #expect(abs(result.pitchDeg) < 0.1)
    }

    /// Calibrate face-up flat, then place face-down on a surface tilted 10° in
    /// roll. Should show ~10° tilt (the delta between surfaces).
    @Test func faceDownOnDifferentSurfaceShowsDelta() {
        let calQ = LevelMath.Quat.identity

        // Face-down on a surface tilted 10° from horizontal
        // (the surface itself is tilted, so the phone's orientation in world frame
        //  is a 10° roll followed by a 180° flip)
        let tiltQ = eulerToQuat(roll: 10.0 * .pi / 180.0, pitch: 0.0, yaw: 0.0)
        let flipQ = eulerToQuat(roll: .pi, pitch: 0.0, yaw: 0.0)
        let faceDownTiltedQ = LevelMath.quatMultiply(tiltQ, flipQ)

        let result = LevelMath.relativeAttitudeDegrees(
            current: faceDownTiltedQ,
            calibration: calQ
        )
        #expect(abs(result.rollDeg - 10.0) < 0.2)
        #expect(abs(result.pitchDeg) < 0.2)
    }

    /// Calibrated at one tilt, device tilted differently: should show the delta.
    @Test func calibratedTiltChangeDetectedAfterBodyFrameYaw() {
        // Calibrate at roll=5°, pitch=0°
        let calQ = eulerToQuat(roll: 5.0 * .pi / 180.0, pitch: 0.0, yaw: 0.0)
        // Rotate 45° in-plane, then tilt an extra 3° in roll
        let yaw45 = eulerToQuat(roll: 0.0, pitch: 0.0, yaw: .pi / 4.0)
        let extraRoll = eulerToQuat(roll: 3.0 * .pi / 180.0, pitch: 0.0, yaw: 0.0)
        let curQ = LevelMath.quatMultiply(LevelMath.quatMultiply(calQ, yaw45), extraRoll)

        let result = LevelMath.relativeAttitudeDegrees(current: curQ, calibration: calQ)
        // The extra 3° roll appears in the body-frame tilt, but it's been rotated
        // by 45° in-plane so the roll/pitch split depends on the yaw angle.
        // The total tilt magnitude should be ~3°.
        let tiltMag = sqrt(result.rollDeg * result.rollDeg + result.pitchDeg * result.pitchDeg)
        #expect(abs(tiltMag - 3.0) < 0.2)
    }

}

// MARK: - Test helper: Euler angles → quaternion (ZYX convention, matches CoreMotion)

/// Converts ZYX Euler angles (roll, pitch, yaw) to a quaternion.
/// This matches CoreMotion's convention:
///   roll  = rotation around device X axis
///   pitch = rotation around device Y axis
///   yaw   = rotation around device Z axis
private func eulerToQuat(roll: Double, pitch: Double, yaw: Double) -> LevelMath.Quat {
    let cosineRoll = cos(roll / 2.0)
    let sineRoll = sin(roll / 2.0)
    let cosinePitch = cos(pitch / 2.0)
    let sinePitch = sin(pitch / 2.0)
    let cosineYaw = cos(yaw / 2.0)
    let sineYaw = sin(yaw / 2.0)

    return LevelMath.Quat(
        x: sineRoll * cosinePitch * cosineYaw - cosineRoll * sinePitch * sineYaw,
        y: cosineRoll * sinePitch * cosineYaw + sineRoll * cosinePitch * sineYaw,
        z: cosineRoll * cosinePitch * sineYaw - sineRoll * sinePitch * cosineYaw,
        w: cosineRoll * cosinePitch * cosineYaw + sineRoll * sinePitch * sineYaw
    )
}
