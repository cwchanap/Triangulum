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
