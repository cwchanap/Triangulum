//
//  CelestialTheme.swift
//  Triangulum
//
//  Celestial Atlas design system — a deep-space observatory aesthetic.
//  Near-black navy fields, luminous cyan/gold data, hairline star-chart
//  grids, and monospaced instrument readouts.
//
//  Typography strategy (no bundled fonts, ships with iOS):
//   • Display / titles  → New York serif  (.serif)   — astronomical journal
//   • Eyebrows / data   → SF Mono         (.monospaced) — instrument readouts
//

import SwiftUI

// MARK: - Color Tokens

extension Color {

    // Deep-space field
    static let celBackgroundTop    = Color(red: 0.020, green: 0.027, blue: 0.055)   // #05070E
    static let celBackgroundBottom = Color(red: 0.043, green: 0.063, blue: 0.125)   // #0B1020
    static let celNebula           = Color(red: 0.196, green: 0.137, blue: 0.392)   // #322364

    // Surfaces
    static let celSurfaceTop    = Color(red: 0.082, green: 0.125, blue: 0.227)       // #15203A
    static let celSurfaceBottom = Color(red: 0.043, green: 0.075, blue: 0.149)       // #0B1326
    static let celSurfaceRaised = Color(red: 0.110, green: 0.157, blue: 0.275)       // #1C2846

    // Hairlines & grid
    static let celStroke       = Color.white.opacity(0.08)
    static let celStrokeStrong = Color(red: 0.357, green: 0.878, blue: 0.941).opacity(0.28)
    static let celGrid         = Color(red: 0.357, green: 0.878, blue: 0.941).opacity(0.06)

    // Text
    static let celText      = Color(red: 0.902, green: 0.925, blue: 0.961)           // #E6ECF5
    static let celTextDim   = Color(red: 0.616, green: 0.690, blue: 0.800)           // #9DB0CC
    static let celTextFaint = Color(red: 0.361, green: 0.435, blue: 0.561)           // #5C6F8F

    // Luminous accents
    static let celCyan     = Color(red: 0.357, green: 0.878, blue: 0.941)            // #5BE0F0
    static let celCyanDeep = Color(red: 0.165, green: 0.576, blue: 0.710)            // #2A93B5
    static let celGold     = Color(red: 0.957, green: 0.808, blue: 0.478)            // #F4CE7A
    static let celViolet   = Color(red: 0.557, green: 0.482, blue: 0.902)            // #8E7BE6

    // Status
    static let celGreen = Color(red: 0.357, green: 0.902, blue: 0.659)               // #5BE6A8
    static let celAmber = Color(red: 0.949, green: 0.706, blue: 0.361)               // #F2B45C
    static let celRed   = Color(red: 0.957, green: 0.447, blue: 0.447)               // #F47272
}

// MARK: - Gradients

enum CelGradient {
    static let space = LinearGradient(
        colors: [.celBackgroundTop, .celBackgroundBottom],
        startPoint: .top, endPoint: .bottom
    )

    static let surface = LinearGradient(
        colors: [.celSurfaceTop, .celSurfaceBottom],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let cyanGlow = LinearGradient(
        colors: [.celCyan, .celCyanDeep],
        startPoint: .top, endPoint: .bottom
    )

    static let goldGlow = LinearGradient(
        colors: [.celGold, Color(red: 0.85, green: 0.62, blue: 0.30)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Typography

extension Font {
    /// Editorial serif display — section & screen titles.
    static func celDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Monospaced instrument readout — numeric values.
    static func celReadout(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Small uppercase mono label ("eyebrow").
    static let celEyebrow = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let celLabel   = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let celTiny    = Font.system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - Text styles

extension View {
    /// Uppercase, tracked, dim monospaced label used above values & as section eyebrows.
    /// - Parameter size: Mono font size in points. Defaults to 11 (matches `Font.celEyebrow`).
    func celEyebrow(_ color: Color = .celTextDim, size: CGFloat = 11) -> some View {
        self.font(.system(size: size, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Spacing scale

enum CelSpace {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 32
    static let cardRadius: CGFloat = 18
}
