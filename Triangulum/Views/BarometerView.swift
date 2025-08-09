import SwiftUI
import CoreMotion

struct BarometerView: View {
    @ObservedObject var barometerManager: BarometerManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "barometer")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Barometer")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
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
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Relative Altitude")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text("\(barometerManager.relativeAltitude, specifier: "%.2f") m")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.prussianBlueDark)
                        }
                        
                        Spacer()
                    }
                    
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

#Preview {
    let manager = BarometerManager()
    manager.pressure = 101.325
    manager.relativeAltitude = 15.5
    manager.seaLevelPressure = 103.2
    manager.isAvailable = true
    
    return BarometerView(barometerManager: manager)
        .padding()
}