import Foundation
import simd

extension ConstellationMapView {
    // MARK: - Types and Data

    struct Observer { let lat: Double; let lon: Double }

    struct Star { let name: String; let raHours: Double; let decDeg: Double; let mag: Double }

    struct Equatorial { let raHours: Double; let decDeg: Double }

    struct AltAz { let altDeg: Double; let azDeg: Double }

    enum Astronomer {
        static func julianDay(date: Date) -> Double {
            // JD from Unix time
            return 2440587.5 + date.timeIntervalSince1970 / 86400.0
        }

        static func localSiderealTime(date: Date, longitude: Double) -> Double { // hours
            // Approximate LST (accurate to ~1s for our purpose)
            let jd = julianDay(date: date)
            let d = jd - 2451545.0
            var gmst = 18.697374558 + 24.06570982441908 * d // hours
            gmst = gmst.truncatingRemainder(dividingBy: 24)
            if gmst < 0 { gmst += 24 }
            var lst = gmst + longitude / 15.0
            lst = lst.truncatingRemainder(dividingBy: 24)
            if lst < 0 { lst += 24 }
            return lst
        }

        static func altAz(eq: Equatorial, lstHours: Double, latDeg: Double) -> AltAz {
            // Convert RA/Dec (hours/deg) to Alt/Az (deg)
            let raRad = (eq.raHours / 24.0) * 2 * Double.pi
            let decRad = eq.decDeg * Double.pi / 180.0
            let latRad = latDeg * Double.pi / 180.0
            var hRad = (lstHours / 24.0) * 2 * Double.pi - raRad // hour angle
            // normalize to -pi..pi for stability
            hRad = atan2(sin(hRad), cos(hRad))

            let sinAlt = sin(decRad) * sin(latRad) + cos(decRad) * cos(latRad) * cos(hRad)
            let altRad = asin(sinAlt)

            let cosAlt = cos(altRad)
            let sinAz = -cos(decRad) * sin(hRad) / max(cosAlt, 1e-6)
            let cosAz = (sin(decRad) - sinAlt * sin(latRad)) / max(cosAlt * cos(latRad), 1e-6)
            var azRad = atan2(sinAz, cosAz) // 0 at North, increasing eastward
            if azRad < 0 { azRad += 2 * Double.pi }

            return AltAz(altDeg: altRad * 180.0 / Double.pi, azDeg: azRad * 180.0 / Double.pi)
        }

        static func sunEquatorial(date: Date) -> Equatorial {
            // Simplified solar position (sufficient for visibility factor and general orientation)
            let jd = julianDay(date: date)
            let d = jd - 2451545.0
            let L = (280.460 + 0.9856474 * d).truncatingRemainder(dividingBy: 360)
            let g = (357.528 + 0.9856003 * d) * Double.pi / 180.0 // rad
            let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * Double.pi / 180.0 // rad
            let epsilon = (23.439 - 0.0000004 * d) * Double.pi / 180.0 // rad

            let alpha = atan2(cos(epsilon) * sin(lambda), cos(lambda)) // rad
            let delta = asin(sin(epsilon) * sin(lambda)) // rad

            var raHours = (alpha >= 0 ? alpha : (alpha + 2 * Double.pi)) * 12.0 / Double.pi
            if raHours < 0 { raHours += 24 }
            if raHours >= 24 { raHours -= 24 }
            let decDeg = delta * 180.0 / Double.pi
            return Equatorial(raHours: raHours, decDeg: decDeg)
        }

        static func galacticToEquatorial(lDeg: Double, bDeg: Double) -> Equatorial {
            // Use J2000 rotation matrix inverse (transpose of EQ->GAL matrix)
            let l = lDeg * Double.pi / 180.0
            let b = bDeg * Double.pi / 180.0
            let xg = cos(b) * cos(l)
            let yg = cos(b) * sin(l)
            let zg = sin(b)

            // Transpose of equatorial->galactic matrix (J2000)
            let r11 = -0.0548755604, r12 = 0.4941094279, r13 = -0.8676661490
            let r21 = -0.8734370902, r22 = -0.4448296300, r23 = -0.1980763734
            let r31 = -0.4838350155, r32 = 0.7469822445, r33 = 0.4559837762

            let xe = r11 * xg + r12 * yg + r13 * zg
            let ye = r21 * xg + r22 * yg + r23 * zg
            let ze = r31 * xg + r32 * yg + r33 * zg

            var ra = atan2(ye, xe)
            if ra < 0 { ra += 2 * Double.pi }
            let dec = asin(ze)
            let raHours = ra * 12.0 / Double.pi
            let decDeg = dec * 180.0 / Double.pi
            return Equatorial(raHours: raHours, decDeg: decDeg)
        }

