import Foundation
import SwiftData

@Model
class SensorReading {
    var timestamp: Date
    var sensorType: SensorType
    var value: Double
    var unit: String
    var additionalData: String?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    
    init(timestamp: Date = Date(), sensorType: SensorType, value: Double, unit: String, additionalData: String? = nil, latitude: Double? = nil, longitude: Double? = nil, altitude: Double? = nil) {
        self.timestamp = timestamp
        self.sensorType = sensorType
        self.value = value
        self.unit = unit
        self.additionalData = additionalData
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

enum SensorType: String, CaseIterable, Codable {
    case barometer = "barometer"
    case gps = "gps"
    case accelerometer = "accelerometer"
    case gyroscope = "gyroscope"
    case magnetometer = "magnetometer"
    
    var displayName: String {
        switch self {
        case .barometer:
            return "Barometer"
        case .gps:
            return "GPS"
        case .accelerometer:
            return "Accelerometer"
        case .gyroscope:
            return "Gyroscope"
        case .magnetometer:
            return "Magnetometer"
        }
    }
}