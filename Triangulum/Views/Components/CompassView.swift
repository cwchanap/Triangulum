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
            let ink = redMode ? Color.red : (tint ?? Color.white)
            let ringColor = ink.opacity(0.7)

            // Outer ring
            let ring = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(ring, with: .color(ringColor), lineWidth: 1)

            // Tick marks (every 45°)
            for deg in stride(from: 0.0, through: 315.0, by: 45.0) {
                let angle = deg * .pi / 180
                let point1 = CGPoint(x: center.x + cos(angle) * (radius - 2), y: center.y + sin(angle) * (radius - 2))
                let point2 = CGPoint(x: center.x + cos(angle) * (radius - 6), y: center.y + sin(angle) * (radius - 6))
                var tick = Path()
                tick.move(to: point1)
                tick.addLine(to: point2)
                context.stroke(tick, with: .color(ringColor), lineWidth: 1)
            }

            // Cardinal labels fixed to view; needle rotates instead
            let labelColor = ink
            // Place 'N' at top by using -90° for N, then clockwise
            let labels: [(String, Double)] = [("N", -90), ("E", 0), ("S", 90), ("W", 180)]
            for (txt, deg) in labels {
                let angle = deg * .pi / 180
                let point = CGPoint(x: center.x + cos(angle) * (radius - 10), y: center.y + sin(angle) * (radius - 10))
                let text = Text(txt).font(.system(size: 9, weight: .semibold)).foregroundColor(labelColor)
                context.draw(context.resolve(text), at: point, anchor: .center)
            }

            // Needle: triangle pointing up; rotate by -heading so it points to true north
            let needleColor = labelColor
            let base: CGFloat = radius * 0.22
            let tipLen: CGFloat = radius * 0.8
            var tri = Path()
            tri.move(to: CGPoint(x: center.x, y: center.y - tipLen))
            tri.addLine(to: CGPoint(x: center.x - base/2, y: center.y))
            tri.addLine(to: CGPoint(x: center.x + base/2, y: center.y))
            tri.closeSubpath()

            context.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: Angle(degrees: -heading))
                layer.translateBy(x: -center.x, y: -center.y)
                layer.fill(tri, with: .color(needleColor))
            }

            // Heading text
            let txt = Text("\(Int(heading.rounded()))°").font(.system(size: 9)).foregroundColor(labelColor.opacity(0.9))
            context.draw(context.resolve(txt), at: CGPoint(x: center.x, y: center.y + radius + 8), anchor: .top)
        }
        .padding(2)
    }
}
