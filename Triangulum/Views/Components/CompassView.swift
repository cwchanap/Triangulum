import SwiftUI

public struct CompassView: View {
    public let heading: Double // degrees 0..360, 0=N
    public var redMode: Bool = false
    public var tint: Color? // overrides default ink in non-red mode

    public init(heading: Double, redMode: Bool = false, tint: Color? = nil) {
        self.heading = heading
        self.redMode = redMode
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let radius = min(size.width, size.height) * 0.48
            let ink = redMode ? Color.red : (tint ?? Color.celText)
            let accent = redMode ? Color.red : Color.celCyan
            let star = redMode ? Color.red : Color.celGold
            let ringColor = ink.opacity(0.6)

            // Outer ring + faint inner ring
            let ring = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.stroke(ring, with: .color(accent.opacity(0.55)), lineWidth: 1.5)
            let innerRing = Path(ellipseIn: CGRect(
                x: center.x - radius * 0.78, y: center.y - radius * 0.78,
                width: radius * 1.56, height: radius * 1.56
            ))
            context.stroke(innerRing, with: .color(ringColor.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 0.5, dash: [1, 5]))

            // Degree ticks: minor every 15°, major every 45°
            for deg in stride(from: 0.0, through: 345.0, by: 15.0) {
                let isMajor = deg.truncatingRemainder(dividingBy: 45) == 0
                let angle = deg * .pi / 180
                let inset: CGFloat = isMajor ? 9 : 4
                let point1 = CGPoint(x: center.x + cos(angle) * (radius - 2), y: center.y + sin(angle) * (radius - 2))
                let point2 = CGPoint(x: center.x + cos(angle) * (radius - inset), y: center.y + sin(angle) * (radius - inset))
                var tick = Path()
                tick.move(to: point1)
                tick.addLine(to: point2)
                context.stroke(tick, with: .color(isMajor ? accent.opacity(0.8) : ringColor),
                               lineWidth: isMajor ? 1.5 : 0.75)
            }

            // Cardinal labels fixed to view; needle rotates instead
            let labels: [(String, Double)] = [("N", -90), ("E", 0), ("S", 90), ("W", 180)]
            for (txt, deg) in labels {
                let angle = deg * .pi / 180
                let point = CGPoint(x: center.x + cos(angle) * (radius - 18), y: center.y + sin(angle) * (radius - 18))
                let isN = txt == "N"
                let text = Text(txt)
                    .font(.system(size: isN ? 13 : 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isN ? star : ink.opacity(0.85))
                context.draw(context.resolve(text), at: point, anchor: .center)
            }

            // Needle: north half bright/glowing, south half dim
            let base: CGFloat = radius * 0.18
            let tipLen: CGFloat = radius * 0.74
            var north = Path()
            north.move(to: CGPoint(x: center.x, y: center.y - tipLen))
            north.addLine(to: CGPoint(x: center.x - base/2, y: center.y))
            north.addLine(to: CGPoint(x: center.x + base/2, y: center.y))
            north.closeSubpath()
            var south = Path()
            south.move(to: CGPoint(x: center.x, y: center.y + tipLen * 0.82))
            south.addLine(to: CGPoint(x: center.x - base/2, y: center.y))
            south.addLine(to: CGPoint(x: center.x + base/2, y: center.y))
            south.closeSubpath()

            context.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: Angle(degrees: -heading))
                layer.translateBy(x: -center.x, y: -center.y)
                layer.addFilter(.shadow(color: accent.opacity(0.7), radius: 8))
                layer.fill(south, with: .color(ink.opacity(0.35)))
                layer.fill(north, with: .color(accent))
                // Gold star at the north tip
                let tip = CGPoint(x: center.x, y: center.y - tipLen)
                let r: CGFloat = 3
                layer.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r*2, height: r*2)),
                           with: .color(star))
            }

            // Center hub
            let hubR: CGFloat = 5
            context.fill(Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR,
                                                width: hubR*2, height: hubR*2)),
                         with: .color(accent))
            context.stroke(Path(ellipseIn: CGRect(x: center.x - hubR - 2, y: center.y - hubR - 2,
                                                  width: hubR*2 + 4, height: hubR*2 + 4)),
                           with: .color(accent.opacity(0.4)), lineWidth: 1)
        }
        .padding(2)
    }
}
