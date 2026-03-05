import Foundation

extension ConstellationMapView.Astronomer {
    // MARK: - Planet Positions (Meeus Ch.33 Low-Accuracy)

    static func planetEquatorial(planet: Planet, date: Date) -> ConstellationMapView.Equatorial {
        switch planet.name {
        case "Mercury": return mercuryEquatorial(date: date)
        case "Venus":   return venusEquatorial(date: date)
        case "Mars":    return marsEquatorial(date: date)
        case "Jupiter": return jupiterEquatorial(date: date)
        default:          return saturnEquatorial(date: date)
        }
    }

    /// Ecliptic longitude of an inner planet (degrees 0..360), used for phase calculation.
    static func planetEclipticLongitude(planet: Planet, date: Date) -> Double {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        switch planet.name {
        case "Mercury":
            let meanLongitude = (252.2509 + 4.09233445 * d).truncatingRemainder(dividingBy: 360)
            let meanAnomaly = (174.7925 + 4.09233445 * d) * rad
            var lon = meanLongitude + 23.4400 * sin(meanAnomaly) + 2.9988 * sin(2 * meanAnomaly)
            lon = lon.truncatingRemainder(dividingBy: 360)
            return lon < 0 ? lon + 360 : lon
        case "Venus":
            let meanLongitude = (181.9798 + 1.60213034 * d).truncatingRemainder(dividingBy: 360)
            let meanAnomaly = (50.3766 + 1.60213034 * d) * rad
            var lon = meanLongitude + 0.7758 * sin(meanAnomaly) + 0.0033 * sin(2 * meanAnomaly)
            lon = lon.truncatingRemainder(dividingBy: 360)
            return lon < 0 ? lon + 360 : lon
        default:
            // Outer planets: not used for phase calculation (isInner = false)
            return 0
        }
    }

    /// Illuminated fraction for inner planets (Mercury, Venus).
    /// planetLon and sunLon in degrees.
    static func innerPlanetIllumination(planetLon: Double, sunLon: Double) -> Double {
        var elongation = planetLon - sunLon
        elongation = elongation.truncatingRemainder(dividingBy: 360)
        if elongation < 0 { elongation += 360 }
        let phaseAngleRad = elongation * Double.pi / 180.0
        return 0.5 * (1.0 + cos(phaseAngleRad))
    }

    static func mercuryEquatorial(date: Date) -> ConstellationMapView.Equatorial {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        let meanLongitude = (252.2509 + 4.09233445 * d).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = (174.7925 + 4.09233445 * d) * rad
        let lonDeg = meanLongitude + 23.4400 * sin(meanAnomaly) + 2.9988 * sin(2 * meanAnomaly)
        let rAU = 0.38710 * (1 - 0.20563 * cos(meanAnomaly))
        return innerPlanetToEquatorial(lonDeg: lonDeg, rAU: rAU, date: date)
    }

    static func venusEquatorial(date: Date) -> ConstellationMapView.Equatorial {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        let meanLongitude = (181.9798 + 1.60213034 * d).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = (50.3766 + 1.60213034 * d) * rad
        let lonDeg = meanLongitude + 0.7758 * sin(meanAnomaly) + 0.0033 * sin(2 * meanAnomaly)
        let rAU = 0.72333 * (1 - 0.00677 * cos(meanAnomaly))
        return innerPlanetToEquatorial(lonDeg: lonDeg, rAU: rAU, date: date)
    }

    static func marsEquatorial(date: Date) -> ConstellationMapView.Equatorial {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        let l = (355.433 + 0.52402068 * d).truncatingRemainder(dividingBy: 360)
        let m = (19.3730 + 0.52402068 * d) * rad
        let lonDeg = l + 10.6912 * sin(m) + 0.6228 * sin(2 * m) + 0.0503 * sin(3 * m)
        let latDeg = 1.8497 * sin((49.558 + 0.77481 * d) * rad)
        let rAU = 1.52366 * (1 - 0.09340 * cos(m))
        return outerPlanetToEquatorial(lonDeg: lonDeg, latDeg: latDeg, rAU: rAU, date: date)
    }

    static func jupiterEquatorial(date: Date) -> ConstellationMapView.Equatorial {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        let l = (34.351 + 0.08309104 * d).truncatingRemainder(dividingBy: 360)
        let m = (20.9 + 0.08309104 * d) * rad
        let lonDeg = l + 5.555 * sin(m) + 0.168 * sin(2 * m)
        let latDeg = 1.3 * sin((168.6 + 0.0829 * d) * rad)
        let rAU = 5.2034 * (1 - 0.04849 * cos(m))
        return outerPlanetToEquatorial(lonDeg: lonDeg, latDeg: latDeg, rAU: rAU, date: date)
    }

    static func saturnEquatorial(date: Date) -> ConstellationMapView.Equatorial {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        let l = (50.077 + 0.03345972 * d).truncatingRemainder(dividingBy: 360)
        let m = (317.020 + 0.03345972 * d) * rad
        let lonDeg = l + 6.3585 * sin(m) + 0.2566 * sin(2 * m)
        let latDeg = 2.487 * sin((279.507 + 0.03345 * d) * rad)
        let rAU = 9.5371 * (1 - 0.05551 * cos(m))
        return outerPlanetToEquatorial(lonDeg: lonDeg, latDeg: latDeg, rAU: rAU, date: date)
    }

