import SwiftUI
import CoreMotion

struct AccelerometerView: View {
    @ObservedObject var accelerometerManager: AccelerometerManager

    var body: some View {
        VStack(spacing: CelSpace.md) {
            InstrumentHeader(icon: "move.3d", title: "Accelerometer", tint: .celCyan)

            if !accelerometerManager.isAvailable {
                CelInlineMessage(text: "Accelerometer not available on this device", color: .celRed)
            } else if !accelerometerManager.errorMessage.isEmpty {
                CelInlineMessage(text: accelerometerManager.errorMessage, color: .celRed)
            } else {
                VStack(spacing: CelSpace.md) {
                    HStack(alignment: .top) {
                        MetricReadout("X-Axis",
                                      value: String(format: "%.3f", accelerometerManager.accelerationX),
                                      unit: "g")
                        MetricReadout("Y-Axis",
                                      value: String(format: "%.3f", accelerometerManager.accelerationY),
                                      unit: "g", alignment: .trailing)
                    }
                    HStack(alignment: .top) {
                        MetricReadout("Z-Axis",
                                      value: String(format: "%.3f", accelerometerManager.accelerationZ),
                                      unit: "g")
                        MetricReadout("Magnitude",
                                      value: String(format: "%.3f", accelerometerManager.magnitude),
                                      unit: "g", alignment: .trailing, valueColor: accelerationColor)
                    }
                    LuminousBar(value: min(max(accelerometerManager.magnitude / 2.0, 0.0), 1.0),
                                tint: accelerationColor)
                }
            }
        }
        .widgetCard()
    }

    private var accelerationColor: Color {
        let magnitude = accelerometerManager.magnitude
        if magnitude > 1.5 {
            return .celAmber
        } else if magnitude < 0.5 {
            return .celViolet
        } else {
            return .celCyan
        }
    }
}

#Preview {
    let manager = AccelerometerManager()
    manager.accelerationX = 0.123
    manager.accelerationY = -0.456
    manager.accelerationZ = 0.987
    manager.magnitude = 1.123
    manager.isAvailable = true

    return AccelerometerView(accelerometerManager: manager)
        .padding()
}
