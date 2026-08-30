//
//  CelestialTheme.swift
//  Triangulum
//
//  Celestial field-instrument design system.
//  Ink-navy fields, warm readouts, semantic instrument accents, and
//  hairline star-chart registration marks.
//
//  Typography strategy (no bundled fonts, ships with iOS):
//   • Display / titles  → DIN Alternate   — compact instrument structure
//   • Values / prose    → Avenir Next     — legible field readouts
//   • Telemetry labels  → SF Mono         — tabular instrument metadata
//

import SwiftUI

// MARK: - Color Tokens

extension Color {

    // Deep-space field
    static let celBackgroundTop    = Color(red: 0.059, green: 0.067, blue: 0.125)   // #0F1120
    static let celBackgroundBottom = Color(red: 0.035, green: 0.039, blue: 0.078)   // #090A14
    static let celNebula           = Color(red: 0.255, green: 0.173, blue: 0.420)   // #412C6B

    // Surfaces
    static let celSurfaceTop    = Color(red: 0.125, green: 0.129, blue: 0.204)       // #202134
    static let celSurfaceBottom = Color(red: 0.082, green: 0.086, blue: 0.153)       // #151627
    static let celSurfaceRaised = Color(red: 0.184, green: 0.173, blue: 0.267)       // #2F2C44

    // Hairlines & grid
    static let celStroke       = Color(red: 0.329, green: 0.314, blue: 0.388).opacity(0.72)
    static let celStrokeStrong = Color(red: 0.686, green: 0.545, blue: 0.929).opacity(0.42)
    static let celGrid         = Color(red: 0.369, green: 0.804, blue: 0.827).opacity(0.07)

    // Text
    static let celText      = Color(red: 0.945, green: 0.933, blue: 0.863)           // #F1EEDC
    static let celTextDim   = Color(red: 0.659, green: 0.655, blue: 0.710)           // #A8A7B5
    static let celTextFaint = Color(red: 0.435, green: 0.439, blue: 0.506)           // #6F7081

    // Luminous accents
    static let celCyan     = Color(red: 0.369, green: 0.804, blue: 0.827)            // #5ECDD3
    static let celCyanDeep = Color(red: 0.184, green: 0.561, blue: 0.608)            // #2F8F9B
    static let celGold     = Color(red: 0.902, green: 0.741, blue: 0.384)            // #E6BD62
    static let celGoldDeep = Color(red: 0.718, green: 0.514, blue: 0.192)            // #B78331
    static let celViolet   = Color(red: 0.686, green: 0.545, blue: 0.929)            // #AF8BED

    // Status
    static let celGreen = Color(red: 0.388, green: 0.831, blue: 0.604)               // #63D49A
    static let celAmber = Color(red: 0.910, green: 0.729, blue: 0.341)               // #E8BA57
    static let celRed   = Color(red: 0.902, green: 0.322, blue: 0.373)               // #E6525F
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
        colors: [.celGold, .celGoldDeep],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Typography

extension Font {
    /// Condensed instrument display — section and screen titles.
    static func celDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("DIN Alternate", size: size, relativeTo: .title)
            .weight(weight)
    }

    /// Legible instrument readout with tabular numerals.
    static func celReadout(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Avenir Next", size: size, relativeTo: .title2)
            .weight(weight)
            .monospacedDigit()
    }

    /// Human-readable labels and short prose.
    static func celBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size, relativeTo: .body)
            .weight(weight)
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
    static let cardRadius: CGFloat = 14
}
