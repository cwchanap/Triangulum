import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.triangulum"

    static let weather = Logger(subsystem: subsystem, category: "weather")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let sensor = Logger(subsystem: subsystem, category: "sensor")
    static let satellite = Logger(subsystem: subsystem, category: "satellite")
    static let map = Logger(subsystem: subsystem, category: "map")
    static let snapshot = Logger(subsystem: subsystem, category: "snapshot")
    static let app = Logger(subsystem: subsystem, category: "app")
}
