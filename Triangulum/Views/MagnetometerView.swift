import SwiftUI
import CoreMotion

struct MagnetometerView: View {
    @ObservedObject var magnetometerManager: MagnetometerManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "compass")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Magnetometer")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }
            
            if !magnetometerManager.isAvailable {
                Text("Magnetometer not available on this device")
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else if !magnetometerManager.errorMessage.isEmpty {
                Text(magnetometerManager.errorMessage)
                    .foregroundColor(.prussianError)
                    .font(.caption)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("X-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(magnetometerManager.magneticFieldX, specifier: "%.1f") µT")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Y-Axis")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(magnetometerManager.magneticFieldY, specifier: "%.1f") µT")
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
                            Text("\(magnetometerManager.magneticFieldZ, specifier: "%.1f") µT")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Magnitude")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(magnetometerManager.magnitude, specifier: "%.1f") µT")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Heading")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(magnetometerManager.heading, specifier: "%.1f")°")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Direction")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text(compassDirection)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                    }
                    
                    ProgressView(value: magnetometerManager.magnitude / 100.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: magneticColor))
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
            return .prussianError
        } else if magnitude < 20 {
            return .prussianAccent
        } else {
            return .prussianSuccess
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