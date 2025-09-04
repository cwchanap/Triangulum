import SwiftUI
import CoreLocation
import simd

struct ConstellationMapView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var now: Date = Date()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("nightVisionMode") private var nightVisionMode = false
    @AppStorage("skyShowStarLabels") private var skyShowStarLabels = true
    @AppStorage("skyShowConstellationLabels") private var skyShowConstellationLabels = true
    @AppStorage("skyCatalog") private var skyCatalog = "bright" // bright | extended
    @AppStorage("skyShowLargeCompass") private var skyShowLargeCompass = false
    @AppStorage("skySnapNorth") private var skySnapNorth = true
    @State private var zoom: CGFloat = 1.0
    @GestureState private var pinch: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var largeCompassOffset: CGSize = .zero
    @GestureState private var largeCompassDrag: CGSize = .zero

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                TimelineView(.animation) { timeline in
                    let currentZoom = max(min(zoom * pinch, maxZoom), minZoom)
                    let currentPan = CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
                    let magnify = MagnificationGesture()
                        .updating($pinch) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            zoom = clampZoom(zoom * value)
                        }
                    let panGesture = DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .updating($drag) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            pan.width += value.translation.width
                            pan.height += value.translation.height
                        }
                    let doubleTap = TapGesture(count: 2)
                        .onEnded { withAnimation(.easeInOut) { zoom = 1.0; pan = .zero } }

                    ZStack(alignment: .topTrailing) {
                        Canvas { context, size in
                            drawSky(context: &context, size: size, current: timeline.date, zoom: currentZoom, pan: currentPan)
                        }
                        .gesture(magnify)
                        .simultaneousGesture(panGesture)
                        .gesture(doubleTap)

                        // Small compass pinned top-right (non-interactive)
                        CompassView(heading: locationManager.heading, redMode: nightVisionMode, tint: nightVisionMode ? .red : .prussianBlueDark)
                            .frame(width: 44, height: 44)
                            .padding([.top, .trailing], 12)
                            .allowsHitTesting(false)

                        if skyShowLargeCompass {
                            let compDrag = DragGesture()
                                .updating($largeCompassDrag) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    largeCompassOffset.width += value.translation.width
                                    largeCompassOffset.height += value.translation.height
                                }
                            CompassView(heading: skySnapNorth ? 0 : locationManager.heading, redMode: nightVisionMode)
                                .frame(width: 120, height: 120)
                                .padding(12)
                                .background((nightVisionMode ? Color.red.opacity(0.08) : Color.black.opacity(0.25)).blur(radius: 0))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .offset(x: largeCompassOffset.width + largeCompassDrag.width, y: largeCompassOffset.height + largeCompassDrag.height)
                                .highPriorityGesture(compDrag)
                        }
                    }
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
                        .foregroundColor(nightVisionMode ? Color.red.opacity(0.7) : .prussianBlueLight)
                    Text(String(format: "%.4f, %.4f", locationManager.latitude, locationManager.longitude))
                        .font(.headline)
                        .foregroundColor(nightVisionMode ? Color.red : .prussianBlueDark)
                    // Moon info row
                    let sunEq = Astronomer.sunEquatorial(date: now)
                    let moonEq = Astronomer.moonEquatorial(date: now)
                    let k = Astronomer.illuminationFraction(sunEq: sunEq, moonEq: moonEq)
                    let age = Astronomer.moonAgeDays(date: now)
                    HStack(spacing: 8) {
                        MoonPhaseGlyph(k: k, redMode: nightVisionMode)
                            .frame(width: 14, height: 14)
                        Text(String(format: "Moon: %.1f d · %d%%", age, Int((k*100).rounded())))
                            .font(.caption2)
                            .foregroundColor(nightVisionMode ? Color.red.opacity(0.85) : .prussianBlueLight)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Time (UTC)")
                        .font(.caption)
                        .foregroundColor(nightVisionMode ? Color.red.opacity(0.7) : .prussianBlueLight)
                    Text(Self.utcFormatter.string(from: now))
                        .font(.headline)
                        .foregroundColor(nightVisionMode ? Color.red : .prussianBlueDark)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background((nightVisionMode ? Color.red.opacity(0.08) : Color.white.opacity(0.85)))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            // Only show legend on wider screens to avoid line breaks
            if horizontalSizeClass == .regular {
                LegendDot(color: nightVisionMode ? .red : .white, label: "Star")
                LegendLine(color: (nightVisionMode ? Color.red : Color.white).opacity(0.8), label: "Constellation")
                LegendDot(color: nightVisionMode ? .red : .yellow, label: "Sun")
                LegendDot(color: nightVisionMode ? .red : .gray.opacity(0.9), label: "Moon")
            }
            Spacer(minLength: 8)
            // Compact zoom controls (icon-only)
            HStack(spacing: 14) {
                Button { withAnimation(.easeInOut) { zoom = clampZoom(zoom / 1.15) } } label: {
                    Image(systemName: "minus.circle").foregroundColor(nightVisionMode ? .red : .white)
                }
                Button { withAnimation(.easeInOut) { zoom = clampZoom(zoom * 1.15) } } label: {
                    Image(systemName: "plus.circle").foregroundColor(nightVisionMode ? .red : .white)
                }
                Button { withAnimation(.easeInOut) { zoom = 1.0; pan = .zero } } label: {
                    Image(systemName: "arrow.counterclockwise.circle").foregroundColor(nightVisionMode ? .red : .white)
                }
            }
            Menu {
                Toggle("Night Vision", isOn: $nightVisionMode)
                Toggle("Star Labels", isOn: $skyShowStarLabels)
                Toggle("Constellation Labels", isOn: $skyShowConstellationLabels)
                Toggle("Large Compass", isOn: $skyShowLargeCompass)
                Toggle("Snap North", isOn: $skySnapNorth)
                Picker("Catalog", selection: $skyCatalog) {
                    Text("Bright").tag("bright")
                    Text("Extended").tag("extended")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(nightVisionMode ? .red : .white)
                    .font(.title3)
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(nightVisionMode ? Color.red.opacity(0.08) : Color.white.opacity(0.85))
    }

    // MARK: - Drawing

    private func drawSky(context: inout GraphicsContext, size: CGSize, current: Date, zoom: CGFloat, pan: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.48

        // Background dome circle
        let domeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let dome = Path(ellipseIn: domeRect)

        // Clip to dome then draw all content in a scaled layer around center
        context.clip(to: dome)
        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.scaleBy(x: zoom, y: zoom)
            layer.translateBy(x: -center.x, y: -center.y)

            // Night-sky gradient fill inside the dome
            let gradient = Gradient(stops: [
                .init(color: nightVisionMode ? Color(red: 0.12, green: 0.02, blue: 0.02) : Color(red: 0.02, green: 0.04, blue: 0.10), location: 0.0),
                .init(color: Color.black, location: 1.0)
            ])
            layer.fill(dome, with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))

            // Sun altitude drives day/night visibility
            let observer = Observer(lat: locationManager.latitude, lon: locationManager.longitude)
            let sunEq = Astronomer.sunEquatorial(date: current)
            let lstHoursForSun = Astronomer.localSiderealTime(date: current, longitude: observer.lon)
            let sunAltAz = Astronomer.altAz(eq: Equatorial(raHours: sunEq.raHours, decDeg: sunEq.decDeg), lstHours: lstHoursForSun, latDeg: observer.lat)
            let nightFactor = Self.visibilityFactor(sunAltitudeDeg: sunAltAz.altDeg)
            let effectiveNight = max(nightFactor, 0.35) // ensure visibility even in daytime

            // Procedural faint starfield (twinkling)
            drawBackgroundStars(context: &layer, center: center, radius: radius, nightFactor: effectiveNight, current: current)

            // Milky Way soft band along galactic plane
            drawMilkyWay(context: &layer, center: center, radius: radius, observer: observer, nightFactor: effectiveNight, current: current)

            // Sun and Moon markers
            drawSunAndMoon(context: &layer, center: center, radius: radius, observer: observer, current: current)

            // Altitude rings (30°, 60°)
            let fg = nightVisionMode ? Color.red : Color.white
            for alt in stride(from: 30.0, through: 60.0, by: 30.0) {
                let r = radius * (1 - alt / 90.0)
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                let path = Path(ellipseIn: rect)
                layer.stroke(path, with: .color(fg.opacity(0.15)), lineWidth: 0.8)
            }

            // Pan offsets mapped to azimuth/altitude
            let azOffsetRad = Double(pan.width) / Double(radius) * (Double.pi / 2.0) // ~90° per radius
            let altOffsetDeg = -Double(pan.height) / Double(radius) * 90.0

            // Cardinal directions (rotated by heading and panned)
            let labels = [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)]
            let headingRad = (skySnapNorth ? 0.0 : locationManager.heading) * .pi / 180.0
            for (text, az) in labels {
                let theta = az * .pi / 180
                let point = pointOnDome(center: center, radius: radius, azimuthRad: theta - headingRad + azOffsetRad, altitudeDeg: 0 + altOffsetDeg)
                var resolved = layer.resolve(Text(text).font(.caption).foregroundColor(fg))
                layer.draw(resolved, at: point, anchor: .center)
            }

            // Even if location isn't available, draw stars using default lat/lon

            // Compute star positions
            let lstHours = Astronomer.localSiderealTime(date: current, longitude: observer.lon)
            // Constellation lines first (so stars draw over them)
            for line in ConstellationData.lines {
                if let a = ConstellationData.star(named: line.0), let b = ConstellationData.star(named: line.1) {
                    if let pa = project(star: a, lstHours: lstHours, observer: observer, center: center, radius: radius, headingRad: headingRad, azOffsetRad: azOffsetRad, altOffsetDeg: altOffsetDeg),
                       let pb = project(star: b, lstHours: lstHours, observer: observer, center: center, radius: radius, headingRad: headingRad, azOffsetRad: azOffsetRad, altOffsetDeg: altOffsetDeg) {
                        var path = Path()
                        path.move(to: pa)
                        path.addLine(to: pb)
                        layer.stroke(path, with: .color(fg.opacity(0.5 * effectiveNight)), lineWidth: 0.7)
                    }
                }
            }

            // Draw stars
            let starsToUse: [Star] = skyCatalog == "extended" ? ConstellationData.starsExtended : ConstellationData.stars
            for star in starsToUse {
                if let p = project(star: star, lstHours: lstHours, observer: observer, center: center, radius: radius, headingRad: headingRad, azOffsetRad: azOffsetRad, altOffsetDeg: altOffsetDeg) {
                    let size = max(1.5, 5.2 - 0.8 * star.mag)
                    let rect = CGRect(x: p.x - size/2, y: p.y - size/2, width: size, height: size)
                    layer.fill(Path(ellipseIn: rect), with: .color(fg.opacity(effectiveNight)))

                    if skyShowStarLabels && star.mag < 1.0 { // label brighter stars
                        let label = Text(star.name).font(.system(size: 8)).foregroundColor(fg.opacity(effectiveNight))
                        layer.draw(layer.resolve(label), at: CGPoint(x: p.x + 8, y: p.y - 8), anchor: .topLeading)
                    }
                }
            }

            if skyShowConstellationLabels {
                drawConstellationLabels(context: &layer, center: center, radius: radius, lstHours: lstHours, observer: observer, headingRad: headingRad, azOffsetRad: azOffsetRad, altOffsetDeg: altOffsetDeg, fg: fg.opacity(effectiveNight))
            }
        }

        // Outline after fill so it stays crisp
        let fg = nightVisionMode ? Color.red : Color.white
        context.stroke(dome, with: .color(fg.opacity(0.25)), lineWidth: 1)

    }

    private func drawBackgroundStars(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, nightFactor: Double, current: Date) {
        // Number scales with area; cap for performance
        let n = min(1000, max(250, Int((radius * radius) / 6)))
        let t = current.timeIntervalSince1970
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
            let alpha = base * twinkle * nightFactor
            let s = 0.4 + 1.2 * prand(Double(i) * 5.11 + 0.09) // 0.4 - 1.6 px

            let rect = CGRect(x: x - s/2, y: y - s/2, width: s, height: s)
            let starColor = nightVisionMode ? Color.red : Color.white
            context.fill(Path(ellipseIn: rect), with: .color(starColor.opacity(alpha)))
        }
    }

    private func prand(_ n: Double) -> Double {
        let s = sin(n) * 43758.5453
        return s - floor(s)
    }

    private func clampZoom(_ z: CGFloat) -> CGFloat { max(minZoom, min(maxZoom, z)) }

    // MARK: - Milky Way rendering
    private func drawMilkyWay(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, observer: Observer, nightFactor: Double, current: Date) {
        guard nightFactor > 0.02 else { return }
        let lstHours = Astronomer.localSiderealTime(date: current, longitude: observer.lon)

        // Draw multiple belts at galactic latitude offsets to create a soft band
        let latitudes = [-10.0, -6.0, -3.0, 0.0, 3.0, 6.0, 10.0]
        let alphas: [Double] = [0.02, 0.035, 0.05, 0.07, 0.05, 0.035, 0.02]
        for (idx, b) in latitudes.enumerated() {
            var path = Path()
            var started = false
            let alpha = alphas[min(idx, alphas.count-1)] * nightFactor
            for l in stride(from: 0.0, through: 360.0, by: 3.0) {
                let eq = Astronomer.galacticToEquatorial(lDeg: l, bDeg: b)
                let altaz = Astronomer.altAz(eq: Equatorial(raHours: eq.raHours, decDeg: eq.decDeg), lstHours: lstHours, latDeg: observer.lat)
                if altaz.altDeg > 0 {
                    let az = altaz.azDeg * .pi / 180.0
                    let p = pointOnDome(center: center, radius: radius, azimuthRad: az, altitudeDeg: altaz.altDeg)
                    if !started {
                        path.move(to: p)
                        started = true
                    } else {
                        path.addLine(to: p)
                    }
                } else {
                    started = false
                }
            }
            let color = nightVisionMode ? Color.red : Color.white
            context.stroke(path, with: .color(color.opacity(alpha)), lineWidth: 3)
        }
    }

    private func drawConstellationLabels(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, lstHours: Double, observer: Observer, headingRad: Double, azOffsetRad: Double, altOffsetDeg: Double, fg: Color) {
        // Define label groups
        let orion = ["Betelgeuse","Bellatrix","Rigel","Saiph","Alnilam","Alnitak","Mintaka"]
        let dipper = ["Dubhe","Merak","Phecda","Megrez","Alioth","Mizar","Alkaid"]
        func centroid(for names: [String]) -> CGPoint? {
            var pts: [CGPoint] = []
            for n in names {
                if let s = ConstellationData.star(named: n) {
                    if let p = project(star: s, lstHours: lstHours, observer: observer, center: center, radius: radius, headingRad: headingRad, azOffsetRad: azOffsetRad, altOffsetDeg: altOffsetDeg) {
                        pts.append(p)
                    }
                }
            }
            guard !pts.isEmpty else { return nil }
            let sx = pts.reduce(0) { $0 + $1.x }
            let sy = pts.reduce(0) { $0 + $1.y }
            return CGPoint(x: sx / CGFloat(pts.count), y: sy / CGFloat(pts.count))
        }
        if let c = centroid(for: orion) {
            let label = Text("Orion").font(.system(size: 10, weight: .semibold)).foregroundColor(fg)
            context.draw(context.resolve(label), at: c, anchor: .center)
        }
        if let c = centroid(for: dipper) {
            let label = Text("Ursa Major").font(.system(size: 10, weight: .semibold)).foregroundColor(fg)
            context.draw(context.resolve(label), at: c, anchor: .center)
        }
    }

    private func drawSunAndMoon(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, observer: Observer, current: Date) {
        let lstHours = Astronomer.localSiderealTime(date: current, longitude: observer.lon)
        // Sun
        let sunEq = Astronomer.sunEquatorial(date: current)
        let sunAltAz = Astronomer.altAz(eq: Equatorial(raHours: sunEq.raHours, decDeg: sunEq.decDeg), lstHours: lstHours, latDeg: observer.lat)
        if true {
            let az = sunAltAz.azDeg * .pi / 180.0
            let headingRad = (skySnapNorth ? 0.0 : locationManager.heading) * .pi / 180.0
            let azOffsetRad = Double(pan.width) / Double(radius) * (Double.pi / 2.0)
            let altOffsetDeg = -Double(pan.height) / Double(radius) * 90.0
            let adjAlt = max(-90.0, min(90.0, sunAltAz.altDeg + altOffsetDeg))
            let p = pointOnDome(center: center, radius: radius, azimuthRad: az - headingRad + azOffsetRad, altitudeDeg: adjAlt)
            let s: CGFloat = 8
            let rect = CGRect(x: p.x - s/2, y: p.y - s/2, width: s, height: s)
            let color = nightVisionMode ? Color.red : Color.yellow
            context.fill(Path(ellipseIn: rect), with: .color(color))
            let label = Text("Sun").font(.system(size: 8)).foregroundColor(color)
            context.draw(context.resolve(label), at: CGPoint(x: p.x + 8, y: p.y - 8), anchor: .topLeading)
        }

        // Moon
        let moonEq = Astronomer.moonEquatorial(date: current)
        let moonAltAz = Astronomer.altAz(eq: Equatorial(raHours: moonEq.raHours, decDeg: moonEq.decDeg), lstHours: lstHours, latDeg: observer.lat)
        if true {
            let azMoon = moonAltAz.azDeg * .pi / 180.0
            let headingRad = (skySnapNorth ? 0.0 : locationManager.heading) * .pi / 180.0
            let azOffsetRad = Double(pan.width) / Double(radius) * (Double.pi / 2.0)
            let altOffsetDeg = -Double(pan.height) / Double(radius) * 90.0
            let adjAlt = max(-90.0, min(90.0, moonAltAz.altDeg + altOffsetDeg))
            let p = pointOnDome(center: center, radius: radius, azimuthRad: azMoon - headingRad + azOffsetRad, altitudeDeg: adjAlt)

            // Phase and orientation
            let k = Astronomer.illuminationFraction(sunEq: sunEq, moonEq: moonEq)
            let azSun = sunAltAz.azDeg * .pi / 180.0
            // Canvas vector for azimuth a is (sin a, -cos a)
            let vx = sin(azSun)
            let vy = -cos(azSun)
            let theta = atan2(vy, vx)

            // Draw moon with crescent/gibbous shading
            let color = nightVisionMode ? Color.red : Color.white
            let s: CGFloat = 10
            let r = s / 2
            let baseRect = CGRect(x: -r, y: -r, width: s, height: s)

            context.drawLayer { layer in
                layer.translateBy(x: p.x, y: p.y)
                layer.rotate(by: Angle(radians: theta))

                // Base: dark outline to enhance legibility
                layer.stroke(Path(ellipseIn: baseRect), with: .color(color), lineWidth: 1)

                if k >= 0.5 {
                    // Bright gibbous/full: intersection of two discs
                    let d = 2 * r * (1 - k)
                    let shifted = baseRect.offsetBy(dx: d, dy: 0)
                    layer.clip(to: Path(ellipseIn: baseRect))
                    layer.clip(to: Path(ellipseIn: shifted)) // intersection
                    layer.fill(Path(ellipseIn: baseRect), with: .color(color))
                } else {
                    // Bright crescent: base minus shifted disc (within base)
                    let d = 2 * r * k
                    let shifted = baseRect.offsetBy(dx: d, dy: 0)
                    layer.clip(to: Path(ellipseIn: baseRect))
                    var crescent = Path()
                    crescent.addEllipse(in: baseRect)
                    crescent.addEllipse(in: shifted)
                    layer.fill(crescent, with: .color(color), style: FillStyle(eoFill: true))
                }
            }

            // Label with illumination percent
            let percent = Int((k * 100).rounded())
            let label = Text("Moon \(percent)%").font(.system(size: 8)).foregroundColor(color)
            context.draw(context.resolve(label), at: CGPoint(x: p.x + 8, y: p.y - 8), anchor: .topLeading)
        }
    }

    // Day-night transition factor based on Sun altitude (deg)
    private static func visibilityFactor(sunAltitudeDeg: Double) -> Double {
        // 0 at 0° (day), 1 at -18° (astronomical night)
        let t = min(max((-sunAltitudeDeg) / 18.0, 0.0), 1.0)
        // Smoothstep for gentle transition
        return t * t * (3 - 2 * t)
    }

    private func project(star: Star, lstHours: Double, observer: Observer, center: CGPoint, radius: CGFloat, headingRad: Double, azOffsetRad: Double, altOffsetDeg: Double) -> CGPoint? {
        let eq = Equatorial(raHours: star.raHours, decDeg: star.decDeg)
        let altaz = Astronomer.altAz(eq: eq, lstHours: lstHours, latDeg: observer.lat)
        let adjAlt = max(-90.0, min(90.0, altaz.altDeg + altOffsetDeg))
        let azRad = altaz.azDeg * .pi / 180
        let pt = pointOnDome(center: center, radius: radius, azimuthRad: azRad - headingRad + azOffsetRad, altitudeDeg: adjAlt)
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
            let r11 = -0.0548755604, r12 = 0.4941094279,  r13 = -0.8676661490
            let r21 = -0.8734370902, r22 = -0.4448296300, r23 = -0.1980763734
            let r31 = -0.4838350155, r32 = 0.7469822445,  r33 = 0.4559837762

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
            let D  = (297.8501921 + 12.19074912 * d).truncatingRemainder(dividingBy: 360) // elongation Sun-Moon
            let M  = (357.5291092 + 0.98560028  * d).truncatingRemainder(dividingBy: 360) // Sun anomaly
            let Mp = (134.9633964 + 13.06499295 * d).truncatingRemainder(dividingBy: 360) // Moon anomaly
            let F  = (93.2720950  + 13.22935024 * d).truncatingRemainder(dividingBy: 360) // Moon lat argument

            // Ecliptic longitude (deg), major terms
            var lon = Lp
            lon += 6.289 * sin(Mp * rad)
            lon += 1.274 * sin((2*D - Mp) * rad)
            lon += 0.658 * sin(2*D * rad)
            lon += 0.214 * sin((2*Mp) * rad)
            lon += 0.110 * sin(D * rad)
            lon -= 0.186 * sin(M * rad) // solar equation of center

            // Ecliptic latitude (deg), major terms
            var lat = 5.128 * sin(F * rad)
            lat += 0.280 * sin((Mp + F) * rad)
            lat += 0.277 * sin((Mp - F) * rad)
            lat += 0.173 * sin((2*D - F) * rad)

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
            let D  = (297.8501921 + 12.19074912 * d).truncatingRemainder(dividingBy: 360)
            let M  = (357.5291092 + 0.98560028  * d).truncatingRemainder(dividingBy: 360)
            let Mp = (134.9633964 + 13.06499295 * d).truncatingRemainder(dividingBy: 360)
            var lon = Lp
            lon += 6.289 * sin(Mp * rad)
            lon += 1.274 * sin((2*D - Mp) * rad)
            lon += 0.658 * sin(2*D * rad)
            lon += 0.214 * sin((2*Mp) * rad)
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

        static let moreStars: [Star] = [
            Star(name: "Sadr", raHours: 20.3705, decDeg: 40.2567, mag: 2.23),
            Star(name: "Kochab", raHours: 14.8451, decDeg: 74.1555, mag: 2.08),
            Star(name: "Schedar", raHours: 0.6751, decDeg: 56.5373, mag: 2.24),
            Star(name: "Caph", raHours: 0.1529, decDeg: 59.1498, mag: 2.27),
            Star(name: "Alpheratz", raHours: 0.1398, decDeg: 29.0904, mag: 2.06),
            Star(name: "Mirfak", raHours: 3.4054, decDeg: 49.8612, mag: 1.79),
            Star(name: "Algol", raHours: 3.1361, decDeg: 40.9556, mag: 2.1),
            Star(name: "Denebola", raHours: 11.8177, decDeg: 14.5719, mag: 2.14),
            Star(name: "Markab", raHours: 23.0794, decDeg: 15.2053, mag: 2.49),
            Star(name: "Enif", raHours: 21.7364, decDeg: 9.875, mag: 2.38),
            Star(name: "Rasalhague", raHours: 17.5822, decDeg: 12.5606, mag: 2.08),
            Star(name: "Atria", raHours: 16.8111, decDeg: -69.0278, mag: 1.91),
            Star(name: "Peacock", raHours: 20.4275, decDeg: -56.735, mag: 1.94),
            Star(name: "Alhena", raHours: 6.6285, decDeg: 16.3993, mag: 1.93),
            Star(name: "Bellatrix", raHours: 5.4189, decDeg: 6.3497, mag: 1.64)
        ]

        static let starsExtended: [Star] = stars + moreStars

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

// CompassView moved to Views/Components/CompassView.swift for reuse

#if canImport(SwiftUI)
private struct MoonPhaseGlyph: View {
    let k: Double // illuminated fraction [0,1]
    let redMode: Bool
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let r = s / 2
            let rect = CGRect(x: (size.width - s)/2, y: (size.height - s)/2, width: s, height: s)
            let color = redMode ? Color.red : Color.white
            // Outline
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: max(0.8, s * 0.08))
            context.clip(to: Path(ellipseIn: rect))
            if k >= 0.5 {
                let d = 2 * r * (1 - k)
                let shifted = rect.offsetBy(dx: d, dy: 0)
                context.clip(to: Path(ellipseIn: shifted))
                context.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                let d = 2 * r * k
                let shifted = rect.offsetBy(dx: d, dy: 0)
                var crescent = Path()
                crescent.addEllipse(in: rect)
                crescent.addEllipse(in: shifted)
                context.fill(crescent, with: .color(color), style: FillStyle(eoFill: true))
            }
        }
    }
}
#endif

#Preview {
    ConstellationMapView(locationManager: LocationManager())
}
