import Foundation

extension ConstellationMapView.Astronomer {
    /// Returns the time on `date`'s calendar day when the Sun crosses `altitudeDeg`.
    /// - Parameters:
    ///   - altitudeDeg: Target altitude (negative = below horizon). e.g. -0.833 for sunrise.
    ///   - rising: true = morning crossing, false = evening crossing.
    ///   - date: Any moment on the target calendar day (local calendar used).
    ///   - latDeg: Observer latitude in degrees.
    ///   - lonDeg: Observer longitude in degrees.
    /// - Returns: nil if the Sun never reaches this altitude on this date (polar day/night).
    static func solarCrossing(
        altitudeDeg: Double,
        rising: Bool,
        date: Date,
        latDeg: Double,
        lonDeg: Double
    ) -> Date? {
        let rad = Double.pi / 180.0
        let latRad = latDeg * rad

        // Use local calendar noon as reference (Sun's Dec changes slowly; good approx for the day)
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        comps.nanosecond = 0
        guard let localNoon = Calendar.current.date(from: comps) else { return nil }

        let sunEq = sunEquatorial(date: localNoon)
        let decRad = sunEq.decDeg * rad

        // Hour angle for the target altitude: cos(H) = (sin(h) - sin(lat)·sin(dec)) / (cos(lat)·cos(dec))
        let sinH = sin(altitudeDeg * rad)
        let cosHdenom = cos(latRad) * cos(decRad)
        guard abs(cosHdenom) > 1e-6 else { return nil }
        let cosH = (sinH - sin(latRad) * sin(decRad)) / cosHdenom
        guard cosH >= -1.0 && cosH <= 1.0 else { return nil }
        let hourAngleHours = acos(cosH) * 12.0 / Double.pi

        // Solar transit: when hour angle = 0 → LST = RA_sun
        let lst = localSiderealTime(date: localNoon, longitude: lonDeg)
        var transitOffset = sunEq.raHours - lst
        transitOffset = transitOffset.truncatingRemainder(dividingBy: 24)
        // Normalize to ±12 h: negative = transit before noon, positive = after noon
        // (unlike nextPlanetEvent's [0,24) convention which finds the *next* transit)
        if transitOffset > 12 { transitOffset -= 24 }
        if transitOffset < -12 { transitOffset += 24 }
        let transitDate = localNoon.addingTimeInterval(transitOffset * 3600)

        // Rising = transit − H, Setting = transit + H
        return transitDate.addingTimeInterval((rising ? -hourAngleHours : hourAngleHours) * 3600)
    }
}
