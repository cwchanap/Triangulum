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
                                .foregroundColor(abs(adjustedRoll) <= thresholdDeg ? .green : .prussianBlueDark)
                        }
                        VStack(spacing: 4) {
                            Text("Pitch")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(adjustedPitch, specifier: "%.1f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(abs(adjustedPitch) <= thresholdDeg ? .green : .prussianBlueDark)
                        }
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
                .disabled(!barometerManager.isAttitudeAvailable)
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

    private var adjustedRoll: Double { rawRollDeg - calibrationRoll }
    private var adjustedPitch: Double { rawPitchDeg - calibrationPitch }

    private var isLevel: Bool {
        sqrt(adjustedRoll * adjustedRoll + adjustedPitch * adjustedPitch) <= thresholdDeg
    }

    private func calibrate() {
        guard barometerManager.attitude != nil else { return }
        calibrationRoll = rawRollDeg
        calibrationPitch = rawPitchDeg
    }
}

#Preview {
    NavigationStack {
        LevelPageView(barometerManager: BarometerManager(locationManager: LocationManager()))
    }
}
