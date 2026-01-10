import Foundation
import SwiftData

@Model
final class PressureReading {
    var timestamp: Date
    var pressure: Double      // kPa (must be positive and finite)
    var altitude: Double      // meters (from GPS, can be negative for below sea level)
    var seaLevelPressure: Double  // kPa (must be positive and finite)

    /// Creates a new pressure reading with validation
    /// - Parameters:
    ///   - timestamp: When the reading was taken (defaults to now)
    ///   - pressure: Pressure in kPa (must be positive and finite)
    ///   - altitude: Altitude in meters from GPS (can be negative)
    ///   - seaLevelPressure: Sea-level adjusted pressure in kPa (must be positive and finite)
    init(timestamp: Date = Date(), pressure: Double, altitude: Double, seaLevelPressure: Double) {
        // Validate pressure values are physically meaningful
        precondition(pressure > 0 && pressure.isFinite, "Pressure must be positive and finite, got: \(pressure)")
        precondition(seaLevelPressure > 0 && seaLevelPressure.isFinite,
                     "Sea level pressure must be positive and finite, got: \(seaLevelPressure)")
        precondition(altitude.isFinite, "Altitude must be finite, got: \(altitude)")

        self.timestamp = timestamp
        self.pressure = pressure
        self.altitude = altitude
        self.seaLevelPressure = seaLevelPressure
    }
}
