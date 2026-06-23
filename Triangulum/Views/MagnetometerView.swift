import SwiftUI
import CoreMotion

struct MagnetometerView: View {
    @ObservedObject var magnetometerManager: MagnetometerManager

    var body: some View {
        VStack(spacing: CelSpace.md) {
            InstrumentHeader(icon: "location.north.line.fill", title: "Magnetometer", tint: .celCyan)

            if !magnetometerManager.isAvailable {
                CelInlineMessage(text: "Magnetometer not available on this device", color: .celRed)
            } else if !magnetometerManager.errorMessage.isEmpty {
                CelInlineMessage(text: magnetometerManager.errorMessage, color: .celRed)
            } else {
                VStack(spacing: CelSpace.md) {
                    HStack(alignment: .top) {
                        MetricReadout("X-Axis",
                                      value: String(format: "%.1f", magnetometerManager.magneticFieldX),
                                      unit: "µT")
                        MetricReadout("Y-Axis",
                                      value: String(format: "%.1f", magnetometerManager.magneticFieldY),
                                      unit: "µT", alignment: .trailing)
                    }
                    HStack(alignment: .top) {
                        MetricReadout("Z-Axis",
                                      value: String(format: "%.1f", magnetometerManager.magneticFieldZ),
                                      unit: "µT")
                        MetricReadout("Magnitude",
                                      value: String(format: "%.1f", magnetometerManager.magnitude),
                                      unit: "µT", alignment: .trailing, valueColor: magneticColor)
                    }

                    CelDivider()

                    HStack(alignment: .top) {
                        MetricReadout("Heading",
                                      value: String(format: "%.1f°", magnetometerManager.heading),
                                      valueColor: .celGold)
                        MetricReadout("Direction", value: compassDirection,
                                      alignment: .trailing, valueColor: .celGold)
                    }

                    LuminousBar(value: min(max(magnetometerManager.magnitude / 100.0, 0.0), 1.0),
                                tint: magneticColor)
                }
            }
        }
        .widgetCard()
    }

    private var compassDirection: String {
        let heading = magnetometerManager.heading
        if heading >= 337.5 || heading < 22.5 {
            return "N"
        } else if heading >= 22.5 && heading < 67.5 {
            return "NE"
        } else if heading >= 67.5 && heading < 112.5 {
            return "E"
        } else if heading >= 112.5 && heading < 157.5 {
            return "SE"
        } else if heading >= 157.5 && heading < 202.5 {
            return "S"
        } else if heading >= 202.5 && heading < 247.5 {
            return "SW"
        } else if heading >= 247.5 && heading < 292.5 {
            return "W"
        } else {
            return "NW"
        }
    }

    private var magneticColor: Color {
        let magnitude = magnetometerManager.magnitude
        if magnitude > 80 {
            return .celAmber
        } else if magnitude < 20 {
            return .celViolet
        } else {
            return .celCyan
        }
    }
}

#Preview {
    let manager = MagnetometerManager()
    manager.magneticFieldX = 12.3
    manager.magneticFieldY = -45.6
    manager.magneticFieldZ = 98.7
    manager.magnitude = 109.2
    manager.heading = 135.5
    manager.isAvailable = true

    return MagnetometerView(magnetometerManager: manager)
        .padding()
}
