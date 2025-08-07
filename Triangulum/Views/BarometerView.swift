import SwiftUI

struct BarometerView: View {
    @ObservedObject var barometerManager: BarometerManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "barometer")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Barometer")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if !barometerManager.isAvailable {
                Text("Barometer not available on this device")
                    .foregroundColor(.red)
                    .font(.caption)
            } else if !barometerManager.errorMessage.isEmpty {
                Text(barometerManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Pressure")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(barometerManager.pressure, specifier: "%.2f") kPa")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Relative Altitude")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(barometerManager.relativeAltitude, specifier: "%.2f") m")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                    }
                    
                    ProgressView(value: min(max(barometerManager.pressure / 110.0, 0.0), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: pressureColor))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var pressureColor: Color {
        let normalizedPressure = barometerManager.pressure / 101.325
        if normalizedPressure > 1.02 {
            return .red
        } else if normalizedPressure < 0.98 {
            return .blue
        } else {
            return .green
        }
    }
}