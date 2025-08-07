import Foundation
import SwiftData

@Model
class SensorReading {
    var timestamp: Date
    var sensorType: SensorType
    var value: Double
    var unit: String
    var additionalData: String?
    
    init(timestamp: Date = Date(), sensorType: SensorType, value: Double, unit: String, additionalData: String? = nil) {
        self.timestamp = timestamp
        self.sensorType = sensorType
        self.value = value
        self.unit = unit
        self.additionalData = additionalData
    }
}

enum SensorType: String, CaseIterable, Codable {
    case barometer = "barometer"
    case accelerometer = "accelerometer"
    case gyroscope = "gyroscope"
    case magnetometer = "magnetometer"
    
    var displayName: String {
        switch self {
        case .barometer:
            return "Barometer"
        case .accelerometer:
            return "Accelerometer"
        case .gyroscope:
            return "Gyroscope"
        case .magnetometer:
            return "Magnetometer"
        }
    }
}