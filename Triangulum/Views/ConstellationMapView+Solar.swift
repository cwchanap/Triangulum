import Foundation

extension ConstellationMapView.Astronomer {
    /// Returns the instant when the Sun crosses `altitudeDeg` on `localDate`
    /// in `timeZone` — the destination's calendar day, not the device's.
    /// - Parameters:
    ///   - altitudeDeg: Target altitude (negative = below horizon). e.g. -0.833 for sunrise.
    ///   - rising: true = morning crossing, false = evening crossing.
    ///   - localDate: Destination-local calendar day.
    ///   - timeZone: Destination time zone used to resolve `localDate`.
    ///   - latDeg: Observer latitude in degrees.
    ///   - lonDeg: Observer longitude in degrees.
    /// - Returns: nil if the Sun never reaches this altitude on this date (polar day/night).
    static func solarCrossing(
        altitudeDeg: Double,
        rising: Bool,
        localDate: LocalDate,
        timeZone: TimeZone,
        latDeg: Double,
        lonDeg: Double
    ) -> Date? {
        let rad = Double.pi / 180.0
        let latRad = latDeg * rad

        guard let dayStart = try? localDate.start(in: timeZone),
              let dayEnd = try? localDate.endExclusive(in: timeZone),
              let localNoon = try? localDate.noon(in: timeZone) else { return nil }

        // Local-noon reference approximation: the Sun's declination changes
        // slowly, so noon is a good starting point for the hour-angle / transit
        // calculation. The result is then refined against the actual
        // solar-altitude path (below) so a real in-day crossing is never
        // dropped just because the approximation landed on an adjacent civil
        // day — which happens near high-latitude transition dates where
        // declination drifts enough across the hours between noon and the
        // crossing to shift the approximate result ~15 min past midnight.
        let sunEq = sunEquatorial(date: localNoon)
        let decRad = sunEq.decDeg * rad

        // Hour angle for the target altitude: cos(H) = (sin(h) - sin(lat)·sin(dec)) / (cos(lat)·cos(dec))
        let sinH = sin(altitudeDeg * rad)
        let cosHdenom = cos(latRad) * cos(decRad)
        let cosHFeasible = abs(cosHdenom) > 1e-6
        let cosH = cosHFeasible ? (sinH - sin(latRad) * sin(decRad)) / cosHdenom : 0
        let noonApproximationFeasible = cosHFeasible && cosH >= -1.0 && cosH <= 1.0
        guard noonApproximationFeasible else {
            // The noon-based hour-angle approximation is infeasible — either a
            // degenerate denominator (cos(lat)·cos(dec) ≈ 0, near the poles) or
            // cosH slightly outside [-1, 1] near polar transition dates where
            // declination drifts enough across the hours between noon and the
            // crossing to push the approximation past the trigonometric limit.
            // That does NOT mean no crossing exists: the real altitude path may
            // still cross the target later/earlier in the civil day. Fall back
            // to a full-day altitude-path scan instead of dropping the event.
            return scanDayForSolarCrossing(
                altitudeDeg: altitudeDeg,
                rising: rising,
                dayStart: dayStart,
                dayEnd: dayEnd,
                latDeg: latDeg,
                lonDeg: lonDeg
            )
        }
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
        let approximate = transitDate.addingTimeInterval((rising ? -hourAngleHours : hourAngleHours) * 3600)

        // Refine the noon approximation onto the real altitude-path root
        // within `[dayStart, dayEnd)`. Brackets the approximation with a ±1 h
        // window and bisects on the actual Sun altitude; if the approximation
        // is too far off to bracket (transit shifted across midnight, etc.),
        // falls back to a full-day scan. Returns nil only when the Sun
        // genuinely never crosses the target altitude on this civil day.
        return refineSolarCrossing(
            approximate: approximate,
            altitudeDeg: altitudeDeg,
            rising: rising,
            dayStart: dayStart,
            dayEnd: dayEnd,
            latDeg: latDeg,
            lonDeg: lonDeg
        )
    }

    /// Refines an approximate solar crossing onto the real altitude-path root
    /// within `[dayStart, dayEnd)`. Brackets the approximation with a ±1 h
    /// window and bisects; if the approximation is too far off to bracket,
    /// scans the whole civil day for the requested crossing direction.
    private static func refineSolarCrossing(
        approximate: Date,
        altitudeDeg: Double,
        rising: Bool,
        dayStart: Date,
        dayEnd: Date,
        latDeg: Double,
        lonDeg: Double
    ) -> Date? {
        let window: TimeInterval = 3600
        if let crossing = bisectSolarCrossing(
            from: approximate.addingTimeInterval(-window),
            to: approximate.addingTimeInterval(window),
            altitudeDeg: altitudeDeg,
            rising: rising,
            dayStart: dayStart,
            dayEnd: dayEnd,
            latDeg: latDeg,
            lonDeg: lonDeg
        ) {
            return crossing
        }
        return scanDayForSolarCrossing(
            altitudeDeg: altitudeDeg,
            rising: rising,
            dayStart: dayStart,
            dayEnd: dayEnd,
            latDeg: latDeg,
            lonDeg: lonDeg
        )
    }

