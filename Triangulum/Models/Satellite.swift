//
//  Satellite.swift
//  Triangulum
//
//  Satellite tracking data models for ISS, Hubble, and Tiangong
//

import Foundation
import simd

// MARK: - TLE (Two-Line Element Set)

/// Represents a Two-Line Element set for satellite orbital data
struct TLE: Codable, Equatable {
    let name: String
    let line1: String
    let line2: String

    // Parsed orbital elements (extracted from TLE lines)
    let epoch: Date
    let inclination: Double        // degrees
    let rightAscension: Double     // degrees (RAAN)
    let eccentricity: Double       // dimensionless
    let argumentOfPerigee: Double  // degrees
    let meanAnomaly: Double        // degrees
    let meanMotion: Double         // revolutions per day
    let bstar: Double              // drag term

    /// Parse TLE from raw text lines
    /// - Parameters:
    ///   - name: Satellite name
    ///   - line1: First TLE line (starts with "1")
    ///   - line2: Second TLE line (starts with "2")
    init?(name: String, line1: String, line2: String) {
        guard line1.count >= 69, line2.count >= 69 else { return nil }
        guard line1.hasPrefix("1"), line2.hasPrefix("2") else { return nil }

        self.name = name.trimmingCharacters(in: .whitespaces)
        self.line1 = line1
        self.line2 = line2

        // Parse epoch from line 1 (columns 19-32)
        let epochStr = TLE.substring(line1, start: 18, length: 14)
        guard let epoch = TLE.parseEpoch(epochStr) else { return nil }
        self.epoch = epoch

        // Parse B* drag term from line 1 (columns 54-61)
        let bstarStr = TLE.substring(line1, start: 53, length: 8)
        self.bstar = TLE.parseDecimalWithExponent(bstarStr)

        // Parse orbital elements from line 2
        // Inclination (columns 9-16)
        let incStr = TLE.substring(line2, start: 8, length: 8)
        self.inclination = Double(incStr.trimmingCharacters(in: .whitespaces)) ?? 0

        // RAAN (columns 18-25)
        let raanStr = TLE.substring(line2, start: 17, length: 8)
        self.rightAscension = Double(raanStr.trimmingCharacters(in: .whitespaces)) ?? 0

        // Eccentricity (columns 27-33, implied decimal point)
        let eccStr = TLE.substring(line2, start: 26, length: 7)
        self.eccentricity = Double("0." + eccStr.trimmingCharacters(in: .whitespaces)) ?? 0

        // Argument of perigee (columns 35-42)
        let argpStr = TLE.substring(line2, start: 34, length: 8)
        self.argumentOfPerigee = Double(argpStr.trimmingCharacters(in: .whitespaces)) ?? 0

        // Mean anomaly (columns 44-51)
        let maStr = TLE.substring(line2, start: 43, length: 8)
        self.meanAnomaly = Double(maStr.trimmingCharacters(in: .whitespaces)) ?? 0

        // Mean motion (columns 53-63)
        let mmStr = TLE.substring(line2, start: 52, length: 11)
        self.meanMotion = Double(mmStr.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    // MARK: - Parsing Helpers

    private static func substring(_ str: String, start: Int, length: Int) -> String {
        let startIndex = str.index(str.startIndex, offsetBy: min(start, str.count))
        let endIndex = str.index(startIndex, offsetBy: min(length, str.count - start))
        return String(str[startIndex..<endIndex])
    }

    private static func parseEpoch(_ str: String) -> Date? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5 else { return nil }

        // Format: YYDDD.DDDDDDDD
        let yearStr = String(trimmed.prefix(2))
        guard let year2digit = Int(yearStr) else { return nil }

        // Convert 2-digit year to 4-digit (57-99 = 1957-1999, 00-56 = 2000-2056)
        let year = year2digit >= 57 ? 1900 + year2digit : 2000 + year2digit

        // Parse day of year with fractional part
        let dayStr = String(trimmed.dropFirst(2))
        guard let dayOfYear = Double(dayStr) else { return nil }

        // Create date from year and day of year
        var components = DateComponents()
        components.year = year
        components.day = Int(dayOfYear)
        components.hour = 0
        components.minute = 0
        components.second = 0

        let calendar = Calendar(identifier: .gregorian)
        guard var date = calendar.date(from: components) else { return nil }

        // Add fractional day
        let fractionalDay = dayOfYear - floor(dayOfYear)
        date = date.addingTimeInterval(fractionalDay * 86400)

        return date
    }

    private static func parseDecimalWithExponent(_ str: String) -> Double {
        var trimmed = str.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }

        // Handle sign
        var sign: Double = 1.0
        if trimmed.hasPrefix("-") {
            sign = -1.0
            trimmed = String(trimmed.dropFirst())
        } else if trimmed.hasPrefix("+") {
            trimmed = String(trimmed.dropFirst())
        }

        // Format: NNNNN-N (e.g., "12345-4" = 0.12345e-4)
        if let expIndex = trimmed.lastIndex(where: { $0 == "-" || $0 == "+" }) {
            let mantissa = String(trimmed[..<expIndex])
            let exponent = String(trimmed[expIndex...])
            if let mantissaVal = Double("0." + mantissa),
               let expVal = Int(exponent) {
                return sign * mantissaVal * pow(10.0, Double(expVal))
            }
        }

        return 0
    }
}

