import SwiftUI
import CoreLocation
import simd

struct ConstellationMapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var satelliteManager: SatelliteManager
    @AppStorage("skyShowSatellites") private var skyShowSatellites = true
    @AppStorage("skyShowPlanets") private var skyShowPlanets = true
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
            GeometryReader { _ in
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
                            drawSky(
                                context: &context,
                                size: size,
                                current: timeline.date,
                                zoom: currentZoom,
                                pan: currentPan
                            )
                        }
                        .gesture(magnify)
                        .simultaneousGesture(panGesture)
                        .gesture(doubleTap)

                        // Small compass pinned top-right (non-interactive)
                        CompassView(
                            heading: locationManager.heading,
                            redMode: nightVisionMode,
                            tint: nightVisionMode ? .red : .prussianBlueDark
                        )
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
                                .background(
                                    (nightVisionMode ? Color.red.opacity(0.08) : Color.black.opacity(0.25))
                                        .blur(radius: 0)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .offset(
                                    x: largeCompassOffset.width + largeCompassDrag.width,
                                    y: largeCompassOffset.height + largeCompassDrag.height
                                )
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
                    // Next planet rise/set event
                    if skyShowPlanets,
                       locationManager.hasValidLocation,
                       let event = Astronomer.nextPlanetEvent(
                           planets: Planet.catalog,
                           date: now,
                           latDeg: locationManager.latitude,
                           lonDeg: locationManager.longitude
                       ) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(nightVisionMode ? Color.red : event.planet.skyColor)
                                .frame(width: 6, height: 6)
                            Text(event.label)
                                .font(.caption2)
                                .foregroundColor(nightVisionMode ? Color.red.opacity(0.85) : .prussianBlueLight)
                        }
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
                if skyShowSatellites {
                    LegendDot(color: nightVisionMode ? .red : .cyan, label: "Satellite")
                }
                if skyShowPlanets {
                    LegendDot(color: nightVisionMode ? .red : .prussianBlue, label: "Planet")
                }
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
                Toggle("Satellites", isOn: $skyShowSatellites)
                Toggle("Planets", isOn: $skyShowPlanets)
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

            // Planets
            if skyShowPlanets {
                PlanetRenderer.draw(
                    context: &layer,
                    planets: Planet.catalog,
                    config: PlanetRenderer.DrawConfig(
                        center: center,
                        radius: radius,
                        heading: locationManager.heading,
                        snapNorth: skySnapNorth,
                        panOffset: pan,
                        current: current,
                        observer: observer,
                        nightVisionMode: nightVisionMode,
                        pointOnDome: pointOnDome
                    )
                )
            }

            // Satellites
            if skyShowSatellites {
                SatelliteRenderer.draw(
                    context: &layer, satellites: satelliteManager.satellites, center: center,
                    radius: radius, heading: locationManager.heading, snapNorth: skySnapNorth,
                    panOffset: pan, current: current, nightVisionMode: nightVisionMode,
                    pointOnDome: pointOnDome)
            }

            let fg = nightVisionMode ? Color.red : Color.white
            let headingRad = (skySnapNorth ? 0.0 : locationManager.heading) * .pi / 180.0
            let azOffsetRad = Double(pan.width) / Double(radius) * (Double.pi / 2.0) // ~90° per radius
            let altOffsetDeg = -Double(pan.height) / Double(radius) * 90.0

            drawRingsAndCardinals(
                context: &layer,
                center: center,
                radius: radius,
                fg: fg,
                headingRad: headingRad,
                azOffsetRad: azOffsetRad,
                altOffsetDeg: altOffsetDeg
            )

            drawStarsAndConstellations(
                context: &layer,
                center: center,
                radius: radius,
                observer: observer,
                current: current,
                headingRad: headingRad,
                azOffsetRad: azOffsetRad,
                altOffsetDeg: altOffsetDeg,
                effectiveNight: effectiveNight,
                fg: fg
            )
        }

        // Outline after fill so it stays crisp
        let fg = nightVisionMode ? Color.red : Color.white
        context.stroke(dome, with: .color(fg.opacity(0.25)), lineWidth: 1)

    }

    private func drawRingsAndCardinals(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        fg: Color,
        headingRad: Double,
        azOffsetRad: Double,
        altOffsetDeg: Double
    ) {
        // Altitude rings (30°, 60°)
        for alt in stride(from: 30.0, through: 60.0, by: 30.0) {
            let r = radius * (1 - alt / 90.0)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let path = Path(ellipseIn: rect)
            context.stroke(path, with: .color(fg.opacity(0.15)), lineWidth: 0.8)
        }

        // Cardinal directions (rotated by heading and panned)
        let labels = [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)]
        for (text, az) in labels {
            let theta = az * .pi / 180
            let point = pointOnDome(
                center: center,
                radius: radius,
                azimuthRad: theta - headingRad + azOffsetRad,
                altitudeDeg: altOffsetDeg
            )
            let resolved = context.resolve(Text(text).font(.caption).foregroundColor(fg))
            context.draw(resolved, at: point, anchor: .center)
        }
    }

    private func drawStarsAndConstellations(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        observer: Observer,
        current: Date,
        headingRad: Double,
        azOffsetRad: Double,
        altOffsetDeg: Double,
        effectiveNight: Double,
        fg: Color
    ) {
        // Even if location isn't available, draw stars using default lat/lon
        let lstHours = Astronomer.localSiderealTime(date: current, longitude: observer.lon)

        // Constellation lines first (so stars draw over them)
        for line in ConstellationData.lines {
            guard let a = ConstellationData.star(named: line.0),
                  let b = ConstellationData.star(named: line.1),
                  let pa = project(
                    star: a,
                    lstHours: lstHours,
                    observer: observer,
                    center: center,
                    radius: radius,
                    headingRad: headingRad,
                    azOffsetRad: azOffsetRad,
                    altOffsetDeg: altOffsetDeg
                  ),
                  let pb = project(
                    star: b,
                    lstHours: lstHours,
                    observer: observer,
                    center: center,
                    radius: radius,
                    headingRad: headingRad,
                    azOffsetRad: azOffsetRad,
                    altOffsetDeg: altOffsetDeg
                  )
            else {
                continue
            }

            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            context.stroke(path, with: .color(fg.opacity(0.5 * effectiveNight)), lineWidth: 0.7)
        }

        let starsToUse: [Star] = skyCatalog == "extended" ? ConstellationData.starsExtended : ConstellationData.stars
        for star in starsToUse {
            guard let p = project(
                star: star,
                lstHours: lstHours,
                observer: observer,
                center: center,
                radius: radius,
                headingRad: headingRad,
                azOffsetRad: azOffsetRad,
                altOffsetDeg: altOffsetDeg
            ) else {
                continue
            }

            let size = max(1.5, 5.2 - 0.8 * star.mag)
            let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            context.fill(Path(ellipseIn: rect), with: .color(fg.opacity(effectiveNight)))

            if skyShowStarLabels && star.mag < 1.0 { // label brighter stars
                let label = Text(star.name).font(.system(size: 8)).foregroundColor(fg.opacity(effectiveNight))
                context.draw(context.resolve(label), at: CGPoint(x: p.x + 8, y: p.y - 8), anchor: .topLeading)
            }
        }

        if skyShowConstellationLabels {
            drawConstellationLabels(
                context: &context,
                center: center,
                radius: radius,
                lstHours: lstHours,
                observer: observer,
                headingRad: headingRad,
                azOffsetRad: azOffsetRad,
                altOffsetDeg: altOffsetDeg,
                fg: fg.opacity(effectiveNight)
            )
        }
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
        let orion = ["Betelgeuse", "Bellatrix", "Rigel", "Saiph", "Alnilam", "Alnitak", "Mintaka"]
        let dipper = ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"]
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
    let locationManager = LocationManager()
    return ConstellationMapView(
        locationManager: locationManager,
        satelliteManager: SatelliteManager(locationManager: locationManager)
    )
}
