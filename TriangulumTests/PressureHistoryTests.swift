//
//  PressureHistoryTests.swift
//  TriangulumTests
//
//  Tests for Category 1 features: Sensor Graphs and Pressure Trends
//

import Testing
import Foundation
import SwiftData
@testable import Triangulum

// MARK: - PressureTrend Tests

struct PressureTrendTests {

    @Test func testTrendSymbols() {
        #expect(PressureTrend.risingFast.symbol == "↑↑")
        #expect(PressureTrend.rising.symbol == "↑")
        #expect(PressureTrend.steady.symbol == "→")
        #expect(PressureTrend.falling.symbol == "↓")
        #expect(PressureTrend.fallingFast.symbol == "↓↓")
        #expect(PressureTrend.unknown.symbol == "?")
    }

    @Test func testTrendPredictions() {
        #expect(PressureTrend.risingFast.prediction == "Clearing, fair weather ahead")
        #expect(PressureTrend.rising.prediction == "Weather improving")
        #expect(PressureTrend.steady.prediction == "Stable conditions")
        #expect(PressureTrend.falling.prediction == "Weather deteriorating")
        #expect(PressureTrend.fallingFast.prediction == "Storm approaching")
        #expect(PressureTrend.unknown.prediction == "Collecting data...")
    }

    @Test func testTrendSystemImages() {
        #expect(PressureTrend.risingFast.systemImage == "arrow.up.circle.fill")
        #expect(PressureTrend.rising.systemImage == "arrow.up.circle")
        #expect(PressureTrend.steady.systemImage == "arrow.right.circle")
        #expect(PressureTrend.falling.systemImage == "arrow.down.circle")
        #expect(PressureTrend.fallingFast.systemImage == "arrow.down.circle.fill")
        #expect(PressureTrend.unknown.systemImage == "questionmark.circle")
    }

    @Test func testTrendRawValues() {
        #expect(PressureTrend.risingFast.rawValue == "rising_fast")
        #expect(PressureTrend.rising.rawValue == "rising")
        #expect(PressureTrend.steady.rawValue == "steady")
        #expect(PressureTrend.falling.rawValue == "falling")
        #expect(PressureTrend.fallingFast.rawValue == "falling_fast")
        #expect(PressureTrend.unknown.rawValue == "unknown")
    }
}

// MARK: - TimeRange Tests

struct TimeRangeTests {

    @Test func testTimeRangeSeconds() {
        #expect(TimeRange.oneHour.seconds == 3600)
        #expect(TimeRange.sixHours.seconds == 21600)
        #expect(TimeRange.oneDay.seconds == 86400)
        #expect(TimeRange.sevenDays.seconds == 604800)
    }

    @Test func testTimeRangeDisplayNames() {
        #expect(TimeRange.oneHour.displayName == "1 Hour")
        #expect(TimeRange.sixHours.displayName == "6 Hours")
        #expect(TimeRange.oneDay.displayName == "24 Hours")
        #expect(TimeRange.sevenDays.displayName == "7 Days")
    }

    @Test func testTimeRangeRawValues() {
        #expect(TimeRange.oneHour.rawValue == "1H")
        #expect(TimeRange.sixHours.rawValue == "6H")
        #expect(TimeRange.oneDay.rawValue == "24H")
        #expect(TimeRange.sevenDays.rawValue == "7D")
    }

    @Test func testTimeRangeAllCases() {
        let allCases = TimeRange.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.oneHour))
        #expect(allCases.contains(.sixHours))
        #expect(allCases.contains(.oneDay))
        #expect(allCases.contains(.sevenDays))
    }
}

// MARK: - PressureStatistics Tests

struct PressureStatisticsTests {

    @Test func testEmptyStatistics() {
        let empty = PressureStatistics.empty

        #expect(empty.minPressure == 0)
        #expect(empty.maxPressure == 0)
        #expect(empty.avgPressure == 0)
        #expect(empty.minAltitude == 0)
        #expect(empty.maxAltitude == 0)
        #expect(empty.avgAltitude == 0)
        #expect(empty.dataPointCount == 0)
    }

    @Test func testStatisticsInitialization() {
        let stats = PressureStatistics(
            minPressure: 100.0,
            maxPressure: 105.0,
            avgPressure: 102.5,
            minAltitude: 50.0,
            maxAltitude: 150.0,
            avgAltitude: 100.0,
            dataPointCount: 10
        )

        #expect(stats != nil)
        guard let stats else {
            return
        }
        #expect(stats.minPressure == 100.0)
        #expect(stats.maxPressure == 105.0)
        #expect(stats.avgPressure == 102.5)
        #expect(stats.minAltitude == 50.0)
        #expect(stats.maxAltitude == 150.0)
        #expect(stats.avgAltitude == 100.0)
        #expect(stats.dataPointCount == 10)
    }

