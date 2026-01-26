//
//  SGP4Propagator.swift
//  Triangulum
//
//  Simplified SGP4 orbital propagator for satellite position calculation
//  Based on NORAD SGP4 model with J2 perturbation
//

import Foundation
import simd

/// SGP4 orbital propagator for computing satellite positions
enum SGP4Propagator {
    // MARK: - Constants

    // swiftlint:disable:next identifier_name
    private static let mu: Double = 398600.4418  // Earth's gravitational parameter (km³/s²)

    /// Earth's equatorial radius (km)
    private static let earthRadius: Double = 6378.137

    /// Earth's flattening factor (WGS84)
    private static let flattening: Double = 1.0 / 298.257223563

    // swiftlint:disable:next identifier_name
    private static let j2: Double = 1.08262668e-3  // J2 perturbation coefficient

    /// Minutes per day
    private static let minutesPerDay: Double = 1440.0

    /// Radians per degree
    private static let deg2rad: Double = .pi / 180.0

    /// Degrees per radian
    private static let rad2deg: Double = 180.0 / .pi

    // MARK: - Main Propagation

    /// Propagate satellite position to a given date
    /// - Parameters:
    ///   - tle: Two-Line Element set
    ///   - date: Target date/time
    ///   - observerLat: Observer latitude in degrees (optional, for topocentric)
    ///   - observerLon: Observer longitude in degrees (optional, for topocentric)
    /// - Returns: Satellite position in multiple coordinate systems
    static func propagate(tle: TLE, to date: Date,
                          observerLat: Double? = nil, observerLon: Double? = nil) -> SatellitePosition {
        // Time since epoch in minutes
        let tsince = date.timeIntervalSince(tle.epoch) / 60.0

        // Convert orbital elements to radians
        let incl = tle.inclination * deg2rad
        let raan = tle.rightAscension * deg2rad
        let argp = tle.argumentOfPerigee * deg2rad
        // swiftlint:disable:next identifier_name
        let ma = tle.meanAnomaly * deg2rad
        let ecc = tle.eccentricity
        let meanMotion = tle.meanMotion * 2.0 * .pi / minutesPerDay  // rad/min

        // Semi-major axis from mean motion (Kepler's 3rd law)
        // swiftlint:disable:next identifier_name
        let a1 = pow(mu / (meanMotion * meanMotion), 1.0 / 3.0) * pow(60.0, 2.0 / 3.0)

        // J2 secular perturbations
        let cosIncl = cos(incl)
        let sinIncl = sin(incl)
        let p = a1 * (1.0 - ecc * ecc)
        let j2Factor = 1.5 * j2 * earthRadius * earthRadius / (p * p)

        // Secular rates (simplified - no drag)
        let raanDot = -j2Factor * meanMotion * cosIncl
        let argpDot = j2Factor * meanMotion * (2.0 - 2.5 * sinIncl * sinIncl)
        let maDot = meanMotion

        // Propagated elements
        let propagatedRaan = raan + raanDot * tsince
        let propagatedArgp = argp + argpDot * tsince
        let propagatedMa = ma + maDot * tsince

        // Solve Kepler's equation for eccentric anomaly
        let eccentricAnomaly = solveKepler(meanAnomaly: propagatedMa, eccentricity: ecc)

        // True anomaly
        let sinE = sin(eccentricAnomaly)
        let cosE = cos(eccentricAnomaly)
        let sinNu = sqrt(1.0 - ecc * ecc) * sinE / (1.0 - ecc * cosE)
        let cosNu = (cosE - ecc) / (1.0 - ecc * cosE)
        let trueAnomaly = atan2(sinNu, cosNu)

        // Distance from Earth center
        let r = a1 * (1.0 - ecc * cosE)

        // Position in orbital plane
        let xOrb = r * cos(trueAnomaly)
        let yOrb = r * sin(trueAnomaly)

        // Rotation matrices: orbital plane -> ECI
        let cosArgp = cos(propagatedArgp)
        let sinArgp = sin(propagatedArgp)
        let cosRaan = cos(propagatedRaan)
        let sinRaan = sin(propagatedRaan)

        // ECI coordinates
        let eciX = xOrb * (cosRaan * cosArgp - sinRaan * sinArgp * cosIncl) -
               yOrb * (cosRaan * sinArgp + sinRaan * cosArgp * cosIncl)
        let eciY = xOrb * (sinRaan * cosArgp + cosRaan * sinArgp * cosIncl) -
               yOrb * (sinRaan * sinArgp - cosRaan * cosArgp * cosIncl)
        let eciZ = xOrb * sinArgp * sinIncl + yOrb * cosArgp * sinIncl

        // Convert ECI to geodetic
        let geodetic = eciToGeodetic(eci: SIMD3(eciX, eciY, eciZ), at: date)

        // Convert to topocentric if observer location provided
        var azimuth: Double?
        var altitude: Double?
        var range: Double?

        if let obsLat = observerLat, let obsLon = observerLon {
            let topo = eciToTopocentric(
                eci: SIMD3(eciX, eciY, eciZ),
                observerLat: obsLat,
                observerLon: obsLon,
                at: date
            )
            azimuth = topo.azimuth
            altitude = topo.elevation
            range = topo.range
        }

        return SatellitePosition(
            eciX: eciX,
            eciY: eciY,
            eciZ: eciZ,
            latitude: geodetic.latitude,
            longitude: geodetic.longitude,
            altitude: geodetic.altitude,
            azimuthDeg: azimuth,
            altitudeDeg: altitude,
            rangeKm: range
        )
    }