    /// Sun altitude above the horizon (degrees) at an instant, via the
    /// existing equatorial → horizontal path. Shared by the bisection and
    /// scan refinements so they refine against the same model that draws the
    /// star map.
    private static func sunAltitude(_ date: Date, latDeg: Double, lonDeg: Double) -> Double {
        let sun = sunEquatorial(date: date)
        let lst = localSiderealTime(date: date, longitude: lonDeg)
        return altAz(eq: sun, lstHours: lst, latDeg: latDeg).altDeg
    }

    /// Bisection within `[from, to]` for the requested crossing direction,
    /// returning the root only if it lies within `[dayStart, dayEnd)`.
    /// Requires a sign change of `altitude − target` in the requested
    /// direction (rising: below → above; setting: above → below) across the
    /// bracket; returns nil otherwise.
    private static func bisectSolarCrossing(
        from: Date,
        to: Date,
        altitudeDeg: Double,
        rising: Bool,
        dayStart: Date,
        dayEnd: Date,
        latDeg: Double,
        lonDeg: Double
    ) -> Date? {
        func f(_ date: Date) -> Double {
            sunAltitude(date, latDeg: latDeg, lonDeg: lonDeg) - altitudeDeg
        }
        var lo = from
        var hi = to
        var fLo = f(lo)
        var fHi = f(hi)
        // The bracket must straddle the root in the requested direction.
        // rising: f goes negative (below) → non-negative (above)
        // setting: f goes positive (above) → non-positive (below)
        let bracketed = rising
            ? (fLo < 0 && fHi >= 0)
            : (fLo > 0 && fHi <= 0)
        guard bracketed else { return nil }
        for _ in 0..<60 {
            let mid = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            let fMid = f(mid)
            if abs(fMid) < 1e-9 || hi.timeIntervalSince(lo) < 1e-3 {
                return (mid >= dayStart && mid < dayEnd) ? mid : nil
            }
            // Keep the half whose endpoints straddle the root in the
            // requested direction.
            if rising {
                if fLo < 0 && fMid >= 0 {
                    hi = mid
                    fHi = fMid
                } else {
                    lo = mid
                    fLo = fMid
                }
            } else {
                if fLo > 0 && fMid <= 0 {
                    hi = mid
                    fHi = fMid
                } else {
                    lo = mid
                    fLo = fMid
                }
            }
        }
        let root = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
        return (root >= dayStart && root < dayEnd) ? root : nil
    }

    /// Scans the civil day at 10-minute resolution for the requested crossing
    /// direction and bisects the bracketing interval. The Sun's altitude is
    /// monotonic between transits, so a single civil day has at most one
    /// rising and one setting of a given altitude; the scan locates the
    /// correct one by direction and refines it precisely.
    private static func scanDayForSolarCrossing(
        altitudeDeg: Double,
        rising: Bool,
        dayStart: Date,
        dayEnd: Date,
        latDeg: Double,
        lonDeg: Double
    ) -> Date? {
        let step: TimeInterval = 600
        var prev = dayStart
        var prevF = sunAltitude(prev, latDeg: latDeg, lonDeg: lonDeg) - altitudeDeg
        var t = dayStart.addingTimeInterval(step)
        while t < dayEnd {
            let fT = sunAltitude(t, latDeg: latDeg, lonDeg: lonDeg) - altitudeDeg
            let crossed = rising ? (prevF < 0 && fT >= 0) : (prevF > 0 && fT <= 0)
            if crossed {
                return bisectSolarCrossing(
                    from: prev,
                    to: t,
                    altitudeDeg: altitudeDeg,
                    rising: rising,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    latDeg: latDeg,
                    lonDeg: lonDeg
                )
            }
            prev = t
            prevF = fT
            t = t.addingTimeInterval(step)
        }
        // Final partial step landing on dayEnd.
        let fEnd = sunAltitude(dayEnd, latDeg: latDeg, lonDeg: lonDeg) - altitudeDeg
        let crossed = rising ? (prevF < 0 && fEnd >= 0) : (prevF > 0 && fEnd <= 0)
        guard crossed else { return nil }
        return bisectSolarCrossing(
            from: prev,
            to: dayEnd,
            altitudeDeg: altitudeDeg,
            rising: rising,
            dayStart: dayStart,
            dayEnd: dayEnd,
            latDeg: latDeg,
            lonDeg: lonDeg
        )
    }
}