    @Test func testStatisticsFailsWhenMinPressureExceedsMax() {
        // minPressure > maxPressure violates the invariant guarded by the failable initializer
        let stats = PressureStatistics(
            minPressure: 110.0,
            maxPressure: 100.0,
            avgPressure: 105.0,
            minAltitude: 50.0,
            maxAltitude: 150.0,
            avgAltitude: 100.0,
            dataPointCount: 5
        )

        #expect(stats == nil)
    }

    @Test func testStatisticsFailsWhenAvgPressureBelowMin() {
        // avgPressure < minPressure violates the invariant guarded by the failable initializer
        let stats = PressureStatistics(
            minPressure: 100.0,
            maxPressure: 105.0,
            avgPressure: 95.0,
            minAltitude: 50.0,
            maxAltitude: 150.0,
            avgAltitude: 100.0,
            dataPointCount: 5
        )

        #expect(stats == nil)
    }

    @Test func testStatisticsFailsWhenAvgPressureAboveMax() {
        // avgPressure > maxPressure violates the invariant guarded by the failable initializer
        let stats = PressureStatistics(
            minPressure: 100.0,
            maxPressure: 105.0,
            avgPressure: 110.0,
            minAltitude: 50.0,
            maxAltitude: 150.0,
            avgAltitude: 100.0,
            dataPointCount: 5
        )

        #expect(stats == nil)
    }

    @Test func testStatisticsFailsWhenMinAltitudeGreaterThanMaxAltitude() {
        // minAltitude > maxAltitude violates the altitude invariant
        let stats = PressureStatistics(
            minPressure: 100.0,
            maxPressure: 105.0,
            avgPressure: 102.5,
            minAltitude: 200.0,
            maxAltitude: 100.0,
            avgAltitude: 150.0,
            dataPointCount: 5
        )

        #expect(stats == nil)
    }

    @Test func testStatisticsFailsWhenAvgAltitudeBelowMin() {
        // avgAltitude < minAltitude violates the altitude invariant
        let stats = PressureStatistics(
            minPressure: 100.0,
            maxPressure: 105.0,
            avgPressure: 102.5,
            minAltitude: 50.0,
            maxAltitude: 150.0,
            avgAltitude: 30.0,
            dataPointCount: 5
        )

        #expect(stats == nil)
    }

    @Test func testStatisticsFailsWhenAvgAltitudeAboveMax() {
        // avgAltitude > maxAltitude violates the altitude invariant
        let stats = PressureStatistics(
            minPressure: 100.0,
            maxPressure: 105.0,
            avgPressure: 102.5,
            minAltitude: 50.0,
            maxAltitude: 150.0,
            avgAltitude: 200.0,
            dataPointCount: 5
        )

        #expect(stats == nil)
    }
}

// MARK: - PressureReading Model Tests

struct PressureReadingTests {

    @Test func testPressureReadingInitialization() {
        let now = Date()
        let reading = PressureReading(
            timestamp: now,
            pressure: 101.325,
            altitude: 100.0,
            seaLevelPressure: 102.5
        )

        #expect(reading.timestamp == now)
        #expect(reading.pressure == 101.325)
        #expect(reading.altitude == 100.0)
        #expect(reading.seaLevelPressure == 102.5)
    }

    @Test func testPressureReadingDefaultTimestamp() {
        let beforeCreation = Date()
        let reading = PressureReading(
            pressure: 101.0,
            altitude: 50.0,
            seaLevelPressure: 101.5
        )
        let afterCreation = Date()

        #expect(reading.timestamp >= beforeCreation)
        #expect(reading.timestamp <= afterCreation)
    }

    @Test func testPressureReadingWithZeroAltitude() {
        // Zero altitude is valid (sea level)
        let reading = PressureReading(
            pressure: 101.325,
            altitude: 0.0,
            seaLevelPressure: 101.325
        )

        #expect(reading.altitude == 0.0)
        #expect(reading.pressure == 101.325)
    }

    @Test func testPressureReadingWithNegativeAltitude() {
        let reading = PressureReading(
            pressure: 103.0,
            altitude: -50.0,
            seaLevelPressure: 102.5
        )

        #expect(reading.altitude == -50.0)
    }

    @Test func testPressureReadingWithExtremeValues() {
        // Test with high altitude (like Everest)
        let highAltitudeReading = PressureReading(
            pressure: 33.0,
            altitude: 8848.0,
            seaLevelPressure: 101.325
        )

        #expect(highAltitudeReading.pressure == 33.0)
        #expect(highAltitudeReading.altitude == 8848.0)

        // Test with low pressure
        let lowPressureReading = PressureReading(
            pressure: 90.0,
            altitude: 1000.0,
            seaLevelPressure: 101.325
        )

        #expect(lowPressureReading.pressure == 90.0)
    }
}

