//
//  CelComponentRenderingTests.swift
//  TriangulumTests
//
//  Smoke test: renders every Cel design-system component (and every relevant
//  branch) through a live UIHostingController in a single composite view, so
//  each component's SwiftUI `body` is executed and the full render pipeline
//  completes without crashing.
//
//  Note: this is intentionally a *smoke* test. Assertions on the computed
//  values (clamp boundaries, percentage formatting, alignment mapping,
//  status→color) live in `CelFormattingTests` / `CelStatusTests`, where they
//  can actually observe the logic. A window-attachment assertion here only
//  proves "no layout crash".
//

import Testing
import SwiftUI
import UIKit
@testable import Triangulum

// MARK: - Render host

/// Wraps a SwiftUI view in a UIHostingController installed in a live UIWindow
/// and forces layout, causing SwiftUI to evaluate `body`.
///
/// Returns both the hosting controller and the owning `UIWindow`. The caller
/// MUST hold the returned window for the lifetime of its assertions: a
/// `UIWindow` created locally is only kept alive by `UIApplication`'s
/// undocumented key-window retention, which is unreliable (especially under
/// `UIScene`) and can let `host.view.window` become `nil` mid-test. Keeping a
/// strong reference guarantees the window survives until the test finishes.
@MainActor
private func renderHost<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 320, height: 568)
) -> (host: UIHostingController<V>, window: UIWindow) {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return (host, window)
}

@MainActor
@Suite
struct CelComponentRenderingTests {

    // A single composite view exercises every component and every branch that
    // the per-variant tests used to cover individually:
    //   • celestialBackground modifier
    //   • InstrumentCard cornerTicks: true / false
    //   • CornerTicks (standalone)
    //   • CelGlyph
    //   • InstrumentHeader (trailing + EmptyView overload)
    //   • CelChevron, CelDivider
    //   • MetricReadout leading/no-unit, trailing/unit, center
    //   • LuminousBar labeled (value 1.5 → clamp) + unlabeled (value 0)
    //   • StatusPill icon + dot + typed(status:) init
    //   • CelInlineMessage
    //   • Text().celEyebrow() modifier
    @Test func compositeCelComponentsRenderWithoutCrashing() {
        let (host, window) = renderHost(
            ScrollView {
                VStack(alignment: .leading, spacing: CelSpace.md) {
                    // Card with corner ticks + a trailing StatusPill header.
                    VStack(spacing: CelSpace.sm) {
                        InstrumentHeader(icon: "barometer", title: "BAROMETER", tint: .celCyan) {
                            StatusPill("LIVE", color: .celGreen)
                        }
                        InstrumentHeader(icon: "location", title: "LOCATION", tint: .celGold)
                        MetricReadout("PRESSURE", value: "1013.25", alignment: .leading)
                        MetricReadout("ALT", value: "100", unit: "m", alignment: .trailing)
                        MetricReadout("X", value: "0", unit: "°", alignment: .center)
                        LuminousBar(value: 1.5, tint: .celCyan, height: 8,
                                    accessibilityLabel: "Signal")
                        LuminousBar(value: 0.0)
                    }
                    .instrumentCard(tint: .celGold, cornerTicks: true)

                    // cornerTicks: false branch.
                    Color.clear.frame(height: 24)
                        .instrumentCard(tint: .celCyan, cornerTicks: false)

                    // Remaining components.
                    CornerTicks(tint: .celCyan).frame(height: 24)
                    CelGlyph(systemName: "barometer", tint: .celCyan, size: 40)
                    HStack {
                        CelChevron()
                        StatusPill("ONLINE", color: .celGreen, icon: "wifi") // icon branch
                        StatusPill("OFFLINE", color: .celRed)                // dot branch
                        StatusPill("Ready", status: .nominal)                // typed init
                    }
                    CelDivider()
                    CelInlineMessage(text: "No data",
                                     icon: "exclamationmark.triangle.fill",
                                     color: .celRed)
                    Text("SECTION").celEyebrow()
                }
                .padding()
            }
            .celestialBackground()
        )

        // Window attachment == the full render pipeline (including every body
        // above) completed without a layout crash. `withExtendedLifetime`
        // guarantees the owning window stays alive through the assertion — see
        // the note on `renderHost` about key-window retention being unreliable.
        withExtendedLifetime(window) {
            #expect(host.view.window != nil, "Composite Cel view failed to attach to a window during rendering")
        }
    }
}
