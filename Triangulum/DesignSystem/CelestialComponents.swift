//
//  CelestialComponents.swift
//  Triangulum
//
//  Reusable "instrument" building blocks for the Celestial Atlas system:
//  glassy dark cards, luminous headers, monospaced readouts, glowing bars,
//  status pills, and a screen-background helper.
//

import SwiftUI

// MARK: - Pure formatting helpers

extension Double {
    /// Clamps the receiver to the closed range [0, 1]. Shared by `LuminousBar`
    /// (visible fill width) and `celPercentString(for:)` (VoiceOver value) so
    /// the two never disagree.
    func clampedToUnit() -> Double {
        max(0, min(1, self))
    }
}

/// Formats a 0...1 fraction as an integer VoiceOver percentage, e.g.
/// `0.5 → "50 percent"`. Out-of-range values are clamped to [0, 1].
func celPercentString(for fraction: Double) -> String {
    "\(Int(fraction.clampedToUnit() * 100)) percent"
}

extension HorizontalAlignment {
    /// Maps a stack `HorizontalAlignment` to the `Alignment` accepted by
    /// `View.frame(maxWidth:alignment:)`. Centralizes the ternary previously
    /// inlined in `MetricReadout`.
    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}

// MARK: - Typed status semantics

/// Closed status semantics mapping to the Cel status-color palette. Use the
/// `StatusPill(_:status:)` initializer to keep status text and color from
/// drifting apart (e.g. an "OK" label rendering in red). The raw
/// `StatusPill(_:color:icon:)` initializer remains for callers that compute
/// color from a continuous value (e.g. GPS accuracy tiers).
enum CelStatus {
    case nominal   // green
    case caution   // amber
    case alert     // red

    /// Canonical Cel status color for this status.
    var color: Color {
        switch self {
        case .nominal: return .celGreen
        case .caution: return .celAmber
        case .alert:   return .celRed
        }
    }
}

// MARK: - Screen background

extension View {
    /// Places the deep-space starfield behind the content and tints the scene dark.
    func celestialBackground(starCount: Int = 150,
                             showConstellation: Bool = true,
                             twinkles: Bool = true) -> some View {
        self
            .background(
                StarfieldBackground(starCount: starCount,
                                    showConstellation: showConstellation,
                                    twinkles: twinkles)
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Instrument card surface

struct InstrumentCardModifier: ViewModifier {
    var tint: Color = .celCyan
    var cornerTicks: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(CelSpace.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: CelSpace.cardRadius, style: .continuous)
                        .fill(CelGradient.surface)

                    // Faint top sheen
                    RoundedRectangle(cornerRadius: CelSpace.cardRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.10), .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )

                    if cornerTicks {
                        CornerTicks(tint: tint.opacity(0.5))
                            .padding(10)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: CelSpace.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tint.opacity(0.35), .celStroke],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
            .shadow(color: tint.opacity(0.08), radius: 20, x: 0, y: 0)
    }
}

extension View {
    func instrumentCard(tint: Color = .celCyan, cornerTicks: Bool = true) -> some View {
        modifier(InstrumentCardModifier(tint: tint, cornerTicks: cornerTicks))
    }
}

/// Star-chart registration marks in the four corners of a card.
struct CornerTicks: View {
    var tint: Color = .celStrokeStrong
    var length: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // top-left
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: length, y: 0))
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: length))
                // top-right
                p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w - length, y: 0))
                p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: length))
                // bottom-left
                p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: length, y: h))
                p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - length))
                // bottom-right
                p.move(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - length, y: h))
                p.move(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - length))
            }
            .stroke(tint, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Luminous glyph

struct CelGlyph: View {
    let systemName: String
    var tint: Color = .celCyan
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Circle()
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.5), radius: 8)
        // Decorative icon — the accompanying title text (e.g. in
        // InstrumentHeader) conveys the meaning to VoiceOver.
        .accessibilityHidden(true)
    }
}

// MARK: - Instrument header

struct InstrumentHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var tint: Color = .celCyan
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CelSpace.sm) {
            CelGlyph(systemName: icon, tint: tint, size: 36)
            Text(title)
                .celEyebrow(.celText, size: 13)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension InstrumentHeader where Trailing == EmptyView {
    init(icon: String, title: String, tint: Color = .celCyan) {
        self.init(icon: icon, title: title, tint: tint) { EmptyView() }
    }
}

/// A small chevron used to signal a card opens a detail screen.
struct CelChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.celTextFaint)
    }
}

// MARK: - Metric readout

struct MetricReadout: View {
    let label: String
    let value: String
    var unit: String?
    var alignment: HorizontalAlignment = .leading
    var valueColor: Color = .celText
    var valueSize: CGFloat = 24

    init(_ label: String, value: String, unit: String? = nil,
         alignment: HorizontalAlignment = .leading,
         valueColor: Color = .celText, valueSize: CGFloat = 24) {
        self.label = label
        self.value = value
        self.unit = unit
        self.alignment = alignment
        self.valueColor = valueColor
        self.valueSize = valueSize
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label).celEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.celReadout(valueSize, weight: .medium))
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.celReadout(valueSize * 0.5))
                        .foregroundStyle(Color.celTextDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
    }
}

// MARK: - Luminous progress bar

struct LuminousBar: View {
    var value: Double            // 0...1
    var tint: Color = .celCyan
    var height: CGFloat = 6
    /// Optional VoiceOver label. When nil, the bar is treated as decorative
    /// (it typically lives inside a card that already provides context).
    var accessibilityLabel: String?

    var body: some View {
        GeometryReader { geo in
            let clamped = value.clampedToUnit()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * clamped))
                    .shadow(color: tint.opacity(0.7), radius: 5)
            }
        }
        .frame(height: height)
        .modifier(LuminousBarAccessibility(value: value, label: accessibilityLabel))
    }
}

private struct LuminousBarAccessibility: ViewModifier {
    let value: Double
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(celPercentString(for: value))
        } else {
            content
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    var color: Color = .celCyan
    var icon: String?

    init(_ text: String, color: Color = .celCyan, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    /// Typed initializer: derives the canonical color from a `CelStatus`, so
    /// the status text and color can't drift apart. Use for fixed-status pills;
    /// prefer the raw `init(_:color:icon:)` when color is computed dynamically.
    init(_ text: String, status: CelStatus) {
        self.init(text, color: status.color)
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            } else {
                Circle().fill(color).frame(width: 5, height: 5)
                    .shadow(color: color, radius: 4)
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.12))
                .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        )
        // Combine the icon/dot + text into a single VoiceOver element so the
        // status is announced as one readable label rather than fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Hairline divider

struct CelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.celStroke)
            .frame(height: 1)
    }
}

// MARK: - Inline message (errors / hints)

struct CelInlineMessage: View {
    let text: String
    var icon: String = "exclamationmark.triangle.fill"
    var color: Color = .celAmber

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.25), lineWidth: 0.5))
        )
        // Combine the icon + text into a single VoiceOver element so the
        // message is announced as one readable label (matching StatusPill);
        // otherwise VoiceOver reads the decorative SF Symbol name first.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
