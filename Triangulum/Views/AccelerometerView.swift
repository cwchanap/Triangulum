import SwiftUI
import CoreMotion

struct AccelerometerView: View {
    @ObservedObject var accelerometerManager: AccelerometerManager

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "gyroscope")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Accelerometer")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            if !accelerometerManager.isAvailable {
                Text("Accelerometer not available on this device")
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else if !accelerometerManager.errorMessage.isEmpty {
                Text(accelerometerManager.errorMessage)
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("X-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(accelerometerManager.accelerationX, specifier: "%.3f") g")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Y-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(accelerometerManager.accelerationY, specifier: "%.3f") g")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Z-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(accelerometerManager.accelerationZ, specifier: "%.3f") g")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Magnitude")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(accelerometerManager.magnitude, specifier: "%.3f") g")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                    }

                    ProgressView(value: min(max(accelerometerManager.magnitude / 2.0, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: accelerationColor))
                }
            }
        }
        .widgetCard()
    }

    private var accelerationColor: Color {
        let magnitude = accelerometerManager.magnitude
        if magnitude > 1.5 {
            return .prussianError
        } else if magnitude < 0.5 {
            return .prussianAccent
        } else {
            return .prussianSuccess
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
