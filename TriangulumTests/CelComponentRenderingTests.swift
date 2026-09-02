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
//  The `renderHost` helper lives in `SwiftUIRenderTestHelper.swift`, shared
//  with the Almanac rendering suite (no third window-retention
//  implementation).
//

import Testing
import SwiftUI
import UIKit
@testable import Triangulum

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

    // CelInlineMessage applies `.accessibilityElement(children: .ignore)` +
    // `.accessibilityLabel(text)` (mirroring StatusPill) so VoiceOver announces
    // the message once instead of reading the decorative SF Symbol name first.
    //
    // SwiftUI's accessibility tree is built lazily and is NOT materialized
    // synchronously through UIKit (`host.view.accessibilityElements` is empty
    // outside a live assistive-tech session), so the combined-element label
    // can't be asserted via UIKit introspection here. Instead we render the
    // accessibility-modified body directly and assert the full pipeline
    // completes without crashing — a regression in the modifiers (e.g. a
    // malformed label binding) surfaces as a render failure.
    @Test func celInlineMessageRendersWithAccessibilityModifiers() {
        let (host, window) = renderHost(
            VStack {
                CelInlineMessage(text: "Location access denied", color: .celRed)
                CelInlineMessage(text: "Hint with default icon")
            }
        )

        withExtendedLifetime(window) {
            guard let view = host.viewIfLoaded else {
                Issue.record("CelInlineMessage hosting view failed to load")
                return
            }
            #expect(view.window != nil, "CelInlineMessage with accessibility modifiers failed to attach to a window during rendering")
        }
    }
}
