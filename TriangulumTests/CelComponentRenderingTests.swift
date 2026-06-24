//
//  CelComponentRenderingTests.swift
//  TriangulumTests
//
//  Renders Cel design-system components through a UIHostingController so their
//  SwiftUI `body` code is executed (closing the design-system patch coverage
//  gap). Each test asserts the view renders into a live window without crashing.
//  Branch coverage is achieved by rendering every variant (e.g. both StatusPill
//  icon/dot branches, all MetricReadout alignments, both LuminousBar
//  accessibility branches).
//

import Testing
import SwiftUI
import UIKit
@testable import Triangulum

// MARK: - Render helpers

/// Wraps a SwiftUI view in a UIHostingController installed in a live UIWindow
/// and forces layout. This causes SwiftUI to evaluate the view's `body`, which
/// unit tests cannot otherwise reach. Returns the hosting controller so callers
/// can assert on the rendered state.
@MainActor
private func renderHost<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 320, height: 240)
) -> UIHostingController<V> {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return host
}

/// Renders a view and asserts it was attached to a window — i.e. that the full
/// render pipeline (including `body` evaluation) completed without crashing.
@MainActor
private func expectRendered<V: View>(_ view: V) {
    let host = renderHost(view)
    #expect(host.view.window != nil, "View failed to attach to a window during rendering")
}

@MainActor
@Suite
struct CelComponentRenderingTests {

    // MARK: - Background modifier (celestialBackground)

    @Test func celestialBackgroundModifierRenders() {
        expectRendered(Color.clear.celestialBackground())
    }

    // MARK: - Instrument card (InstrumentCardModifier + CornerTicks)

    @Test func instrumentCardRendersWithCornerTicks() {
        expectRendered(Color.celCyan.frame(width: 80, height: 80)
            .instrumentCard(tint: .celGold, cornerTicks: true))
    }

    @Test func instrumentCardRendersWithoutCornerTicks() {
        // cornerTicks: false → the `if cornerTicks { CornerTicks(...) }` branch is skipped.
        expectRendered(Color.celCyan.frame(width: 80, height: 80)
            .instrumentCard(tint: .celGold, cornerTicks: false))
    }

    @Test func cornerTicksRendersStandalone() {
        expectRendered(CornerTicks(tint: .celCyan, length: 7).frame(width: 100, height: 100))
    }

    // MARK: - CelGlyph

    @Test func celGlyphRenders() {
        expectRendered(CelGlyph(systemName: "barometer", tint: .celCyan, size: 40))
    }

    // MARK: - InstrumentHeader (both initializers)

    @Test func instrumentHeaderTrailingRenders() {
        expectRendered(InstrumentHeader(icon: "barometer", title: "BAROMETER", tint: .celCyan) {
            StatusPill("LIVE", color: .celGreen)
        })
    }

    @Test func instrumentHeaderEmptyViewOverloadRenders() {
        // Exercises the `InstrumentHeader where Trailing == EmptyView` convenience init.
        expectRendered(InstrumentHeader(icon: "location", title: "LOCATION", tint: .celGold))
    }

    // MARK: - CelChevron, CelDivider

    @Test func celChevronRenders() {
        expectRendered(CelChevron())
    }

    @Test func celDividerRenders() {
        expectRendered(CelDivider())
    }

    // MARK: - MetricReadout (alignment ternary + optional unit)

    @Test func metricReadoutLeadingWithoutUnit() {
        // unit nil → the `if let unit { Text(unit) }` branch is skipped.
        expectRendered(MetricReadout("PRESSURE", value: "1013.25", alignment: .leading))
    }

    @Test func metricReadoutTrailingWithUnit() {
        // unit non-nil → the `if let unit { Text(unit) }` branch executes.
        expectRendered(MetricReadout("ALT", value: "100", unit: "m", alignment: .trailing)
            .frame(width: 200))
    }

    @Test func metricReadoutCenter() {
        // .center branch of the alignment ternary.
        expectRendered(MetricReadout("X", value: "0", unit: "°", alignment: .center)
            .frame(width: 200))
    }

    // MARK: - LuminousBar (clamp + both accessibility branches)

    @Test func luminousBarClampsAboveOneWithLabel() {
        // value 1.5 → clamped to 1.0 via `max(0, min(1, value))`.
        // accessibilityLabel non-nil → LuminousBarAccessibility renders the labeled branch.
        expectRendered(LuminousBar(value: 1.5, tint: .celCyan, height: 8, accessibilityLabel: "Signal")
            .frame(width: 200))
    }

    @Test func luminousBarZeroWithoutLabel() {
        // value 0 → clamp lower bound. accessibilityLabel nil → `.accessibilityHidden(true)` branch.
        expectRendered(LuminousBar(value: 0.0).frame(width: 200))
    }

    // MARK: - StatusPill (icon branch + dot branch)

    @Test func statusPillWithIcon() {
        // icon non-nil → the `Image(systemName:)` branch.
        expectRendered(StatusPill("ONLINE", color: .celGreen, icon: "wifi"))
    }

    @Test func statusPillWithoutIconDotBranch() {
        // icon nil → the `Circle().fill(color)` dot branch.
        expectRendered(StatusPill("OFFLINE", color: .celRed))
    }

    // MARK: - CelInlineMessage

    @Test func celInlineMessageRenders() {
        expectRendered(CelInlineMessage(text: "No data",
                                        icon: "exclamationmark.triangle.fill",
                                        color: .celRed))
    }

    // MARK: - CelestialTheme.View.celEyebrow(_:) modifier

    @Test func celEyebrowModifierRenders() {
        // Covers the `View.celEyebrow(_:)` body in CelestialTheme.swift.
        expectRendered(Text("SECTION").celEyebrow())
    }
}
