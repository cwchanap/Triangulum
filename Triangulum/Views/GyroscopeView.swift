import SwiftUI
import CoreMotion

struct GyroscopeView: View {
    @ObservedObject var gyroscopeManager: GyroscopeManager

    var body: some View {
        VStack(spacing: CelSpace.md) {
            InstrumentHeader(icon: "rotate.3d", title: "Gyroscope", tint: .celCyan)

            if !gyroscopeManager.isAvailable {
                CelInlineMessage(text: "Gyroscope not available on this device", color: .celRed)
            } else if !gyroscopeManager.errorMessage.isEmpty {
                CelInlineMessage(text: gyroscopeManager.errorMessage, color: .celRed)
            } else {
                VStack(spacing: CelSpace.md) {
                    HStack(alignment: .top) {
                        MetricReadout("X-Axis",
                                      value: String(format: "%.3f", gyroscopeManager.rotationX),
                                      unit: "rad/s")
                        MetricReadout("Y-Axis",
                                      value: String(format: "%.3f", gyroscopeManager.rotationY),
                                      unit: "rad/s", alignment: .trailing)
                    }
                    HStack(alignment: .top) {
                        MetricReadout("Z-Axis",
                                      value: String(format: "%.3f", gyroscopeManager.rotationZ),
                                      unit: "rad/s")
                        MetricReadout("Magnitude",
                                      value: String(format: "%.3f", gyroscopeManager.magnitude),
                                      unit: "rad/s", alignment: .trailing, valueColor: rotationColor)
                    }
                    LuminousBar(value: min(max(gyroscopeManager.magnitude / 5.0, 0.0), 1.0),
                                tint: rotationColor)
                }
            }
        }
        .widgetCard()
    }

    private var rotationColor: Color {
        let magnitude = gyroscopeManager.magnitude
        if magnitude > 3.0 {
            return .celAmber
        } else if magnitude < 1.0 {
            return .celViolet
        } else {
            return .celCyan
        }
    }
}

#Preview {
    let manager = GyroscopeManager()
    manager.rotationX = 0.123
    manager.rotationY = -0.456
    manager.rotationZ = 0.987
    manager.magnitude = 1.123
    manager.isAvailable = true

    return GyroscopeView(gyroscopeManager: manager)
        .padding()
}
