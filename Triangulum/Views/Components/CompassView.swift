import SwiftUI

public struct CompassView: View {
    public let heading: Double // degrees 0..360, 0=N
    public var redMode: Bool = false
    public var tint: Color? = nil // overrides default ink in non-red mode

    public init(heading: Double, redMode: Bool = false, tint: Color? = nil) {
        self.heading = heading
        self.redMode = redMode
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let r = min(size.width, size.height) * 0.48
            let ink = redMode ? Color.red : (tint ?? Color.white)
            let ringColor = ink.opacity(0.7)

            // Outer ring
            let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
            context.stroke(ring, with: .color(ringColor), lineWidth: 1)

            // Tick marks (every 45°)
            for deg in stride(from: 0.0, through: 315.0, by: 45.0) {
                let ang = deg * .pi / 180
                let p1 = CGPoint(x: center.x + cos(ang) * (r - 2), y: center.y + sin(ang) * (r - 2))
                let p2 = CGPoint(x: center.x + cos(ang) * (r - 6), y: center.y + sin(ang) * (r - 6))
                var tick = Path()
                tick.move(to: p1)
                tick.addLine(to: p2)
                context.stroke(tick, with: .color(ringColor), lineWidth: 1)
            }

            // Cardinal labels fixed to view; needle rotates instead
            let labelColor = ink
            let labels: [(String, Double)] = [("N",0),("E",90),("S",180),("W",270)]
            for (txt, deg) in labels {
                let ang = deg * .pi / 180
                let p = CGPoint(x: center.x + cos(ang) * (r - 10), y: center.y + sin(ang) * (r - 10))
                let text = Text(txt).font(.system(size: 9, weight: .semibold)).foregroundColor(labelColor)
                context.draw(context.resolve(text), at: p, anchor: .center)
            }

            // Needle: triangle pointing up; rotate by -heading so it points to true north
            let needleColor = labelColor
            let base: CGFloat = r * 0.22
            let tipLen: CGFloat = r * 0.8
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
            context.draw(context.resolve(txt), at: CGPoint(x: center.x, y: center.y + r + 8), anchor: .top)
        }
        .padding(2)
    }
}
