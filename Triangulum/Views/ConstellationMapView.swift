import SwiftUI
import CoreLocation

struct ConstellationMapView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var now: Date = Date()
    @Environment(\.colorScheme) private var colorScheme

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                Canvas { context, size in
                    drawSky(context: &context, size: size)
                }
                .background(colorScheme == .dark ? Color.black : Color.prussianSoft)
            }
            .padding()
            footer
        }
        .navigationTitle("Constellation Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.prussianBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onReceive(timer) { date in
            now = date
        }
    }

    // MARK: - UI

    private var header: some View {
        VStack(spacing: 8) {
            if locationManager.authorizationStatus == .denied || !locationManager.isAvailable {
                Text("Location unavailable. Enable permissions to view sky.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Observer")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(String(format: "%.4f, %.4f", locationManager.latitude, locationManager.longitude))
                        .font(.headline)
                        .foregroundColor(.prussianBlueDark)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Time (UTC)")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(Self.utcFormatter.string(from: now))
                        .font(.headline)
                        .foregroundColor(.prussianBlueDark)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.85))
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            LegendDot(color: .white, label: "Star")
            LegendLine(color: .white.opacity(0.8), label: "Constellation")
            Spacer()
            Text("Up = North  •  Right = East")
                .font(.caption2)
                .foregroundColor(.prussianBlueLight)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.85))
    }

    // MARK: - Drawing

    private func drawSky(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.48

        // Background dome circle
        let domeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let dome = Path(ellipseIn: domeRect)

        // Night-sky gradient fill inside the dome
        context.clip(to: dome)
        let gradient = Gradient(stops: [
            .init(color: Color(red: 0.02, green: 0.04, blue: 0.10), location: 0.0),
            .init(color: Color(red: 0.00, green: 0.00, blue: 0.00), location: 1.0)
        ])
        context.fill(dome, with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))

        // Procedural faint starfield (twinkling)
        drawBackgroundStars(context: &context, center: center, radius: radius)

        // Outline after fill so it stays crisp
        context.stroke(dome, with: .color(Color.white.opacity(0.25)), lineWidth: 1)

        // Altitude rings (30°, 60°)
        for alt in stride(from: 30.0, through: 60.0, by: 30.0) {
            let r = radius * (1 - alt / 90.0)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let path = Path(ellipseIn: rect)
            context.stroke(path, with: .color(Color.white.opacity(0.15)), lineWidth: 0.8)
        }

        // Cardinal directions
        let labels = [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)]
        for (text, az) in labels {
            let theta = az * .pi / 180
            let point = pointOnDome(center: center, radius: radius, azimuthRad: theta, altitudeDeg: 0)
            var resolved = context.resolve(Text(text).font(.caption).foregroundColor(.white))
            context.draw(resolved, at: point, anchor: .center)
        }

        guard locationManager.isAvailable else { return }

        // Compute star positions
        let observer = Observer(lat: locationManager.latitude, lon: locationManager.longitude)
        let lstHours = Astronomer.localSiderealTime(date: now, longitude: observer.lon)

        // Constellation lines first (so stars draw over them)
        for line in ConstellationData.lines {
            if let a = ConstellationData.star(named: line.0), let b = ConstellationData.star(named: line.1) {
                if let pa = project(star: a, lstHours: lstHours, observer: observer, center: center, radius: radius),
                   let pb = project(star: b, lstHours: lstHours, observer: observer, center: center, radius: radius) {
                    var path = Path()
                    path.move(to: pa)
                    path.addLine(to: pb)
                    context.stroke(path, with: .color(Color.white.opacity(0.5)), lineWidth: 0.7)
                }
            }
        }

        // Draw stars
        for star in ConstellationData.stars {
            if let p = project(star: star, lstHours: lstHours, observer: observer, center: center, radius: radius, returnAlt: false) {
                let size = max(1.5, 5.2 - 0.8 * star.mag)
                let rect = CGRect(x: p.x - size/2, y: p.y - size/2, width: size, height: size)
                context.fill(Path(ellipseIn: rect), with: .color(.white))

                if star.mag < 1.0 { // label brighter stars
                    let label = Text(star.name).font(.system(size: 8)).foregroundColor(.white)
                    context.draw(context.resolve(label), at: CGPoint(x: p.x + 8, y: p.y - 8), anchor: .topLeading)
                }
            }
        }
    }

    private func drawBackgroundStars(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Number scales with area; cap for performance
        let n = min(1000, max(250, Int((radius * radius) / 6)))
        let t = now.timeIntervalSince1970
        for i in 0..<n {
            let u1 = prand(Double(i) * 12.3 + 1.2345)
            let u2 = prand(Double(i) * 78.9 + 4.321)
            // Uniform in disk
            let r = Double(radius) * sqrt(u1)
            let ang = 2.0 * Double.pi * u2
            let x = center.x + CGFloat(r * cos(ang))
            let y = center.y + CGFloat(r * sin(ang))

            // Base brightness and size
            let base = 0.08 + 0.20 * prand(Double(i) * 9.73 + 0.17) // 0.08 - 0.28
            let phase = 2.0 * Double.pi * prand(Double(i) * 3.37 + 0.71)
            let twinkle = 0.7 + 0.3 * sin(1.4 * t + phase)
            let alpha = base * twinkle
            let s = 0.4 + 1.2 * prand(Double(i) * 5.11 + 0.09) // 0.4 - 1.6 px

            let rect = CGRect(x: x - s/2, y: y - s/2, width: s, height: s)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
        }
    }

    private func prand(_ n: Double) -> Double {
        let s = sin(n) * 43758.5453
        return s - floor(s)
    }

    private func project(star: Star, lstHours: Double, observer: Observer, center: CGPoint, radius: CGFloat, returnAlt: Bool = false) -> CGPoint? {
        let eq = Equatorial(raHours: star.raHours, decDeg: star.decDeg)
        let altaz = Astronomer.altAz(eq: eq, lstHours: lstHours, latDeg: observer.lat)
        guard altaz.altDeg > 0 else { return nil } // only plot above horizon
        let azRad = altaz.azDeg * .pi / 180
        let pt = pointOnDome(center: center, radius: radius, azimuthRad: azRad, altitudeDeg: altaz.altDeg)
        return pt
    }

    private func pointOnDome(center: CGPoint, radius: CGFloat, azimuthRad: Double, altitudeDeg: Double) -> CGPoint {
        // Polar projection: r = (90-alt)/90 * R, angle 0 at North, clockwise increasing azimuth
        let r = radius * CGFloat(1.0 - altitudeDeg / 90.0)
        let x = center.x + r * CGFloat(sin(azimuthRad))
        let y = center.y - r * CGFloat(cos(azimuthRad))
        return CGPoint(x: x, y: y)
    }

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
    }

    enum ConstellationData {
        static let stars: [Star] = [
            // Key bright stars (approximate J2000)
            Star(name: "Sirius", raHours: 6.75, decDeg: -16.716, mag: -1.46),
            Star(name: "Canopus", raHours: 6.4, decDeg: -52.7, mag: -0.72),
            Star(name: "Arcturus", raHours: 14.2667, decDeg: 19.183, mag: -0.05),
            Star(name: "Vega", raHours: 18.6167, decDeg: 38.7837, mag: 0.03),
            Star(name: "Capella", raHours: 5.2667, decDeg: 46.0, mag: 0.08),
            Star(name: "Rigel", raHours: 5.242, decDeg: -8.2017, mag: 0.18),
            Star(name: "Procyon", raHours: 7.655, decDeg: 5.225, mag: 0.38),
            Star(name: "Betelgeuse", raHours: 5.9195, decDeg: 7.407, mag: 0.42),
            Star(name: "Achernar", raHours: 1.65, decDeg: -57.15, mag: 0.46),
            Star(name: "Hadar", raHours: 14.0637, decDeg: -60.373, mag: 0.61),
            Star(name: "Altair", raHours: 19.8464, decDeg: 8.8683, mag: 0.77),
            Star(name: "Aldebaran", raHours: 4.5987, decDeg: 16.509, mag: 0.85),
            Star(name: "Spica", raHours: 13.4199, decDeg: -11.161, mag: 1.04),
            Star(name: "Antares", raHours: 16.4901, decDeg: -26.432, mag: 1.06),
            Star(name: "Pollux", raHours: 7.7553, decDeg: 28.026, mag: 1.14),
            Star(name: "Fomalhaut", raHours: 22.9667, decDeg: -29.6167, mag: 1.16),
            Star(name: "Deneb", raHours: 20.6905, decDeg: 45.2803, mag: 1.25),
            Star(name: "Mimosa", raHours: 12.7953, decDeg: -59.6888, mag: 1.25),
            Star(name: "Regulus", raHours: 10.1395, decDeg: 11.9672, mag: 1.35),
            Star(name: "Castor", raHours: 7.5797, decDeg: 31.8883, mag: 1.58),
            Star(name: "Gacrux", raHours: 12.5194, decDeg: -57.1132, mag: 1.63),
            Star(name: "Bellatrix", raHours: 5.4189, decDeg: 6.3497, mag: 1.64),
            Star(name: "Elnath", raHours: 5.4382, decDeg: 28.6075, mag: 1.65),
            Star(name: "Miaplacidus", raHours: 9.2199, decDeg: -69.7172, mag: 1.67),
            Star(name: "Alnilam", raHours: 5.6036, decDeg: -1.2019, mag: 1.69),
            Star(name: "Alnair", raHours: 22.1372, decDeg: -46.9611, mag: 1.73),
            Star(name: "Alioth", raHours: 12.899, decDeg: 55.961, mag: 1.76),
            Star(name: "Polaris", raHours: 2.5303, decDeg: 89.2641, mag: 1.98),
            Star(name: "Mintaka", raHours: 5.5334, decDeg: -0.2991, mag: 2.23),
            Star(name: "Alnitak", raHours: 5.6793, decDeg: -1.9426, mag: 1.74),
            Star(name: "Saiph", raHours: 5.7959, decDeg: -9.6696, mag: 2.06),
            Star(name: "Dubhe", raHours: 11.0621, decDeg: 61.7508, mag: 1.81),
            Star(name: "Merak", raHours: 11.0307, decDeg: 56.3824, mag: 2.37),
            Star(name: "Phecda", raHours: 11.8972, decDeg: 53.6948, mag: 2.43),
            Star(name: "Megrez", raHours: 12.2571, decDeg: 57.0326, mag: 3.31),
            Star(name: "Mizar", raHours: 13.3988, decDeg: 54.9254, mag: 2.27),
            Star(name: "Alkaid", raHours: 13.7923, decDeg: 49.3133, mag: 1.85)
        ]

        // Simple line segments for Orion and Big Dipper
        static let lines: [(String, String)] = [
            // Orion
            ("Betelgeuse", "Bellatrix"),
            ("Betelgeuse", "Alnilam"),
            ("Bellatrix", "Alnilam"),
            ("Alnitak", "Alnilam"),
            ("Alnilam", "Mintaka"),
            ("Rigel", "Saiph"),
            ("Rigel", "Alnitak"),
            ("Saiph", "Mintaka"),
            // Big Dipper (Ursa Major)
            ("Dubhe", "Merak"),
            ("Merak", "Phecda"),
            ("Phecda", "Megrez"),
            ("Megrez", "Alioth"),
            ("Alioth", "Mizar"),
            ("Mizar", "Alkaid")
        ]

        static func star(named name: String) -> Star? {
            return stars.first { $0.name == name }
        }
    }

    // MARK: - Formatters
    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundColor(.prussianBlueLight)
        }
    }
}

private struct LegendLine: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 20, height: 2)
            Text(label).font(.caption2).foregroundColor(.prussianBlueLight)
        }
    }
}

#Preview {
    ConstellationMapView(locationManager: LocationManager())
}
