import SwiftUI

struct BubbleLevelView: View {
    let rollDeg: Double       // calibrated, degrees; positive = right side down
    let pitchDeg: Double      // calibrated, degrees; positive = top tilts away from user
    let thresholdDeg: Double  // bubble turns green within this radius

    init(rollDeg: Double, pitchDeg: Double, thresholdDeg: Double) {
        self.rollDeg = rollDeg
        self.pitchDeg = pitchDeg
        self.thresholdDeg = thresholdDeg
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) * 0.48
            let scale = outerRadius / 90.0  // 1 degree = this many points; +/-90 deg fills the ring
            let bubbleRadius: CGFloat = 14
            let clampedThresholdDeg = LevelMath.clampedThreshold(thresholdDeg)

            // Outer ring
            let outerRing = Path(ellipseIn: CGRect(
                x: center.x - outerRadius, y: center.y - outerRadius,
                width: outerRadius * 2, height: outerRadius * 2
            ))
            context.stroke(outerRing, with: .color(Color.prussianBlueDark.opacity(0.4)), lineWidth: 1.5)

            // Cross-hair
            var hLine = Path()
            hLine.move(to: CGPoint(x: center.x - outerRadius, y: center.y))
            hLine.addLine(to: CGPoint(x: center.x + outerRadius, y: center.y))
            var vLine = Path()
            vLine.move(to: CGPoint(x: center.x, y: center.y - outerRadius))
            vLine.addLine(to: CGPoint(x: center.x, y: center.y + outerRadius))
            context.stroke(hLine, with: .color(Color.prussianBlueDark.opacity(0.2)), lineWidth: 1)
            context.stroke(vLine, with: .color(Color.prussianBlueDark.opacity(0.2)), lineWidth: 1)

            // Cardinal tick marks
            for angle in [Double.pi * -0.5, 0.0, Double.pi * 0.5, Double.pi] {
                let outer = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                let inner = CGPoint(
                    x: center.x + cos(angle) * (outerRadius - 8),
                    y: center.y + sin(angle) * (outerRadius - 8)
                )
                var tick = Path()
                tick.move(to: outer)
                tick.addLine(to: inner)
                context.stroke(tick, with: .color(Color.prussianBlueDark.opacity(0.4)), lineWidth: 2)
            }

            // Level zone indicator (dashed circle at threshold radius)
            let thresholdRadius = CGFloat(clampedThresholdDeg) * scale
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - thresholdRadius, y: center.y - thresholdRadius,
                    width: thresholdRadius * 2, height: thresholdRadius * 2
                )),
                with: .color(Color.prussianBlueDark.opacity(0.4)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )

            // Bubble position — clamped to stay inside outer ring
            let rawX = CGFloat(rollDeg) * scale
            let rawY = CGFloat(-pitchDeg) * scale  // negate: positive pitch (top away) -> bubble moves up
            let dist = sqrt(rawX * rawX + rawY * rawY)
            let safeClamp = max(0, outerRadius - bubbleRadius)
            let clampedDist = min(dist, safeClamp)
            let bx: CGFloat
            let by: CGFloat
            if dist > 0 {
                let a = atan2(rawY, rawX)
                bx = center.x + cos(a) * clampedDist
                by = center.y + sin(a) * clampedDist
            } else {
                bx = center.x
                by = center.y
            }

            let isLevel = LevelMath.isLevel(roll: rollDeg, pitch: pitchDeg, threshold: clampedThresholdDeg)
            let bubbleColor: Color = isLevel ? .green : .prussianAccent
            let bubbleRect = CGRect(
                x: bx - bubbleRadius, y: by - bubbleRadius,
                width: bubbleRadius * 2, height: bubbleRadius * 2
            )
            context.fill(Path(ellipseIn: bubbleRect), with: .color(bubbleColor.opacity(0.85)))
            context.stroke(Path(ellipseIn: bubbleRect), with: .color(bubbleColor), lineWidth: 2)
        }
        .padding(2)
        .accessibilityLabel("Bubble level")
        .accessibilityValue(isLevelState
            ? "Level"
            : "Roll \(String(format: "%.1f", rollDeg)) degrees, pitch \(String(format: "%.1f", pitchDeg)) degrees"
        )
    }

    private var isLevelState: Bool {
        LevelMath.isLevel(roll: rollDeg, pitch: pitchDeg, threshold: LevelMath.clampedThreshold(thresholdDeg))
    }
}

#Preview {
    VStack(spacing: 24) {
        BubbleLevelView(rollDeg: 0.0, pitchDeg: 0.0, thresholdDeg: 2.0)
            .frame(width: 260, height: 260)
        BubbleLevelView(rollDeg: 15.0, pitchDeg: -8.0, thresholdDeg: 2.0)
            .frame(width: 260, height: 260)
    }
    .padding()
    .background(Color.prussianSoft)
}
