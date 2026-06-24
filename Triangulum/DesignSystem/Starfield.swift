//
//  Starfield.swift
//  Triangulum
//
//  Atmospheric deep-space background: a deterministic, gently twinkling star
//  field over a nebula-tinted gradient, with an optional Triangulum
//  constellation motif. Reused as the canvas behind every screen.
//

import SwiftUI

// MARK: - Star model

private struct Star {
    let x: CGFloat          // 0...1
    let y: CGFloat          // 0...1
    let radius: CGFloat
    let baseOpacity: Double
    let phase: Double
    let speed: Double
    let tint: Color
}

/// Tiny deterministic RNG so the star field is stable across redraws.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

private func makeStars(count: Int, seed: UInt64) -> [Star] {
    var rng = SeededGenerator(seed: seed)
    let tints: [Color] = [.white, .white, .white, .celCyan, .celGold, .celViolet]
    return (0..<count).map { _ in
        Star(
            x: CGFloat.random(in: 0...1, using: &rng),
            y: CGFloat.random(in: 0...1, using: &rng),
            radius: CGFloat.random(in: 0.4...1.6, using: &rng),
            baseOpacity: Double.random(in: 0.2...0.95, using: &rng),
            phase: Double.random(in: 0...(2 * .pi), using: &rng),
            speed: Double.random(in: 0.4...1.6, using: &rng),
            tint: tints.randomElement(using: &rng) ?? .white
        )
    }
}

// MARK: - Starfield background

struct StarfieldBackground: View {
    var starCount: Int = 150
    var showConstellation: Bool = true
    var twinkles: Bool = true

    @Environment(\.scenePhase) private var scenePhase

    private let stars: [Star]

    init(starCount: Int = 150, showConstellation: Bool = true, twinkles: Bool = true) {
        self.starCount = starCount
        self.showConstellation = showConstellation
        self.twinkles = twinkles
        self.stars = makeStars(count: starCount, seed: 0xCAFE_BABE)
    }

    /// Whether the animated star canvas should tick this frame.
    /// Paused when twinkles are disabled OR the scene is not foreground-active,
    /// so backgrounded screens do not burn per-frame GPU work on a sensor-heavy app.
    private var animationPaused: Bool {
        Self.shouldPauseAnimation(twinkles: twinkles, scenePhase: scenePhase)
    }

    /// Pure, testable pause decision for the star `TimelineView`.
    /// - Returns: `true` when the star canvas should stop ticking.
    static func shouldPauseAnimation(twinkles: Bool, scenePhase: ScenePhase) -> Bool {
        !twinkles || scenePhase != .active
    }

    var body: some View {
        ZStack {
            CelGradient.space

            // Nebula glow blobs for depth. These are static and intentionally kept
            // OUTSIDE drawingGroup so their expensive Gaussian blurs are composed
            // once and cached by the render tree, rather than re-rasterized on
            // every animated star frame.
            Circle()
                .fill(Color.celCyan.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: -120, y: -220)
            Circle()
                .fill(Color.celViolet.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 130)
                .offset(x: 140, y: 320)

            // Only the animated star canvas is flattened/rasterized via drawingGroup.
            TimelineView(.animation(
                minimumInterval: twinkles ? 0.1 : .infinity,
                paused: animationPaused
            )) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    drawStars(context: &context, size: size, time: t)
                    if showConstellation {
                        drawTriangulum(context: &context, size: size, time: t)
                    }
                }
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
    }

    private func drawStars(context: inout GraphicsContext, size: CGSize, time: Double) {
        for star in stars {
            let twinkle = twinkles
                ? 0.55 + 0.45 * sin(time * star.speed + star.phase)
                : 1.0
            let opacity = star.baseOpacity * twinkle
            let point = CGPoint(x: star.x * size.width, y: star.y * size.height)
            let rect = CGRect(
                x: point.x - star.radius, y: point.y - star.radius,
                width: star.radius * 2, height: star.radius * 2
            )
            // Soft halo for the brighter stars.
            if star.radius > 1.1 {
                let halo = rect.insetBy(dx: -star.radius * 2.2, dy: -star.radius * 2.2)
                context.fill(Circle().path(in: halo),
                             with: .color(star.tint.opacity(opacity * 0.12)))
            }
            context.fill(Circle().path(in: rect),
                         with: .color(star.tint.opacity(opacity)))
        }
    }

    /// The three principal stars of Triangulum, faintly connected.
    private func drawTriangulum(context: inout GraphicsContext, size: CGSize, time: Double) {
        let pulse = 0.5 + 0.5 * sin(time * 0.6)
        let pts = [
            CGPoint(x: size.width * 0.78, y: size.height * 0.12),  // Beta
            CGPoint(x: size.width * 0.90, y: size.height * 0.24),  // Gamma
            CGPoint(x: size.width * 0.70, y: size.height * 0.27)   // Alpha
        ]
        var path = Path()
        path.move(to: pts[0])
        path.addLine(to: pts[1])
        path.addLine(to: pts[2])
        path.closeSubpath()
        context.stroke(path, with: .color(.celCyan.opacity(0.18 + 0.08 * pulse)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
        for p in pts {
            let r: CGFloat = 1.8
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect.insetBy(dx: -4, dy: -4)),
                         with: .color(.celCyan.opacity(0.20 * pulse)))
            context.fill(Circle().path(in: rect),
                         with: .color(.celGold.opacity(0.9)))
        }
    }
}

#Preview {
    StarfieldBackground()
}
