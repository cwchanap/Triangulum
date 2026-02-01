//
//  WidgetOrderManagerTests.swift
//  TriangulumTests
//
//  Tests for widget order persistence and migration
//

import Testing
import Foundation
@testable import Triangulum

@Suite(.serialized)
struct WidgetOrderManagerTests {
    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WidgetOrderManagerTests_\(UUID().uuidString)")!
    }

    @Test func testLoadWidgetOrderAppendsMissingWidgets() {
        let defaults = makeUserDefaults()
        defaults.set(["location", "barometer"], forKey: "widgetOrder")

        let manager = WidgetOrderManager(userDefaults: defaults)

        #expect(manager.widgetOrder.starts(with: [.location, .barometer]))
        #expect(manager.widgetOrder.contains(.satellite))
        #expect(manager.widgetOrder.count == WidgetType.allCases.count)
    }

    @Test func testLoadWidgetOrderDropsUnknownWidgets() {
        let defaults = makeUserDefaults()
        defaults.set(["location", "unknown_widget", "weather"], forKey: "widgetOrder")

        let manager = WidgetOrderManager(userDefaults: defaults)

        #expect(manager.widgetOrder.contains(.location))
        #expect(manager.widgetOrder.contains(.weather))
        #expect(!manager.widgetOrder.contains { $0.rawValue == "unknown_widget" })
        #expect(manager.widgetOrder.count == WidgetType.allCases.count)
    }
}
