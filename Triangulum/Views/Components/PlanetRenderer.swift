//
//  PlanetRenderer.swift
//  Triangulum
//
//  Helper for rendering solar system planet positions on the constellation map.
//  Mirrors SatelliteRenderer pattern: caseless enum with a single static draw function.
//

import SwiftUI

// MARK: - Planet Model

/// A solar system planet with rendering metadata
struct Planet {
    let name: String
    let abbreviation: String
    let skyColor: Color
    let nominalMag: Double  // typical visual magnitude for size computation
    let isInner: Bool       // true for Mercury and Venus (phase rendering applies)

    static let catalog: [Planet] = [
        Planet(name: "Mercury", abbreviation: "Mer",
               skyColor: Color(red: 0.75, green: 0.72, blue: 0.68), nominalMag: 0.0, isInner: true),
        Planet(name: "Venus", abbreviation: "Ven",
               skyColor: Color(red: 0.98, green: 0.97, blue: 0.85), nominalMag: -4.0, isInner: true),
        Planet(name: "Mars", abbreviation: "Mar",
               skyColor: Color(red: 0.90, green: 0.35, blue: 0.20), nominalMag: 0.5, isInner: false),
        Planet(name: "Jupiter", abbreviation: "Jup",
               skyColor: Color(red: 0.92, green: 0.84, blue: 0.72), nominalMag: -2.0, isInner: false),
        Planet(name: "Saturn", abbreviation: "Sat",
               skyColor: Color(red: 0.88, green: 0.82, blue: 0.65), nominalMag: 0.7, isInner: false)
    ]
}

// MARK: - Planet Renderer

/// Renders solar system planet positions on the sky dome canvas.
enum PlanetRenderer {

    struct DrawConfig {
        let center: CGPoint
        let radius: CGFloat
        let heading: Double
        let snapNorth: Bool
        let panOffset: CGSize
        let current: Date
        let observer: ConstellationMapView.Observer
        let nightVisionMode: Bool
        let pointOnDome: (CGPoint, CGFloat, Double, Double) -> CGPoint
    }

    static func draw(
        context: inout GraphicsContext,
        planets: [Planet],
        config: DrawConfig
    ) {
        let headingRad = (config.snapNorth ? 0.0 : config.heading) * .pi / 180.0
        let azOffsetRad = Double(config.panOffset.width) / Double(config.radius) * (Double.pi / 2.0)
        let altOffsetDeg = -Double(config.panOffset.height) / Double(config.radius) * 90.0
        let lstHours = ConstellationMapView.Astronomer.localSiderealTime(date: config.current, longitude: config.observer.lon)
        let sunLon = ConstellationMapView.Astronomer.sunEclipticLongitude(date: config.current)

        for planet in planets {
            let eq = ConstellationMapView.Astronomer.planetEquatorial(planet: planet, date: config.current)
            let altaz = ConstellationMapView.Astronomer.altAz(
                eq: ConstellationMapView.Equatorial(raHours: eq.raHours, decDeg: eq.decDeg),
                lstHours: lstHours,
                latDeg: config.observer.lat
            )

            let adjAlt = altaz.altDeg + altOffsetDeg
            guard adjAlt > -5 else { continue }

            let azRad = altaz.azDeg * .pi / 180.0
            let point = config.pointOnDome(config.center, config.radius, azRad - headingRad + azOffsetRad, max(0, adjAlt))

            // Magnitude-based sizing: range 7pt (dim) to 12pt (bright, e.g. Venus)
            let sizePt = CGFloat(max(7.0, min(12.0, 8.0 - 1.0 * planet.nominalMag)))
            let r = sizePt / 2

            let isVisible = adjAlt > 0
            let baseColor: Color = config.nightVisionMode ? .red : planet.skyColor
            let color = isVisible ? baseColor : baseColor.opacity(0.35)

            if planet.isInner {
                drawInnerPlanetPhase(
                    context: &context, at: point, r: r,
                    sunLon: sunLon, planet: planet, current: config.current, color: color
                )
            } else {
                let rect = CGRect(x: point.x - r, y: point.y - r, width: sizePt, height: sizePt)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.6)), lineWidth: 0.8)
            }

            // Name label offset top-right, mirrors SatelliteRenderer label placement
            let labelColor = isVisible ? baseColor : baseColor.opacity(0.5)
            let labelText = Text(planet.abbreviation)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(labelColor)
            context.draw(
                context.resolve(labelText),
                at: CGPoint(x: point.x + r + 3, y: point.y - r - 3),
                anchor: .topLeading
            )
        }
    }

    // MARK: - Inner Planet Phase (Mercury / Venus)

    private static func drawInnerPlanetPhase(
        context: inout GraphicsContext,
        at point: CGPoint,
        r: CGFloat,
        sunLon: Double,
        planet: Planet,
        current: Date,
        color: Color
    ) {
        let planetLon = ConstellationMapView.Astronomer.planetEclipticLongitude(planet: planet, date: current)
        let k = ConstellationMapView.Astronomer.innerPlanetIllumination(planetLon: planetLon, sunLon: sunLon)
        let tiltRad = (sunLon - planetLon) * .pi / 180.0
        let baseRect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)

        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: Angle(radians: tiltRad))

            layer.stroke(Path(ellipseIn: baseRect), with: .color(color), lineWidth: 1)

            if k >= 0.5 {
                // Gibbous/full: intersection of two overlapping discs
                let d = 2 * r * CGFloat(1.0 - k)
                let shifted = baseRect.offsetBy(dx: d, dy: 0)
                layer.clip(to: Path(ellipseIn: baseRect))
                layer.clip(to: Path(ellipseIn: shifted))
                layer.fill(Path(ellipseIn: baseRect), with: .color(color))
            } else {
                // Crescent: even-odd fill (base disc minus inner shifted disc)
                let d = 2 * r * CGFloat(k)
                let shifted = baseRect.offsetBy(dx: d, dy: 0)
                layer.clip(to: Path(ellipseIn: baseRect))
                var crescent = Path()
                crescent.addEllipse(in: baseRect)
                crescent.addEllipse(in: shifted)
                layer.fill(crescent, with: .color(color), style: FillStyle(eoFill: true))
            }
        }
    }
}
