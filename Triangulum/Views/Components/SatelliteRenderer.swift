//
//  SatelliteRenderer.swift
//  Triangulum
//
//  Helper for rendering satellites on the constellation map
//

import SwiftUI

/// Renders satellite positions on the sky dome canvas
enum SatelliteRenderer {

    /// Draw all tracked satellites on the constellation map
    static func draw(
        context: inout GraphicsContext,
        satellites: [Satellite],
        center: CGPoint,
        radius: CGFloat,
        heading: Double,
        snapNorth: Bool,
        panOffset: CGSize,
        current: Date,
        nightVisionMode: Bool,
        pointOnDome: (CGPoint, CGFloat, Double, Double) -> CGPoint
    ) {
        let headingRad = (snapNorth ? 0.0 : heading) * .pi / 180.0
        let azOffsetRad = Double(panOffset.width) / Double(radius) * (Double.pi / 2.0)
        let altOffsetDeg = -Double(panOffset.height) / Double(radius) * 90.0

        for satellite in satellites {
            guard let position = satellite.currentPosition,
                  let azimuth = position.azimuthDeg,
                  let altitude = position.altitudeDeg else { continue }

            let adjAlt = altitude + altOffsetDeg
            guard adjAlt > -5 else { continue }

            let azRad = azimuth * .pi / 180.0
            let point = pointOnDome(center, radius, azRad - headingRad + azOffsetRad, max(0, adjAlt))

            // Satellite marker with pulsing effect
            let baseSize: CGFloat = 6.0
            let pulsePhase = current.timeIntervalSince1970.truncatingRemainder(dividingBy: 2.0) / 2.0
            let size = baseSize * CGFloat(1.0 + 0.2 * sin(pulsePhase * 2.0 * .pi))

            let isVisible = adjAlt > 0
            let baseColor: Color = satellite.id == "ISS"
                ? (nightVisionMode ? .red : .yellow)
                : (nightVisionMode ? .red : .cyan)
            let color = isVisible ? baseColor : baseColor.opacity(0.4)

            let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
            context.fill(Path(ellipseIn: rect), with: .color(color))

            let labelColor = isVisible ? baseColor : baseColor.opacity(0.6)
            let labelText = Text(satellite.id).font(.system(size: 9, weight: .bold)).foregroundColor(labelColor)
            context.draw(context.resolve(labelText), at: CGPoint(x: point.x + 8, y: point.y - 8), anchor: .topLeading)
        }
    }
}
