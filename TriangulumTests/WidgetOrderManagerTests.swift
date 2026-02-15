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

    @Test func testDefaultOrderContainsAllWidgets() {
        let defaults = makeUserDefaults()
        let manager = WidgetOrderManager(userDefaults: defaults)

        #expect(manager.widgetOrder.count == WidgetType.allCases.count)
        for widgetType in WidgetType.allCases {
            #expect(manager.widgetOrder.contains(widgetType))
        }
    }

    @Test func testMoveWidgetUpdatesOrder() {
        let defaults = makeUserDefaults()
        let manager = WidgetOrderManager(userDefaults: defaults)
        let originalFirst = manager.widgetOrder[0]
        let originalSecond = manager.widgetOrder[1]

        manager.moveWidget(from: IndexSet(integer: 0), to: 2)

        #expect(manager.widgetOrder[0] == originalSecond)
        #expect(manager.widgetOrder[1] == originalFirst)
    }

    @Test func testWidgetTypeProperties() {
        for widgetType in WidgetType.allCases {
            #expect(!widgetType.displayName.isEmpty)
            #expect(!widgetType.iconName.isEmpty)
        }
    }

    @Test func testMoveWidgetPersistsToUserDefaults() {
        let defaults = makeUserDefaults()
        let manager = WidgetOrderManager(userDefaults: defaults)

        manager.moveWidget(from: IndexSet(integer: 0), to: 2)

        // Verify the order was persisted
        let saved = defaults.stringArray(forKey: "widgetOrder")
        #expect(saved != nil)
        #expect(saved?.count == WidgetType.allCases.count)
        #expect(saved?[0] == manager.widgetOrder[0].rawValue)
    }
}
