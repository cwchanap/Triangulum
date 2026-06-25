//
//  DesignSystemTests.swift
//  TriangulumTests
//
//  Tests for the Celestial design-system behavior changes:
//   • Starfield pause logic (scenePhase + twinkles) — Issue #3
//   • InstrumentHeader / celEyebrow construction smoke — Issue #1
//

import Testing
import SwiftUI
@testable import Triangulum

@Suite
struct StarfieldPauseTests {

    @Test func testAnimatesWhenActiveAndTwinkling() {
        // Foreground + twinkles on → canvas must tick (not paused).
        #expect(StarfieldBackground.shouldPauseAnimation(twinkles: true, scenePhase: .active) == false)
    }

    @Test func testPausesWhenTwinklesDisabled() {
        // Static (non-twinkling) starfields never need to animate, regardless of phase.
        #expect(StarfieldBackground.shouldPauseAnimation(twinkles: false, scenePhase: .active) == true)
        #expect(StarfieldBackground.shouldPauseAnimation(twinkles: false, scenePhase: .background) == true)
    }

    @Test func testPausesWhenBackgrounded() {
        // Backgrounded scenes must not burn per-frame GPU work on a sensor-heavy app.
        #expect(StarfieldBackground.shouldPauseAnimation(twinkles: true, scenePhase: .background) == true)
    }

    @Test func testPausesWhenInactive() {
        // .inactive covers e.g. multitasking switcher / covered-but-attached states.
        #expect(StarfieldBackground.shouldPauseAnimation(twinkles: true, scenePhase: .inactive) == true)
    }
}

@Suite
struct DesignSystemConstructionTests {

    @Test func testStarfieldBackgroundConstructsWithAllOptions() {
        // Smoke: ensure init + default params still build after the drawingGroup /
        // scenePhase restructure (Issues #2/#3/#4).
        let defaultField = StarfieldBackground()
        let noConstellation = StarfieldBackground(showConstellation: false)
        let staticField = StarfieldBackground(twinkles: false)
        let customCount = StarfieldBackground(starCount: 50)

        #expect(defaultField.starCount == 150)
        #expect(noConstellation.showConstellation == false)
        #expect(staticField.twinkles == false)
        #expect(customCount.starCount == 50)
    }

    @Test func testInstrumentHeaderConstructs() {
        // Smoke: the font-clarity refactor (#1) must still produce a valid header.
        let header = InstrumentHeader(icon: "barometer", title: "BAROMETER", tint: .celCyan)
        #expect(header.icon == "barometer")
        #expect(header.title == "BAROMETER")
        #expect(header.tint == .celCyan)
    }
}

@Suite
struct CelFormattingTests {
    // Boundary tests for the pure helpers extracted from LuminousBar /
    // MetricReadout (review #4). These were previously only exercised by
    // render-only tests that asserted nothing about the computed values.

    @Test func clampedToUnitClampsBelowZeroAndAboveOne() {
        #expect((-0.5).clampedToUnit() == 0.0)
        #expect(0.0.clampedToUnit() == 0.0)
        #expect(0.5.clampedToUnit() == 0.5)
        #expect(1.0.clampedToUnit() == 1.0)
        #expect(1.5.clampedToUnit() == 1.0)
    }

    @Test func percentStringClampsAndFormats() {
        #expect(celPercentString(for: -0.5) == "0 percent")
        #expect(celPercentString(for: 0.0) == "0 percent")
        #expect(celPercentString(for: 0.5) == "50 percent")
        #expect(celPercentString(for: 1.0) == "100 percent")
        #expect(celPercentString(for: 1.5) == "100 percent")
    }

    @Test func percentStringRoundsTruncatesDown() {
        // Mirrors the original `Int(...)` truncation behavior.
        #expect(celPercentString(for: 0.999) == "99 percent")
        #expect(celPercentString(for: 0.001) == "0 percent")
    }

    @Test func frameAlignmentMapsAllAxes() {
        #expect(HorizontalAlignment.leading.frameAlignment == .leading)
        #expect(HorizontalAlignment.trailing.frameAlignment == .trailing)
        #expect(HorizontalAlignment.center.frameAlignment == .center)
    }

    @Test func luminousFillWidthRendersEmptyAtZero() {
        // A 0% bar must render truly empty so the visible state agrees with the
        // VoiceOver "0 percent" value (no floor-sized nub).
        #expect(0.0.luminousFillWidth(trackWidth: 200, floor: 6) == 0)
        // Negative inputs clamp to 0 → also empty.
        #expect((-0.5).luminousFillWidth(trackWidth: 200, floor: 6) == 0)
    }

    @Test func luminousFillWidthFloorsSmallPositiveValues() {
        // Very small positive readings stay visible via the floor so a trace
        // signal isn't invisible. 0.001 * 200 = 0.2 → floored to 6.
        #expect(0.001.luminousFillWidth(trackWidth: 200, floor: 6) == 6)
        // Just above 0 but below floor still floors.
        #expect(0.01.luminousFillWidth(trackWidth: 200, floor: 6) == 6)
    }

    @Test func luminousFillWidthScalesAndClamps() {
        // Mid value scales proportionally once it exceeds the floor.
        #expect(0.5.luminousFillWidth(trackWidth: 200, floor: 6) == 100)
        // Full / over-full value fills the whole track.
        #expect(1.0.luminousFillWidth(trackWidth: 200, floor: 6) == 200)
        #expect(1.5.luminousFillWidth(trackWidth: 200, floor: 6) == 200)
    }
}

@Suite
struct CelStatusTests {
    // Review #3: the typed status→color mapping prevents status/color drift.

    @Test func statusMapsToCanonicalColors() {
        #expect(CelStatus.nominal.color == .celGreen)
        #expect(CelStatus.caution.color == .celAmber)
        #expect(CelStatus.alert.color == .celRed)
    }

    @Test func statusPillTypedInitAdoptsStatusColor() {
        let nominal = StatusPill("Live", status: .nominal)
        let alert = StatusPill("Down", status: .alert)
        #expect(nominal.color == .celGreen)
        #expect(alert.color == .celRed)
        // Default icon stays nil (dot) for visual parity with existing pills.
        #expect(nominal.icon == nil)
    }
}