    // MARK: - Kepler's Equation

    /// Solve Kepler's equation: M = E - e*sin(E)
    /// - Parameters:
    ///   - meanAnomaly: Mean anomaly in radians
    ///   - eccentricity: Orbital eccentricity
    /// - Returns: Eccentric anomaly in radians
    private static func solveKepler(meanAnomaly: Double, eccentricity: Double) -> Double {
        // Normalize mean anomaly to [0, 2π)
        // swiftlint:disable:next identifier_name
        var ma = meanAnomaly.truncatingRemainder(dividingBy: 2.0 * .pi)
        if ma < 0 { ma += 2.0 * .pi }

        // Initial guess
        var eccentricAnomaly = ma + eccentricity * sin(ma)

        // Newton-Raphson iteration
        for _ in 0..<10 {
            let delta = (eccentricAnomaly - eccentricity * sin(eccentricAnomaly) - ma) /
                        (1.0 - eccentricity * cos(eccentricAnomaly))
            eccentricAnomaly -= delta
            if abs(delta) < 1e-12 { break }
        }

        return eccentricAnomaly
    }

    // MARK: - Coordinate Transforms

    /// Convert ECI coordinates to geodetic (lat/lon/alt)
    /// - Parameters:
    ///   - eci: Earth-Centered Inertial position in km
    ///   - date: Current date for Earth rotation angle
    /// - Returns: Geodetic coordinates
    static func eciToGeodetic(eci: SIMD3<Double>, at date: Date) -> (latitude: Double, longitude: Double, altitude: Double) {
        // Greenwich Mean Sidereal Time
        let gmst = greenwichMeanSiderealTime(date: date)

        // Convert ECI to ECEF (rotate by GMST)
        let cosGmst = cos(gmst)
        let sinGmst = sin(gmst)
        let ecefX = eci.x * cosGmst + eci.y * sinGmst
        let ecefY = -eci.x * sinGmst + eci.y * cosGmst
        let ecefZ = eci.z

        // Geodetic latitude using iterative method
        let xyDistance = sqrt(ecefX * ecefX + ecefY * ecefY)

        // Initial latitude guess
        var latitude = atan2(ecefZ, xyDistance)

        // Iterate for WGS84 ellipsoid
        let a = earthRadius
        // swiftlint:disable:next identifier_name
        let e2 = flattening * (2.0 - flattening)

        for _ in 0..<10 {
            let sinLat = sin(latitude)
            let n = a / sqrt(1.0 - e2 * sinLat * sinLat)
            let newLat = atan2(ecefZ + e2 * n * sinLat, xyDistance)
            if abs(newLat - latitude) < 1e-12 { break }
            latitude = newLat
        }

        // Longitude (simple atan2)
        var longitude = atan2(ecefY, ecefX)
        longitude *= rad2deg

        // Normalize longitude to [-180, 180]
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }

        // Altitude above ellipsoid
        let sinLat = sin(latitude)
        let n = a / sqrt(1.0 - e2 * sinLat * sinLat)
        let cosLat = cos(latitude)
        let altitude: Double
        if abs(cosLat) > 1e-8 {
            altitude = xyDistance / cosLat - n
        } else {
            altitude = ecefZ / sinLat - n * (1.0 - e2)
        }