// MARK: - Satellite Position

/// Position of a satellite in various coordinate systems
struct SatellitePosition: Codable {
    /// Earth-Centered Inertial coordinates (km)
    let eciX: Double
    let eciY: Double
    let eciZ: Double

    /// Geodetic coordinates
    let latitude: Double    // degrees
    let longitude: Double   // degrees
    let altitude: Double    // km above Earth surface

    /// Topocentric coordinates (relative to observer)
    let azimuthDeg: Double?     // degrees from North
    let altitudeDeg: Double?    // degrees above horizon
    let rangeKm: Double?        // distance to satellite

    /// Whether satellite is above the horizon
    var isVisible: Bool {
        guard let alt = altitudeDeg else { return false }
        return alt > 0
    }

    var eci: SIMD3<Double> {
        SIMD3(eciX, eciY, eciZ)
    }
}

// MARK: - Satellite Pass

/// Represents a predicted visible pass of a satellite
struct SatellitePass: Codable, Identifiable {
    // swiftlint:disable:next identifier_name
    let id: UUID
    let satelliteId: String
    let satelliteName: String
    let riseTime: Date
    let peakTime: Date
    let setTime: Date
    let maxAltitudeDeg: Double
    let riseAzimuthDeg: Double
    let setAzimuthDeg: Double

    init(satelliteId: String, satelliteName: String, riseTime: Date, peakTime: Date,
         setTime: Date, maxAltitudeDeg: Double, riseAzimuthDeg: Double, setAzimuthDeg: Double) {
        self.id = UUID()
        self.satelliteId = satelliteId
        self.satelliteName = satelliteName
        self.riseTime = riseTime
        self.peakTime = peakTime
        self.setTime = setTime
        self.maxAltitudeDeg = maxAltitudeDeg
        self.riseAzimuthDeg = riseAzimuthDeg
        self.setAzimuthDeg = setAzimuthDeg
    }

    /// Duration of the pass in seconds
    var duration: TimeInterval {
        setTime.timeIntervalSince(riseTime)
    }

    /// Formatted duration string
    var durationString: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Satellite

/// A tracked satellite with its orbital data and current position
struct Satellite: Identifiable, Codable {
    // swiftlint:disable:next identifier_name
    let id: String
    let name: String
    let noradId: Int
    var tle: TLE?
    var currentPosition: SatellitePosition?
    var nextPass: SatellitePass?

    /// The satellites we track
    static let tracked: [Satellite] = [
        Satellite(id: "ISS", name: "ISS (ZARYA)", noradId: 25544),
        Satellite(id: "HST", name: "HST (Hubble)", noradId: 20580),
        Satellite(id: "CSS", name: "CSS (Tiangong)", noradId: 48274)
    ]

    /// CelesTrak NORAD IDs for fetching TLE data
    static var noradIds: [Int] {
        tracked.map { $0.noradId }
    }

    // swiftlint:disable:next identifier_name
    init(id: String, name: String, noradId: Int, tle: TLE? = nil,
         currentPosition: SatellitePosition? = nil, nextPass: SatellitePass? = nil) {
        self.id = id
        self.name = name
        self.noradId = noradId
        self.tle = tle
        self.currentPosition = currentPosition
        self.nextPass = nextPass
    }
}

// MARK: - Satellite Data for Snapshots

/// Satellite data captured in a sensor snapshot
struct SatelliteSnapshotData: Codable {
    let capturedAt: Date
    let satellites: [SatellitePositionSnapshot]
    let nextISSPass: SatellitePass?
}

/// Individual satellite position for snapshot
struct SatellitePositionSnapshot: Codable, Identifiable {
    // swiftlint:disable:next identifier_name
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let altitudeKm: Double
    let azimuthDeg: Double?
    let elevationDeg: Double?
    let isVisible: Bool

    init(from satellite: Satellite) {
        self.id = satellite.id
        self.name = satellite.name
        self.latitude = satellite.currentPosition?.latitude ?? 0
        self.longitude = satellite.currentPosition?.longitude ?? 0
        self.altitudeKm = satellite.currentPosition?.altitude ?? 0
        self.azimuthDeg = satellite.currentPosition?.azimuthDeg
        self.elevationDeg = satellite.currentPosition?.altitudeDeg
        self.isVisible = satellite.currentPosition?.isVisible ?? false
    }
}
