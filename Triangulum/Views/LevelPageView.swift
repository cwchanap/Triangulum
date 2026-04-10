import SwiftUI
import UIKit

struct LevelPageView: View {
    @ObservedObject var barometerManager: BarometerManager

    @AppStorage("levelCalibrationRoll") private var calibrationRoll: Double = 0.0
    @AppStorage("levelCalibrationPitch") private var calibrationPitch: Double = 0.0

    private let thresholdDeg = 2.0
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color.prussianSoft.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                if barometerManager.isAttitudeAvailable {
                    if barometerManager.attitude != nil {
                        BubbleLevelView(
                            rollDeg: adjustedRoll,
                            pitchDeg: adjustedPitch,
                            thresholdDeg: thresholdDeg
                        )
                        .frame(width: 260, height: 260)

                        HStack(spacing: 40) {
                            VStack(spacing: 4) {
                                Text("Roll")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(adjustedRoll, specifier: "%.1f")°")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(isLevel ? .green : .prussianBlueDark)
                            }
                            VStack(spacing: 4) {
                                Text("Pitch")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(adjustedPitch, specifier: "%.1f")°")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(isLevel ? .green : .prussianBlueDark)
                            }
                        }
                    } else {
                        ProgressView("Waiting for sensor data…")
                            .foregroundColor(.prussianBlueLight)
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.prussianWarning)
                    Text("Motion sensors not available on this device")
                        .font(.body)
                        .foregroundColor(.prussianBlueLight)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
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
        .onAppear { hapticGenerator.prepare() }
        .onChange(of: isLevel) { _, nowLevel in
            if nowLevel { hapticGenerator.impactOccurred() }
        }
    }

    // MARK: - Private helpers

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

    private var isLevel: Bool {
        LevelMath.isLevel(roll: adjustedRoll, pitch: adjustedPitch, threshold: thresholdDeg)
    }

    private func calibrate() {
        guard let attitude = barometerManager.attitude else { return }
        calibrationRoll = attitude.roll * 180.0 / .pi
        calibrationPitch = attitude.pitch * 180.0 / .pi
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
    /// A real bubble rises to the HIGH side, so both axes are negated.
    /// `scale` converts degrees to points (e.g. `outerRadius / 90`).
    static func bubbleOffset(rollDeg: Double, pitchDeg: Double, scale: Double) -> (x: Double, y: Double) {
        let x = -rollDeg * scale
        let y = pitchDeg * scale
        return (x, y)
    }
}

#Preview {
    NavigationStack {
        LevelPageView(barometerManager: BarometerManager(locationManager: LocationManager()))
    }
}