        return (latitude: latitude * rad2deg, longitude: longitude, altitude: altitude)
    }

    /// Convert ECI coordinates to topocentric (azimuth/elevation/range)
    /// - Parameters:
    ///   - eci: Satellite ECI position in km
    ///   - observerLat: Observer latitude in degrees
    ///   - observerLon: Observer longitude in degrees
    ///   - date: Current date
    /// - Returns: Topocentric coordinates
    static func eciToTopocentric(eci: SIMD3<Double>, observerLat: Double, observerLon: Double,
                                 at date: Date) -> (azimuth: Double, elevation: Double, range: Double) {
        // Observer position in ECEF
        let latRad = observerLat * deg2rad
        let lonRad = observerLon * deg2rad
        let gmst = greenwichMeanSiderealTime(date: date)

        // Observer ECEF position (assuming sea level)
        let cosLat = cos(latRad)
        let sinLat = sin(latRad)
        let a = earthRadius
        // swiftlint:disable:next identifier_name
        let e2 = flattening * (2.0 - flattening)
        let n = a / sqrt(1.0 - e2 * sinLat * sinLat)

        let obsEcefX = n * cosLat * cos(lonRad)
        let obsEcefY = n * cosLat * sin(lonRad)
        let obsEcefZ = n * (1.0 - e2) * sinLat

        // Convert observer ECEF to ECI
        let theta = gmst + lonRad
        let obsEciX = obsEcefX * cos(gmst) - obsEcefY * sin(gmst)
        let obsEciY = obsEcefX * sin(gmst) + obsEcefY * cos(gmst)
        let obsEciZ = obsEcefZ

        // Range vector (satellite - observer) in ECI
        let rangeX = eci.x - obsEciX
        let rangeY = eci.y - obsEciY
        let rangeZ = eci.z - obsEciZ
        let rangeMag = sqrt(rangeX * rangeX + rangeY * rangeY + rangeZ * rangeZ)

        // Convert to topocentric (SEZ) coordinates
        let sinLon = sin(theta)
        let cosLon = cos(theta)

        // South-East-Zenith basis vectors in ECI
        // swiftlint:disable identifier_name
        let sX = sinLat * cosLon * rangeX + sinLat * sinLon * rangeY - cosLat * rangeZ
        let eX = -sinLon * rangeX + cosLon * rangeY
        let zX = cosLat * cosLon * rangeX + cosLat * sinLon * rangeY + sinLat * rangeZ
        // swiftlint:enable identifier_name

        // Elevation (altitude above horizon)
        let elevation = asin(zX / rangeMag) * rad2deg

        // Azimuth (from North, clockwise)
        var azimuth = atan2(eX, -sX) * rad2deg
        if azimuth < 0 { azimuth += 360 }

        return (azimuth: azimuth, elevation: elevation, range: rangeMag)
    }

    /// Calculate Greenwich Mean Sidereal Time
    /// - Parameter date: Date for calculation
    /// - Returns: GMST in radians
    static func greenwichMeanSiderealTime(date: Date) -> Double {
        // Julian Date
        let jd = 2440587.5 + date.timeIntervalSince1970 / 86400.0

        // Julian centuries from J2000.0
        let t = (jd - 2451545.0) / 36525.0

        // GMST in degrees (IAU 1982 formula)
        var gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) +
                   0.000387933 * t * t - t * t * t / 38710000.0

        // Normalize to [0, 360)
        gmst = gmst.truncatingRemainder(dividingBy: 360.0)
        if gmst < 0 { gmst += 360 }

        return gmst * deg2rad
    }

    // MARK: - Pass Prediction

    /// Find the next visible pass of a satellite
    /// - Parameters:
    ///   - tle: Satellite TLE data
    ///   - observerLat: Observer latitude in degrees
    ///   - observerLon: Observer longitude in degrees
    ///   - startDate: Start searching from this date
    ///   - minElevation: Minimum peak elevation to consider (default 10°)
    ///   - maxHours: Maximum hours to search ahead (default 48)
    /// - Returns: Next visible pass, or nil if none found
    static func findNextPass(tle: TLE, observerLat: Double, observerLon: Double,
                             startDate: Date = Date(), minElevation: Double = 10.0,
                             maxHours: Double = 48.0) -> SatellitePass? {
        let stepMinutes: Double = 1.0  // 1-minute steps
        let maxSteps = Int(maxHours * 60 / stepMinutes)

        func sample(at date: Date) -> (elevation: Double, azimuth: Double)? {
            let position = propagate(tle: tle, to: date,
                                     observerLat: observerLat, observerLon: observerLon)
            guard let elevation = position.altitudeDeg,
                  let azimuth = position.azimuthDeg else { return nil }
            return (elevation, azimuth)
        }

        func refineCrossing(from start: Date, to end: Date, startElevation: Double,
                            endElevation: Double) -> (Date, Double, Double)? {
            var lower = start
            var upper = end
            var lowerElev = startElevation

            for _ in 0..<20 {
                let mid = Date(timeIntervalSince1970: (lower.timeIntervalSince1970 + upper.timeIntervalSince1970) / 2)
                guard let midSample = sample(at: mid) else { return nil }

                if (lowerElev <= 0 && midSample.elevation > 0) || (lowerElev > 0 && midSample.elevation <= 0) {
                    upper = mid
                } else {
                    lower = mid
                    lowerElev = midSample.elevation
                }
            }

            guard let refined = sample(at: upper) else { return nil }
            return (upper, refined.azimuth, refined.elevation)
        }

        func refinePeak(from start: Date, to end: Date) -> (Date, Double)? {
            var left = start
            var right = end

            for _ in 0..<20 {
                let leftMid = Date(timeIntervalSince1970: (2 * left.timeIntervalSince1970 + right.timeIntervalSince1970) / 3)
                let rightMid = Date(timeIntervalSince1970: (left.timeIntervalSince1970 + 2 * right.timeIntervalSince1970) / 3)

                guard let leftSample = sample(at: leftMid),
                      let rightSample = sample(at: rightMid) else { return nil }

                if leftSample.elevation < rightSample.elevation {
                    left = leftMid
                } else {
                    right = rightMid
                }
            }

            let peakTime = Date(timeIntervalSince1970: (left.timeIntervalSince1970 + right.timeIntervalSince1970) / 2)
            guard let peakSample = sample(at: peakTime) else { return nil }
            return (peakTime, peakSample.elevation)
        }

        var searchStart = startDate
        if let initial = sample(at: startDate), initial.elevation > 0 {
            var backSteps = 0
            var backDate = startDate

            while backSteps < maxSteps {
                let candidateDate = backDate.addingTimeInterval(-stepMinutes * 60)
                guard let candidateSample = sample(at: candidateDate) else { break }
                if candidateSample.elevation <= 0 {
                    searchStart = candidateDate
                    break
                }
                backDate = candidateDate
                backSteps += 1
            }

            if backSteps == maxSteps {
                searchStart = backDate
            }
        }

        var isAboveHorizon = false
        var riseTime: Date?
        var riseAzimuth: Double = 0
        var peakTime: Date?
        var peakElevation: Double = 0
        var lastDate: Date?
        var lastElevation: Double = 0

        for step in 0..<maxSteps {
            let currentDate = searchStart.addingTimeInterval(Double(step) * stepMinutes * 60)
            guard let sampleResult = sample(at: currentDate) else { continue }
            let elevation = sampleResult.elevation
            let azimuth = sampleResult.azimuth

            if elevation > 0 && !isAboveHorizon {
                // Satellite just rose
                isAboveHorizon = true
                if let prevDate = lastDate {
                    if let refined = refineCrossing(from: prevDate, to: currentDate,
                                                    startElevation: lastElevation,
                                                    endElevation: elevation) {
                        riseTime = refined.0
                        riseAzimuth = refined.1
                    } else {
                        riseTime = currentDate
                        riseAzimuth = azimuth
                    }
                } else {
                    riseTime = currentDate
                    riseAzimuth = azimuth
                }
                peakElevation = elevation
                peakTime = currentDate
            } else if elevation > 0 && isAboveHorizon {
                // Satellite still visible - track peak
                if elevation > peakElevation {
                    peakElevation = elevation
                    peakTime = currentDate
                }
            } else if elevation <= 0 && isAboveHorizon {
                // Satellite just set
                if peakElevation >= minElevation, let rise = riseTime, let peak = peakTime {
                    let refinedSet: (Date, Double, Double)?
                    if let prevDate = lastDate {
                        refinedSet = refineCrossing(from: prevDate, to: currentDate,
                                                    startElevation: lastElevation,
                                                    endElevation: elevation)
                    } else {
                        refinedSet = nil
                    }

                    let setTime = refinedSet?.0 ?? currentDate
                    let setAzimuth = refinedSet?.1 ?? azimuth

                    let refinedPeak = refinePeak(from: rise, to: setTime)
                    let finalPeakTime = refinedPeak?.0 ?? peak
                    let finalPeakElevation = refinedPeak?.1 ?? peakElevation

                    return SatellitePass(
                        satelliteId: tle.name,
                        satelliteName: tle.name,
                        riseTime: rise,
                        peakTime: finalPeakTime,
                        setTime: setTime,
                        maxAltitudeDeg: finalPeakElevation,
                        riseAzimuthDeg: riseAzimuth,
                        setAzimuthDeg: setAzimuth
                    )
                }

                // Reset for next pass
                isAboveHorizon = false
                riseTime = nil
                peakTime = nil
                peakElevation = 0
            }

            lastDate = currentDate
            lastElevation = elevation
        }

        return nil
    }
}
