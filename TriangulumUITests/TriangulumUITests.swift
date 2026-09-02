//
//  TriangulumUITests.swift
//  TriangulumUITests
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import XCTest

final class TriangulumUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMobileShellDisplaysFivePrimaryTabs() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))

        ["Live", "Field", "Almanac", "Footprint", "Settings"].forEach { title in
            XCTAssertTrue(tabBar.buttons[title].exists, "Missing \(title) tab")
        }
    }

    /// End-to-end smoke over the `-ui-testing` fixture only: the Almanac tab
    /// restores the fixed Vancouver selection (September 15, 2026) with no
    /// location prompts, wall clock, or network. The fixture's restored date
    /// is not the device's today, so the Tides summary leads with the day's
    /// first tide (no countdown) and the fixture station sits 0 m away.
    @MainActor
    func testAlmanacFixtureShowsSunAndTides() throws {
        let app = makeApp()
        app.launch()

        let almanacTab = app.tabBars.buttons["Almanac"]
        XCTAssertTrue(almanacTab.waitForExistence(timeout: 5), "Almanac tab missing")
        almanacTab.tap()

        // Sun section: fixed fixture location/date context, time zone, sunrise/sunset.
        XCTAssertTrue(app.staticTexts["Vancouver, British Columbia"].waitForExistence(timeout: 8),
                      "Fixture location context missing")
        XCTAssertTrue(app.staticTexts["Selected Location"].exists, "Location mode missing")
        XCTAssertTrue(app.staticTexts["Tuesday, September 15"].exists, "Fixture date context missing")
        XCTAssertTrue(app.staticTexts["Sunrise"].exists, "Sunrise missing")
        XCTAssertTrue(app.staticTexts["Sunset"].exists, "Sunset missing")
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Pacific Daylight Time"))
            .firstMatch.exists, "Destination time-zone line missing")

        // Tides section: first-tide summary, chart accessibility summary,
        // station, distance, datum, provider attribution, planning-only warning.
        app.buttons["Tides"].tap()
        XCTAssertTrue(app.staticTexts["First tide"].waitForExistence(timeout: 8),
                      "First-tide summary missing")
        XCTAssertTrue(app.staticTexts["Tuesday, September 15"].exists, "Summary date missing")

        let chartSummary = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Tide chart for September 15, 2026"))
            .firstMatch
        XCTAssertTrue(chartSummary.waitForExistence(timeout: 5),
                      "Tide chart accessibility summary missing")

        let warning = app.staticTexts["Predictions are for planning only, not navigation."]
        for _ in 0..<8 where !warning.exists {
            app.swipeUp()
        }
        XCTAssertTrue(warning.exists, "Planning-only warning missing")
        XCTAssertTrue(app.staticTexts["Vancouver Point Atkinson"].exists, "Station name missing")
        XCTAssertTrue(app.staticTexts["0 m away"].exists, "Fixture station distance missing")
        XCTAssertTrue(app.staticTexts["Chart Datum"].exists, "Datum missing")
        XCTAssertTrue(app.staticTexts["Fixture (Canadian Hydrographic Service)"].exists,
                      "Provider attribution missing")
    }

    @MainActor
    func testLaunchPerformance() throws {
        guard ProcessInfo.processInfo.environment["RUN_LAUNCH_PERF_TESTS"] == "1" else {
            throw XCTSkip("Launch performance test is opt-in; set RUN_LAUNCH_PERF_TESTS=1 to run.")
        }

        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }
}
