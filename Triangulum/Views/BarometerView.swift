import SwiftUI

struct BarometerView: View {
    @ObservedObject var barometerManager: BarometerManager
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(spacing: CelSpace.md) {
                InstrumentHeader(icon: "barometer", title: "Barometer", tint: .celGold) {
                    CelChevron()
                }

                if !barometerManager.isAvailable {
                    CelInlineMessage(text: "Barometer not available on this device", color: .celRed)
                } else if !barometerManager.errorMessage.isEmpty {
                    CelInlineMessage(text: barometerManager.errorMessage, color: .celRed)
                } else {
                    VStack(spacing: CelSpace.md) {
                        ZStack {
                            PressureWeatherMapArt()

                            HStack(alignment: .top) {
                                MetricReadout("Pressure",
                                              value: String(format: "%.2f", barometerManager.pressure),
                                              unit: "kPa", valueColor: pressureColor, valueSize: 28)
                                MetricReadout("Sea Level",
                                              value: seaLevelPressureText, unit: "kPa",
                                              alignment: .trailing)
                            }
                            .padding(.horizontal, CelSpace.xs)
                        }
                        .frame(height: 118)

                        // Sea-level pressure requires a valid location fix.
                        // Surface a distinct hint per reason so the user
                        // understands why "Sea Level" reads "--". Tapping the
                        // card opens the detail view, which hosts the
                        // actionable "Open Settings" button for the denial case.
                        //
                        // Check the system-wide toggle first: when Location
                        // Services are off globally the per-app status retains
                        // its prior value, so both flags can be true at once.
                        // The global toggle is the true root cause and the
                        // app-settings page cannot re-enable it, so it must win
                        // over the per-app denial hint.
                        if barometerManager.seaLevelPressure == nil &&
                            barometerManager.isLocationServicesDisabled {
                            CelInlineMessage(text: "Sea level unavailable — location services disabled",
                                             color: .celRed)
                        } else if barometerManager.seaLevelPressure == nil &&
                            barometerManager.isLocationDenied {
                            CelInlineMessage(text: "Sea level unavailable — location denied. Tap for details.",
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
            .instrumentCard(tint: .celGold)
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

private struct PressureWeatherMapArt: View {
    var body: some View {
        Canvas { context, size in
            let dashed = StrokeStyle(lineWidth: 1, dash: [5, 6])
            let isobar = Color.celGold.opacity(0.30)

            context.stroke(
                Path(ellipseIn: CGRect(x: -size.width * 0.18,
                                       y: size.height * 0.08,
                                       width: size.width * 0.72,
                                       height: size.height * 0.82)),
                with: .color(isobar), style: dashed
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: size.width * 0.12,
                                       y: -size.height * 0.42,
                                       width: size.width * 0.72,
                                       height: size.height * 1.36)),
                with: .color(isobar), style: dashed
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: size.width * 0.64,
                                       y: size.height * 0.16,
                                       width: size.width * 0.48,
                                       height: size.height * 0.72)),
                with: .color(isobar), style: dashed
            )

            var front = Path()
            front.move(to: CGPoint(x: -8, y: size.height * 0.74))
            front.addCurve(to: CGPoint(x: size.width + 8, y: size.height * 0.34),
                           control1: CGPoint(x: size.width * 0.30, y: size.height * 0.96),
                           control2: CGPoint(x: size.width * 0.64, y: size.height * 0.05))
            context.stroke(front, with: .color(.celCyan.opacity(0.62)), lineWidth: 1.4)

            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.20,
                                                y: size.height * 0.70,
                                                width: 6, height: 6)),
                         with: .color(.celCyan.opacity(0.85)))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.70,
                                                y: size.height * 0.27,
                                                width: 6, height: 6)),
                         with: .color(.celCyan.opacity(0.85)))
        }
        .background(
            RadialGradient(colors: [.celGold.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 150)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
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
