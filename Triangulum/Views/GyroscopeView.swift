import SwiftUI
import CoreMotion

struct GyroscopeView: View {
    @ObservedObject var gyroscopeManager: GyroscopeManager

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "rotate.3d")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Gyroscope")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            if !gyroscopeManager.isAvailable {
                Text("Gyroscope not available on this device")
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else if !gyroscopeManager.errorMessage.isEmpty {
                Text(gyroscopeManager.errorMessage)
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("X-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(gyroscopeManager.rotationX, specifier: "%.3f") rad/s")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Y-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(gyroscopeManager.rotationY, specifier: "%.3f") rad/s")
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
                            Text("\(gyroscopeManager.rotationZ, specifier: "%.3f") rad/s")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Magnitude")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(gyroscopeManager.magnitude, specifier: "%.3f") rad/s")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                    }

                    ProgressView(value: min(max(gyroscopeManager.magnitude / 5.0, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: rotationColor))
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

    private var rotationColor: Color {
        let magnitude = gyroscopeManager.magnitude
        if magnitude > 3.0 {
            return .prussianError
        } else if magnitude < 1.0 {
            return .prussianAccent
        } else {
            return .prussianSuccess
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