    // Shared heliocentric -> geocentric -> equatorial conversion for inner planets (lat ≈ 0).
    private static func innerPlanetToEquatorial(
        lonDeg: Double,
        rAU: Double,
        date: Date
    ) -> ConstellationMapView.Equatorial {
        let jd = julianDay(date: date)
        let d = jd - 2451545.0
        let rad = Double.pi / 180.0
        let sunLon = sunEclipticLongitude(date: date) * rad
        let lonRad = lonDeg * rad
        let xg = rAU * cos(lonRad) - cos(sunLon)
        let yg = rAU * sin(lonRad) - sin(sunLon)
        let epsilon = (23.439 - 0.0000004 * d) * rad
        let ra = atan2(cos(epsilon) * yg, xg)
        let dec = atan2(sin(epsilon) * yg, sqrt(xg * xg + yg * yg))
        let raHours = (ra < 0 ? ra + 2 * Double.pi : ra) * 12.0 / Double.pi
        return ConstellationMapView.Equatorial(raHours: raHours, decDeg: dec * 180.0 / Double.pi)
    }

    // Shared heliocentric -> geocentric -> equatorial conversion for outer planets.
    private static func outerPlanetToEquatorial(
        lonDeg: Double,
        latDeg: Double,
        rAU: Double,
        date: Date
    ) -> ConstellationMapView.Equatorial {
        let julianDate = julianDay(date: date)
        let daysSinceJ2000 = julianDate - 2451545.0
        let degreesToRadians = Double.pi / 180.0
        let sunLongitude = sunEclipticLongitude(date: date) * degreesToRadians
        let longitudeRad = lonDeg * degreesToRadians
        let latitudeRad = latDeg * degreesToRadians
        let heliocentricX = rAU * cos(latitudeRad) * cos(longitudeRad)
        let heliocentricY = rAU * cos(latitudeRad) * sin(longitudeRad)
        let heliocentricZ = rAU * sin(latitudeRad)
        let geocentricX = heliocentricX - cos(sunLongitude)
        let geocentricY = heliocentricY - sin(sunLongitude)
        let obliquity = (23.439 - 0.0000004 * daysSinceJ2000) * degreesToRadians
        let equatorialX = geocentricX
        let equatorialY = geocentricY * cos(obliquity) - heliocentricZ * sin(obliquity)
        let equatorialZ = geocentricY * sin(obliquity) + heliocentricZ * cos(obliquity)
        let rightAscension = atan2(equatorialY, equatorialX)
        let declination = atan2(equatorialZ, sqrt(equatorialX * equatorialX + equatorialY * equatorialY))
        let rightAscensionHours = (rightAscension < 0 ? rightAscension + 2 * Double.pi : rightAscension) * 12.0 / Double.pi
        return ConstellationMapView.Equatorial(raHours: rightAscensionHours, decDeg: declination * 180.0 / Double.pi)
    }

    // MARK: - Planet Rise/Set

    struct PlanetEvent {
        let planet: Planet
        let label: String  // e.g. "Jupiter rises 21:14"
    }

    /// Returns the next planet rise or set event within a 24h window.
    /// Uses the analytical hour-angle formula for the standard horizon (-0.833°).
    static func nextPlanetEvent(
        planets: [Planet],
        date: Date,
        latDeg: Double,
        lonDeg: Double
    ) -> PlanetEvent? {
        let rad = Double.pi / 180.0
        let latRad = latDeg * rad
        let sinH0 = sin(-0.833 * rad)
        var nearest: (interval: TimeInterval, event: PlanetEvent)?

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current

        for planet in planets {
            let eq = planetEquatorial(planet: planet, date: date)
            let decRad = eq.decDeg * rad
            let cosH0denom = cos(latRad) * cos(decRad)
            guard abs(cosH0denom) > 1e-6 else { continue }
            let cosH0 = (sinH0 - sin(latRad) * sin(decRad)) / cosH0denom
            guard cosH0 >= -1.0 && cosH0 <= 1.0 else { continue }  // circumpolar or never rises
            let hourAngleHours = acos(cosH0) * 12.0 / Double.pi

            let lst = localSiderealTime(date: date, longitude: lonDeg)
            var hoursToTransit = eq.raHours - lst
            hoursToTransit = hoursToTransit.truncatingRemainder(dividingBy: 24)
            if hoursToTransit < 0 { hoursToTransit += 24 }

            for (hoursAhead, verb) in [
                (hoursToTransit - hourAngleHours, "rises"),
                (hoursToTransit + hourAngleHours, "sets")
            ] {
                var h = hoursAhead.truncatingRemainder(dividingBy: 24)
                if h < 0 { h += 24 }
                let intervalSecs = h * 3600
                let eventDate = date.addingTimeInterval(intervalSecs)
                let timeStr = formatter.string(from: eventDate)
                let event = PlanetEvent(planet: planet, label: "\(planet.name) \(verb) \(timeStr)")
                if nearest == nil || intervalSecs < nearest!.interval {
                    nearest = (intervalSecs, event)
                }
            }
        }

        return nearest?.event
    }
}
