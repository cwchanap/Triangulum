import SwiftUI
import UIKit

struct LevelPageView: View {
    @ObservedObject var barometerManager: BarometerManager

    @AppStorage("levelCalibrationRoll") private var calibrationRoll: Double = 0.0
    @AppStorage("levelCalibrationPitch") private var calibrationPitch: Double = 0.0

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
                                .foregroundColor(isLevel ? .green : .prussianBlueDark)
                        }
                        VStack(spacing: 4) {
                            Text("Pitch")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(screenPitch, specifier: "%.1f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(isLevel ? .green : .prussianBlueDark)
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

    private var rawRollDeg: Double {
        guard let attitude = barometerManager.attitude else { return 0.0 }
        return attitude.roll * 180.0 / .pi
    }

    private var rawPitchDeg: Double {
        guard let attitude = barometerManager.attitude else { return 0.0 }
        return attitude.pitch * 180.0 / .pi
    }

    private var adjustedRoll: Double { LevelMath.adjusted(raw: rawRollDeg, calibration: calibrationRoll) }
    private var adjustedPitch: Double { LevelMath.adjusted(raw: rawPitchDeg, calibration: calibrationPitch) }

    private var screenAttitude: (screenRoll: Double, screenPitch: Double) {
        LevelMath.remapForOrientation(
            roll: adjustedRoll,
            pitch: adjustedPitch,
            orientation: UIDevice.current.orientation,
            interfaceOrientation: interfaceOrientation
        )
    }

    /// Screen-space roll/pitch after orientation remap.
    private var screenRoll: Double {
        screenAttitude.screenRoll
    }

    private var screenPitch: Double {
        screenAttitude.screenPitch
    }

    private var isLevel: Bool {
        // Radial distance is orientation-invariant (remap only swaps/negates axes).
        LevelMath.isLevel(roll: adjustedRoll, pitch: adjustedPitch, threshold: thresholdDeg)
    }

    private func calibrate() {
        guard let attitude = barometerManager.attitude else { return }
        calibrationRoll = attitude.roll * 180.0 / .pi
        calibrationPitch = attitude.pitch * 180.0 / .pi
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