// MARK: - PressureHistoryManager Tests

@MainActor
@Suite(.serialized)
struct PressureHistoryManagerTests {

    // Helper to create an in-memory SwiftData context for testing
    private func createTestModelContext() throws -> ModelContext {
        let schema = Schema([PressureReading.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func testManagerInitialization() {
        let manager = PressureHistoryManager()

        #expect(manager.trend == .unknown)
        #expect(manager.changeRate == 0.0)
        #expect(manager.statistics.dataPointCount == 0)
        #expect(manager.recentReadings.isEmpty)
    }

    @Test func testManagerConfiguration() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()

        manager.configure(with: context)

        // After configuration, manager should still have unknown trend (no data yet)
        #expect(manager.trend == .unknown)
    }

    @Test func testRecordReading() async throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        try await manager.recordReading(
            pressure: 101.325,
            altitude: 100.0,
            seaLevelPressure: 102.5
        )

        #expect(manager.recentReadings.count == 1)
        #expect(manager.recentReadings.first?.pressure == 101.325)
    }

    @Test func testRecordReadingMinimumInterval() async throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Record first reading
        try await manager.recordReading(pressure: 101.0, altitude: 100.0, seaLevelPressure: 102.0)

        // Try to record immediately - should be ignored due to minimum interval
        try await manager.recordReading(pressure: 102.0, altitude: 100.0, seaLevelPressure: 103.0)

        // Should still have only one reading
        #expect(manager.recentReadings.count == 1)
        #expect(manager.recentReadings.first?.pressure == 101.0)
    }

    @Test func testFetchReadingsEmptyDatabase() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let readings = manager.fetchReadings(for: .oneHour)

        #expect(readings.isEmpty)
    }

    @Test func testFetchReadingsWithData() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Add readings directly to context for testing
        let now = Date()
        for index in 0..<5 {
            let reading = PressureReading(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                pressure: 101.0 + Double(index) * 0.1,
                altitude: 100.0,
                seaLevelPressure: 102.0
            )
            context.insert(reading)
        }
        try context.save()

        let readings = manager.fetchReadings(for: .oneHour)

        #expect(readings.count == 5)
    }

    @Test func testLoadRecentReadings() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Add readings directly to context
        let now = Date()
        for index in 0..<3 {
            let reading = PressureReading(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                pressure: 100.0 + Double(index),
                altitude: 50.0 + Double(index * 10),
                seaLevelPressure: 101.0
            )
            context.insert(reading)
        }
        try context.save()

        manager.loadRecentReadings(for: .oneHour)

        #expect(manager.recentReadings.count == 3)
        #expect(manager.statistics.dataPointCount == 3)
    }

    @Test func testStatisticsCalculation() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Add readings with known values
        // Note: Statistics use seaLevelPressure (not raw pressure) for weather analysis
        let now = Date()
        let rawPressures = [99.0, 100.0, 101.0]  // Raw pressure values (not used in stats)
        let seaLevelPressures = [100.0, 102.0, 104.0]  // Sea level pressure (used in stats)
        let altitudes = [50.0, 100.0, 150.0]

        for index in 0..<3 {
            let reading = PressureReading(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                pressure: rawPressures[index],
                altitude: altitudes[index],
                seaLevelPressure: seaLevelPressures[index]
            )
            context.insert(reading)
        }
        try context.save()

        manager.loadRecentReadings(for: .oneHour)

        // Statistics should use seaLevelPressure values, NOT raw pressure values
        #expect(manager.statistics.minPressure == 100.0)  // min of seaLevelPressures
        #expect(manager.statistics.maxPressure == 104.0)  // max of seaLevelPressures
        #expect(manager.statistics.avgPressure == 102.0)  // avg of seaLevelPressures
        #expect(manager.statistics.minAltitude == 50.0)
        #expect(manager.statistics.maxAltitude == 150.0)
        #expect(manager.statistics.avgAltitude == 100.0)
        #expect(manager.statistics.dataPointCount == 3)
    }

    @Test func testStatisticsUsesSeaLevelPressureNotRawPressure() throws {
        // Explicitly verify that statistics use seaLevelPressure, not raw pressure
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let now = Date()
        // Raw pressures are very different from sea level pressures
        let reading = PressureReading(
            timestamp: now,
            pressure: 90.0,  // Raw pressure (e.g., at high altitude)
            altitude: 1000.0,
            seaLevelPressure: 101.325  // Sea level adjusted
        )
        context.insert(reading)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)

        // Statistics should show seaLevelPressure (101.325), NOT raw pressure (90.0)
        #expect(manager.statistics.minPressure == 101.325)
        #expect(manager.statistics.maxPressure == 101.325)
        #expect(manager.statistics.avgPressure == 101.325)
    }
}