        static func moonEquatorial(date: Date) -> Equatorial {
            // Low-order lunar position sufficient for drawing
            let jd = julianDay(date: date)
            let d = jd - 2451545.0
            let rad = Double.pi / 180.0

            // Mean elements (deg)
            let Lp = (218.3164477 + 13.17639648 * d).truncatingRemainder(dividingBy: 360)
            let D = (297.8501921 + 12.19074912 * d).truncatingRemainder(dividingBy: 360) // elongation Sun-Moon
            let M = (357.5291092 + 0.98560028 * d).truncatingRemainder(dividingBy: 360) // Sun anomaly
            let Mp = (134.9633964 + 13.06499295 * d).truncatingRemainder(dividingBy: 360) // Moon anomaly
            let F = (93.2720950 + 13.22935024 * d).truncatingRemainder(dividingBy: 360) // Moon lat argument

            // Ecliptic longitude (deg), major terms
            var lon = Lp
            lon += 6.289 * sin(Mp * rad)
            lon += 1.274 * sin((2 * D - Mp) * rad)
            lon += 0.658 * sin(2 * D * rad)
            lon += 0.214 * sin((2 * Mp) * rad)
            lon += 0.110 * sin(D * rad)
            lon -= 0.186 * sin(M * rad) // solar equation of center

            // Ecliptic latitude (deg), major terms
            var lat = 5.128 * sin(F * rad)
            lat += 0.280 * sin((Mp + F) * rad)
            lat += 0.277 * sin((Mp - F) * rad)
            lat += 0.173 * sin((2 * D - F) * rad)

            let epsilon = (23.439 - 0.0000004 * d) * rad
            let lambda = lon * rad
            let beta = lat * rad

            // Ecliptic -> Equatorial
            let sinDec = sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda)
            let dec = asin(sinDec)
            let y = sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon)
            let x = cos(lambda)
            var ra = atan2(y, x)
            if ra < 0 { ra += 2 * Double.pi }

            let raHours = ra * 12.0 / Double.pi
            let decDeg = dec * 180.0 / Double.pi
            return Equatorial(raHours: raHours, decDeg: decDeg)
        }

        static func illuminationFraction(sunEq: Equatorial, moonEq: Equatorial) -> Double {
            // Convert to unit vectors in equatorial frame
            let raS = sunEq.raHours / 24.0 * 2 * Double.pi
            let decS = sunEq.decDeg * Double.pi / 180.0
            let raM = moonEq.raHours / 24.0 * 2 * Double.pi
            let decM = moonEq.decDeg * Double.pi / 180.0

            let s = SIMD3(
                cos(decS) * cos(raS),
                cos(decS) * sin(raS),
                sin(decS)
            )
            let m = SIMD3(
                cos(decM) * cos(raM),
                cos(decM) * sin(raM),
                sin(decM)
            )
            let dot = max(-1.0, min(1.0, Double(simd_dot(s, m))))
            let psi = acos(dot) // elongation
            let k = 0.5 * (1.0 + cos(psi)) // illuminated fraction [0,1]
            return k
        }

        static func sunEclipticLongitude(date: Date) -> Double { // degrees 0..360
            let jd = julianDay(date: date)
            let d = jd - 2451545.0
            let L = (280.460 + 0.9856474 * d).truncatingRemainder(dividingBy: 360)
            let g = (357.528 + 0.9856003 * d) * Double.pi / 180.0
            var lambda = L + 1.915 * sin(g) + 0.020 * sin(2 * g)
            lambda = lambda.truncatingRemainder(dividingBy: 360)
            if lambda < 0 { lambda += 360 }
            return lambda
        }

        static func moonEclipticLongitude(date: Date) -> Double { // degrees 0..360
            let jd = julianDay(date: date)
            let d = jd - 2451545.0
            let rad = Double.pi / 180.0
            let Lp = (218.3164477 + 13.17639648 * d).truncatingRemainder(dividingBy: 360)
            let D = (297.8501921 + 12.19074912 * d).truncatingRemainder(dividingBy: 360)
            let M = (357.5291092 + 0.98560028 * d).truncatingRemainder(dividingBy: 360)
            let Mp = (134.9633964 + 13.06499295 * d).truncatingRemainder(dividingBy: 360)
            var lon = Lp
            lon += 6.289 * sin(Mp * rad)
            lon += 1.274 * sin((2 * D - Mp) * rad)
            lon += 0.658 * sin(2 * D * rad)
            lon += 0.214 * sin((2 * Mp) * rad)
            lon += 0.110 * sin(D * rad)
            lon -= 0.186 * sin(M * rad)
            lon = lon.truncatingRemainder(dividingBy: 360)
            if lon < 0 { lon += 360 }
            return lon
        }

        static func moonAgeDays(date: Date) -> Double {
            let sunLon = sunEclipticLongitude(date: date)
            let moonLon = moonEclipticLongitude(date: date)
            var diff = moonLon - sunLon
            diff = diff.truncatingRemainder(dividingBy: 360)
            if diff < 0 { diff += 360 }
            let synodic = 29.53058867
            return (diff / 360.0) * synodic
        }
    }
}
