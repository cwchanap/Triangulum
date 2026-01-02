import Foundation
import SwiftData

@Model
final class PressureReading {
    var timestamp: Date
    var pressure: Double      // kPa
    var altitude: Double      // meters (from GPS)
    var seaLevelPressure: Double  // kPa

    init(timestamp: Date = Date(), pressure: Double, altitude: Double, seaLevelPressure: Double) {
        self.timestamp = timestamp
        self.pressure = pressure
        self.altitude = altitude
        self.seaLevelPressure = seaLevelPressure
    }
}
