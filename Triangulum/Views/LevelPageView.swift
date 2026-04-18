import SwiftUI
import UIKit

struct LevelPageView: View {
    @ObservedObject var barometerManager: BarometerManager

    /// Calibration quaternion stored as four separate @AppStorage entries.
    /// Default is the identity quaternion (no calibration offset).
    @AppStorage("levelCalibQX") private var calibQX: Double = 0.0
    @AppStorage("levelCalibQY") private var calibQY: Double = 0.0
    @AppStorage("levelCalibQZ") private var calibQZ: Double = 0.0
    @AppStorage("levelCalibQW") private var calibQW: Double = 1.0

    /// The stored calibration quaternion.
    private var calibrationQuat: LevelMath.Quat {
        LevelMath.Quat(x: calibQX, y: calibQY, z: calibQZ, w: calibQW)
    }

    private let thresholdDeg = 2.0
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    @State private var interfaceOrientation: UIInterfaceOrientation?

    var body: some View {
        ZStack {
            Color.prussianSoft.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                switch displayState {
                case .level:
                    BubbleLevelView(
                        rollDeg: screenRoll,
                        pitchDeg: screenPitch,
                        thresholdDeg: thresholdDeg
                    )
                    .frame(width: 260, height: 260)

                    HStack(spacing: 40) {
                        VStack(spacing: 4) {
                            Text("Roll")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(screenRoll, specifier: "%.1f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(isLevel ? .prussianGreen : .prussianBlueDark)
                                .accessibilityLabel("Roll: \(String(format: "%.1f", screenRoll)) degrees")
                        }
                        VStack(spacing: 4) {
                            Text("Pitch")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(screenPitch, specifier: "%.1f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(isLevel ? .prussianGreen : .prussianBlueDark)
                                .accessibilityLabel("Pitch: \(String(format: "%.1f", screenPitch)) degrees")
                        }
                    }
                case .loading:
                    ProgressView("Waiting for sensor data…")
                        .foregroundColor(.prussianBlueLight)
                case .unavailable:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.prussianWarning)
                    Text("Motion sensors not available on this device")
                        .font(.body)
                        .foregroundColor(.prussianBlueLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.prussianError)
                    Text(message)
                        .font(.body)
                        .foregroundColor(.prussianError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .background(
            InterfaceOrientationReader { orientation in
                interfaceOrientation = orientation
            }
        )
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.prussianBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: calibrate) {
                    Image(systemName: "scope")
                        .foregroundColor(.white)
                }
                .disabled(!barometerManager.isAttitudeAvailable || barometerManager.attitude == nil)
                .accessibilityLabel("Calibrate level")
                .accessibilityHint("Sets current tilt as the zero reference")
            }
        }
        .onAppear {
            hapticGenerator.prepare()
            barometerManager.startAttitudeUpdates()
        }
        .onDisappear {
            barometerManager.stopAttitudeUpdates()
        }
        .onChange(of: isLevel) { _, nowLevel in
            if nowLevel { hapticGenerator.impactOccurred() }
        }
    }

    // MARK: - Private helpers

    private var displayState: LevelPageDisplayState {
        LevelPageDisplayState.resolve(
            isAttitudeAvailable: barometerManager.isAttitudeAvailable,
            hasAttitude: barometerManager.attitude != nil,
            errorMessage: barometerManager.errorMessage,
            motionStreamFailed: barometerManager.motionStreamFailed
        )
    }

    /// Roll/pitch in degrees relative to the calibration reference, always
    /// computed via quaternion-based surface-normal comparison. When no
    /// calibration has been stored, the identity quaternion is used as the
    /// reference, which avoids the gimbal-lock edge cases of raw Euler angles
    /// (e.g. phone face-down reporting ~180° roll/pitch).
    private var relativeAttitudeDeg: (rollDeg: Double, pitchDeg: Double) {
        guard let attitude = barometerManager.attitude else { return (0.0, 0.0) }
        let currentQ = LevelMath.Quat(
            x: attitude.quaternion.x,
            y: attitude.quaternion.y,
            z: attitude.quaternion.z,
            w: attitude.quaternion.w
        )
        return LevelMath.relativeAttitudeDegrees(
            current: currentQ,
            calibration: calibrationQuat
        )
    }

    /// Screen-space roll/pitch after orientation remap and calibration.
    /// Calibration is applied in the device-fixed quaternion frame first,
    /// then the result is remapped for the current screen orientation.
    private var screenRoll: Double {
        let relative = relativeAttitudeDeg
        let screen = LevelMath.remapForOrientation(
            roll: relative.rollDeg,
            pitch: relative.pitchDeg,
            orientation: UIDevice.current.orientation,
            interfaceOrientation: interfaceOrientation
        )
        return screen.screenRoll
    }

    private var screenPitch: Double {
        let relative = relativeAttitudeDeg
        let screen = LevelMath.remapForOrientation(
            roll: relative.rollDeg,
            pitch: relative.pitchDeg,
            orientation: UIDevice.current.orientation,
            interfaceOrientation: interfaceOrientation
        )
        return screen.screenPitch
    }

    private var isLevel: Bool {
        // Radial distance is orientation-invariant (remap only swaps/negates axes).
        // Must have a real attitude reading; otherwise rawRoll/rawPitch default to 0,
        // which can falsely report "level" and trigger haptics.
        guard barometerManager.attitude != nil else { return false }
        return LevelMath.isLevel(roll: screenRoll, pitch: screenPitch, threshold: thresholdDeg)
    }

    private func calibrate() {
        guard let attitude = barometerManager.attitude else { return }
        let quaternion = attitude.quaternion
        calibQX = quaternion.x
        calibQY = quaternion.y
        calibQZ = quaternion.z
        calibQW = quaternion.w
    }
}

enum LevelPageDisplayState: Equatable {
    case level
    case loading
    case unavailable
    case error(String)

