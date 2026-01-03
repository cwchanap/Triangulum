import SwiftUI
import CoreMotion

struct BarometerView: View {
    @ObservedObject var barometerManager: BarometerManager
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(spacing: 16) {
                // Header with navigation indicator
                HStack {
                    Image(systemName: "barometer")
                        .font(.title)
                        .foregroundColor(.prussianAccent)
                    Text("Barometer")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.prussianBlueDark)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                }

                if !barometerManager.isAvailable {
                    Text("Barometer not available on this device")
                        .foregroundColor(.prussianError)
                        .font(.caption)
                } else if !barometerManager.errorMessage.isEmpty {
                    Text(barometerManager.errorMessage)
                        .foregroundColor(.prussianError)
                        .font(.caption)
                } else {
                    VStack(spacing: 12) {
                        // Pressure values
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Pressure")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(barometerManager.pressure, specifier: "%.2f") kPa")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.prussianBlueDark)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Sea Level Pressure")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(barometerManager.seaLevelPressure, specifier: "%.2f") kPa")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.prussianBlueDark)
                            }
                        }

                        // Trend indicator
                        if let historyManager = barometerManager.historyManager {
                            TrendIndicatorView(historyManager: historyManager)
                        }

                        // Attitude display
                        if let attitude = barometerManager.attitude {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Attitude")
                                        .font(.caption)
                                        .foregroundColor(.prussianBlueLight)
                                    Spacer()
                                }

                                HStack(spacing: 16) {
                                    VStack {
                                        Text("Roll")
                                            .font(.caption2)
                                            .foregroundColor(.prussianBlueLight)
                                        Text("\(attitude.roll * 180 / .pi, specifier: "%.1f")°")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.prussianBlueDark)
                                    }

                                    VStack {
                                        Text("Pitch")
                                            .font(.caption2)
                                            .foregroundColor(.prussianBlueLight)
                                        Text("\(attitude.pitch * 180 / .pi, specifier: "%.1f")°")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.prussianBlueDark)
                                    }

                                    VStack {
                                        Text("Yaw")
                                            .font(.caption2)
                                            .foregroundColor(.prussianBlueLight)
                                        Text("\(attitude.yaw * 180 / .pi, specifier: "%.1f")°")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.prussianBlueDark)
                                    }

                                    Spacer()
                                }
                            }
                        }

                        ProgressView(value: min(max(barometerManager.pressure / 110.0, 0.0), 1.0))
                            .progressViewStyle(LinearProgressViewStyle(tint: pressureColor))
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.white, Color.prussianSoft]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.prussianBlue.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Barometer details")
        .accessibilityHint("Opens detailed barometer view")
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            BarometerDetailView(barometerManager: barometerManager)
        }
    }

    private var pressureColor: Color {
        let normalizedPressure = barometerManager.pressure / 101.325
        if normalizedPressure > 1.02 {
            return .prussianError
        } else if normalizedPressure < 0.98 {
            return .prussianAccent
        } else {
            return .prussianSuccess
        }
    }
}

// MARK: - Trend Indicator Component

struct TrendIndicatorView: View {
    @ObservedObject var historyManager: PressureHistoryManager

    var body: some View {
        HStack(spacing: 12) {
            // Trend arrow
            Image(systemName: historyManager.trend.systemImage)
                .font(.title2)
                .foregroundColor(trendColor)

            VStack(alignment: .leading, spacing: 2) {
                // Prediction text
                Text(historyManager.trend.prediction)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianBlueDark)

                // Rate of change
                if historyManager.trend != .unknown {
                    Text(rateText)
                        .font(.caption2)
                        .foregroundColor(.prussianBlueLight)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(trendColor.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trendAccessibilityLabel)
        .accessibilityHint("Pressure trend indicator")
    }

    private var trendColor: Color {
        switch historyManager.trend {
        case .risingFast, .rising:
            return .prussianSuccess
        case .steady:
            return .prussianBlueLight
        case .falling, .fallingFast:
            return .prussianWarning
        case .unknown:
            return .prussianBlueLight
        }
    }

    private var rateText: String {
        let rate = abs(historyManager.changeRate)
        let direction = historyManager.changeRate >= 0 ? "+" : "-"
        return "\(direction)\(String(format: "%.2f", rate)) hPa/hr"
    }

    private var trendAccessibilityLabel: String {
        if historyManager.trend != .unknown {
            return "\(historyManager.trend.prediction). \(rateText)"
        } else {
            return historyManager.trend.prediction
        }
    }
}

#Preview {
    let manager = BarometerManager(locationManager: LocationManager())
    manager.pressure = 101.325
    manager.seaLevelPressure = 103.2
    manager.isAvailable = true

    return BarometerView(barometerManager: manager)
        .padding()
}
