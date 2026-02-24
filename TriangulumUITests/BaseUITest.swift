//
//  BaseUITest.swift
//  TriangulumUITests
//
//  Shared helpers for all UI test classes.
//

import XCTest

extension XCTestCase {
    /// Creates and configures the application under test with the `-ui-testing`
    /// launch argument so sensors, timers, and permission prompts are suppressed.
    func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        return app
    }
}