    static func resolve(
        isAttitudeAvailable: Bool,
        hasAttitude: Bool,
        errorMessage: String,
        motionStreamFailed: Bool = false
    ) -> Self {
        guard isAttitudeAvailable else {
            return .unavailable
        }

        if hasAttitude {
            return .level
        }

        // If the motion stream failed (even if errorMessage was subsequently cleared
        // by a pressure update), show the error state rather than a loading spinner.
        if motionStreamFailed {
            let normalizedErrorMessage = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedErrorMessage.hasPrefix("Motion sensor error:") {
                return .error(normalizedErrorMessage)
            }
            // errorMessage was wiped by a pressure update — use a generic message
            return .error("Motion sensor error: updates stopped unexpectedly")
        }

        let normalizedErrorMessage = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedErrorMessage.hasPrefix("Motion sensor error:") {
            return .error(normalizedErrorMessage)
        }

        return .loading
    }
}

enum LevelMath {
    static func adjusted(raw: Double, calibration: Double) -> Double {
        raw - calibration
    }

    static func clampedThreshold(_ threshold: Double) -> Double {
        max(threshold, 0)
    }

    static func isLevel(roll: Double, pitch: Double, threshold: Double) -> Bool {
        let normalizedThreshold = clampedThreshold(threshold)
        return sqrt(roll * roll + pitch * pitch) <= normalizedThreshold
    }

    /// Returns the (x, y) offset for the bubble inside a level indicator.
    ///
    /// Convention: positive roll = right side down, positive pitch = top tilts away.
    /// Roll is negated so the bubble moves toward the high side (right side down → bubble goes left).
    /// Pitch is kept positive so the bubble moves down when the top tilts away.
    /// `scale` converts degrees to points (e.g. `outerRadius / 90`).
    static func bubbleOffset(rollDeg: Double, pitchDeg: Double, scale: Double) -> (x: Double, y: Double) {
        let x = -rollDeg * scale
        let y = pitchDeg * scale
        return (x, y)
    }

    /// Remaps device-frame roll/pitch to screen-frame values based on the
    /// current device orientation so that the bubble always drifts in the
    /// correct on-screen direction.
    ///
    /// Core Motion reports roll and pitch in the device's physical reference
    /// frame (portrait axes). When the device is rotated to landscape or
    /// upside-down, those axes no longer align with the screen's horizontal
    /// and vertical axes. This function performs the axis swap/negation so
    /// downstream math (bubble offset, numeric readouts) matches what the
    /// user sees on screen.
    static func remapForOrientation(
        roll: Double,
        pitch: Double,
        orientation: UIDeviceOrientation,
        interfaceOrientation: UIInterfaceOrientation? = nil
    ) -> (screenRoll: Double, screenPitch: Double) {
        switch resolvedOrientation(
            orientation,
            interfaceOrientation: interfaceOrientation
        ) {
        case .portrait, .unknown, .faceUp, .faceDown:
            return (roll, pitch)
        case .portraitUpsideDown:
            return (-roll, -pitch)
        case .landscapeLeft:
            return (pitch, roll)
        case .landscapeRight:
            return (-pitch, -roll)
        @unknown default:
            return (roll, pitch)
        }
    }

    static func resolvedOrientation(
        _ orientation: UIDeviceOrientation,
        interfaceOrientation: UIInterfaceOrientation?
    ) -> UIDeviceOrientation {
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            switch orientation {
            case .faceUp, .faceDown, .unknown:
                return .portrait
            default:
                return orientation
            }
        }
    }

    // MARK: - Quaternion-based calibration

    /// Lightweight quaternion representation for calibration storage.
    /// Uses (x, y, z, w) convention matching CMQuaternion.
    struct Quat: Equatable {
        var x: Double
        var y: Double
        var z: Double
        var w: Double

