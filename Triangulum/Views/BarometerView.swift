import SwiftUI

struct BarometerView: View {
    @ObservedObject var barometerManager: BarometerManager
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(spacing: CelSpace.md) {
                InstrumentHeader(icon: "barometer", title: "Barometer", tint: .celCyan) {
                    CelChevron()
                }

                if !barometerManager.isAvailable {
                    CelInlineMessage(text: "Barometer not available on this device", color: .celRed)
                } else if !barometerManager.errorMessage.isEmpty {
                    CelInlineMessage(text: barometerManager.errorMessage, color: .celRed)
                } else {
                    VStack(spacing: CelSpace.md) {
                        HStack(alignment: .top) {
                            MetricReadout("Pressure",
                                          value: String(format: "%.2f", barometerManager.pressure),
                                          unit: "kPa", valueColor: pressureColor, valueSize: 28)
                            MetricReadout("Sea Level",
                                          value: seaLevelPressureText, unit: "kPa",
                                          alignment: .trailing)
                        }

                        // Sea-level pressure requires a valid location fix.
                        // When location access is denied, surface a hint so the
                        // user understands why "Sea Level" reads "--". Tapping
                        // the card opens the detail view, which hosts the
                        // actionable "Open Settings" button.
                        if barometerManager.seaLevelPressure == nil &&
                            barometerManager.isLocationDenied {
                            CelInlineMessage(text: "Sea level unavailable — location denied. Tap for settings.",
                                             color: .celAmber)
                        }

                        // Trend indicator
                        if let historyManager = barometerManager.historyManager {
                            TrendIndicatorView(historyManager: historyManager)
                        }

                        // History recording error indicator
                        if let recordingError = barometerManager.historyRecordingError {
                            CelInlineMessage(text: "Recording issue: \(recordingError.localizedDescription)",
                                             color: .celAmber)
                        }

                        LuminousBar(value: min(max(barometerManager.pressure / 110.0, 0.0), 1.0),
                                    tint: pressureColor)
                    }
                }
            }
            .widgetCard()
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
            return .celAmber
        } else if normalizedPressure < 0.98 {
            return .celViolet
        } else {
            return .celCyan
        }
    }

    private var seaLevelPressureText: String {
        guard let seaLevelPressure = barometerManager.seaLevelPressure else {
            return "--"
        }
        // Unit is rendered separately by MetricReadout(unit: "kPa");
        // keep the value numeric to avoid a duplicated "kPa kPa".
        return String(format: "%.2f", seaLevelPressure)
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
                .foregroundStyle(trendColor)
                .shadow(color: trendColor.opacity(0.6), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                // Prediction text
                Text(historyManager.trend.prediction)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.celText)

                // Rate of change
                if historyManager.trend != .unknown {
                    Text(rateText)
                        .font(.celTiny)
                        .foregroundStyle(Color.celTextDim)
                }
            }

            Spacer()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(trendColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(trendColor.opacity(0.3), lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trendAccessibilityLabel)
        .accessibilityHint("Pressure trend indicator")
    }

    private var trendColor: Color {
        switch historyManager.trend {
        case .risingFast, .rising:
            return .celGreen
        case .steady:
            return .celCyan
        case .falling, .fallingFast:
            return .celAmber
        case .unknown:
            return .celTextDim
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