        static let identity = Quat(x: 0, y: 0, z: 0, w: 1)
    }

    /// Hamilton product of two quaternions: q1 * q2.
    static func quatMultiply(_ lhs: Quat, _ rhs: Quat) -> Quat {
        Quat(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    /// Conjugate (inverse for unit quaternions).
    static func quatConjugate(_ quaternion: Quat) -> Quat {
        Quat(x: -quaternion.x, y: -quaternion.y, z: -quaternion.z, w: quaternion.w)
    }

    /// Rotates a 3D vector by a unit quaternion using the sandwich product
    /// v' = q * v * q⁻¹.
    static func rotateVector(
        _ vector: (x: Double, y: Double, z: Double),
        by quaternion: Quat
    ) -> (x: Double, y: Double, z: Double) {
        let vectorQuat = Quat(x: vector.x, y: vector.y, z: vector.z, w: 0)
        let rotated = quatMultiply(quatMultiply(quaternion, vectorQuat), quatConjugate(quaternion))
        return (rotated.x, rotated.y, rotated.z)
    }

    /// Extracts roll (radians) from a quaternion using the same ZYX Euler
    /// angle convention as CoreMotion.
    static func quaternionToRoll(_ quaternion: Quat) -> Double {
        let sinrCosp = 2.0 * (quaternion.w * quaternion.x + quaternion.y * quaternion.z)
        let cosrCosp = 1.0 - 2.0 * (quaternion.x * quaternion.x + quaternion.y * quaternion.y)
        return atan2(sinrCosp, cosrCosp)
    }

    /// Extracts pitch (radians) from a quaternion using the same ZYX Euler
    /// angle convention as CoreMotion.
    static func quaternionToPitch(_ quaternion: Quat) -> Double {
        let sinp = 2.0 * (quaternion.w * quaternion.y - quaternion.z * quaternion.x)
        // Clamp to [-1, 1] to avoid NaN from asin due to floating-point drift
        return asin(max(-1.0, min(1.0, sinp)))
    }

    /// Computes roll and pitch (in degrees) of the *relative tilt* between
    /// the current orientation and a stored calibration orientation.
    ///
    /// Uses surface-normal comparison to remain invariant to in-plane (yaw)
    /// rotations. The device's surface normal (body Z axis) is transformed to
    /// world frame for both orientations. The calibration normal is then
    /// expressed in the current body frame: if the phone is still on the same
    /// calibration surface, this vector equals [0, 0, 1] regardless of any
    /// in-plane rotation that occurred after calibrating.
    ///
    /// Roll and pitch are extracted from the body-frame calibration normal
    /// using atan2, matching CoreMotion's sign conventions (positive roll =
    /// right side down, positive pitch = top tilts away from user).
    static func relativeAttitudeDegrees(
        current: Quat,
        calibration: Quat
    ) -> (rollDeg: Double, pitchDeg: Double) {
        let upVector = (x: 0.0, y: 0.0, z: 1.0)

        // Calibration surface normal in world frame
        let nCalWorld = rotateVector(upVector, by: calibration)

        // Express calibration normal in the current body frame.
        // On the same surface as calibration → [0,0,1] → roll/pitch = 0.
        let nCalBody = rotateVector(nCalWorld, by: quatConjugate(current))

        let rollDeg = atan2(nCalBody.y, nCalBody.z) * 180.0 / .pi
        let pitchDeg = atan2(-nCalBody.x, hypot(nCalBody.y, nCalBody.z)) * 180.0 / .pi

        return (rollDeg, pitchDeg)
    }
}

private struct InterfaceOrientationReader: UIViewRepresentable {
    let onChange: (UIInterfaceOrientation?) -> Void

    func makeUIView(context: Context) -> InterfaceOrientationReportingView {
        let view = InterfaceOrientationReportingView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: InterfaceOrientationReportingView, context: Context) {
        uiView.onChange = onChange
        uiView.reportOrientationIfNeeded()
    }
}

private final class InterfaceOrientationReportingView: UIView {
    var onChange: ((UIInterfaceOrientation?) -> Void)?

    private weak var lastWindowScene: UIWindowScene?
    private var lastOrientation: UIInterfaceOrientation?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportOrientationIfNeeded(force: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportOrientationIfNeeded()
    }

    func reportOrientationIfNeeded(force: Bool = false) {
        let windowScene = window?.windowScene
        let orientation = windowScene?.interfaceOrientation

        guard force || windowScene !== lastWindowScene || orientation != lastOrientation else {
            return
        }

        lastWindowScene = windowScene
        lastOrientation = orientation

        guard let onChange else {
            return
        }

        DispatchQueue.main.async {
            onChange(orientation)
        }
    }
}

#Preview {
    NavigationStack {
        LevelPageView(barometerManager: BarometerManager(locationManager: LocationManager()))
    }
}
