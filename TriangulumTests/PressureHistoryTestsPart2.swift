//
//  PressureHistoryTestsPart2.swift
//  TriangulumTests
//
//  Tests for Category 1 features: Sensor Graphs and Pressure Trends (Part 2)
//

import Testing
import Foundation
import SwiftData
@testable import Triangulum

// MARK: - Trend Calculation Integration Tests

@MainActor
@Suite(.serialized)
struct TrendCalculationIntegrationTests {

    // Helper to create an in-memory SwiftData context for testing
    private func createTestModelContext() throws -> ModelContext {
        let schema = Schema([PressureReading.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func testTrendCalculationRisingFast() throws {
        // Test that actual PressureHistoryManager calculates rising fast trend correctly
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Insert readings spanning 31 minutes with rising seaLevelPressure
        // Note: calculateTrend() only fetches from last 35 min (30 + 5 buffer)
        // Readings must be within that window but span at least 30 minutes
        let now = Date()
        let reading1 = PressureReading(timestamp: now.addingTimeInterval(-31 * 60), pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)
        let reading2 = PressureReading(timestamp: now.addingTimeInterval(-30 * 60), pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)
        let reading3 = PressureReading(timestamp: now.addingTimeInterval(-1 * 60), pressure: 102.0, altitude: 100.0, seaLevelPressure: 102.5)

        context.insert(reading1)
        context.insert(reading2)
        context.insert(reading3)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .risingFast)
    }

    @Test func testTrendCalculationRising() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let now = Date()
        // Small rise (~0.8 hPa/hour) should be "rising"
        let reading1 = PressureReading(timestamp: now.addingTimeInterval(-31 * 60), pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)
        let reading2 = PressureReading(timestamp: now.addingTimeInterval(-30 * 60), pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)
        let reading3 = PressureReading(timestamp: now.addingTimeInterval(-1 * 60), pressure: 101.02, altitude: 100.0, seaLevelPressure: 101.04)

        context.insert(reading1)
        context.insert(reading2)
        context.insert(reading3)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .rising)
    }

    @Test func testTrendCalculationSteady() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let now = Date()
        // Tiny change (~0.2 hPa/hour) should be "steady"
        let reading1 = PressureReading(timestamp: now.addingTimeInterval(-31 * 60), pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)
        let reading2 = PressureReading(timestamp: now.addingTimeInterval(-30 * 60), pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)
        let reading3 = PressureReading(timestamp: now.addingTimeInterval(-1 * 60), pressure: 101.01, altitude: 100.0, seaLevelPressure: 101.01)

        context.insert(reading1)
        context.insert(reading2)
        context.insert(reading3)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .steady)
    }

    @Test func testTrendCalculationFalling() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let now = Date()
        // Small drop (~-0.8 hPa/hour) should be "falling"
        let reading1 = PressureReading(timestamp: now.addingTimeInterval(-31 * 60), pressure: 102.0, altitude: 100.0, seaLevelPressure: 102.0)
        let reading2 = PressureReading(timestamp: now.addingTimeInterval(-30 * 60), pressure: 102.0, altitude: 100.0, seaLevelPressure: 102.0)
        let reading3 = PressureReading(timestamp: now.addingTimeInterval(-1 * 60), pressure: 101.98, altitude: 100.0, seaLevelPressure: 101.96)

        context.insert(reading1)
        context.insert(reading2)
        context.insert(reading3)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .falling)
    }

    @Test func testTrendCalculationFallingFast() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let now = Date()
        // Over 3 mb drop in 30 minutes - should be "falling fast"
        let reading1 = PressureReading(timestamp: now.addingTimeInterval(-31 * 60), pressure: 103.0, altitude: 100.0, seaLevelPressure: 103.0)
        let reading2 = PressureReading(timestamp: now.addingTimeInterval(-30 * 60), pressure: 103.0, altitude: 100.0, seaLevelPressure: 103.0)
        let reading3 = PressureReading(timestamp: now.addingTimeInterval(-1 * 60), pressure: 102.0, altitude: 100.0, seaLevelPressure: 101.5)

        context.insert(reading1)
        context.insert(reading2)
        context.insert(reading3)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .fallingFast)
    }

    @Test func testTrendCalculationNotEnoughData() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Only one reading - not enough for trend calculation
        let now = Date()
        let reading1 = PressureReading(timestamp: now, pressure: 101.0, altitude: 100.0, seaLevelPressure: 101.0)

        context.insert(reading1)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .unknown)
    }

    @Test func testTrendCalculationDataOutsideWindow() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        let now = Date()
        // Readings from more than 35 minutes ago should be ignored
        let reading1 = PressureReading(timestamp: now.addingTimeInterval(-40 * 60), pressure: 98.0, altitude: 100.0, seaLevelPressure: 98.0)
        let reading2 = PressureReading(timestamp: now.addingTimeInterval(-36 * 60), pressure: 99.0, altitude: 100.0, seaLevelPressure: 99.0)

        context.insert(reading1)
        context.insert(reading2)
        try context.save()

        manager.loadRecentReadings(for: .oneHour)
        let trend = manager.calculateTrend()

        #expect(trend == .unknown)
    }
}

// MARK: - Delta Calculation Tests (for Comparison View)

struct DeltaCalculationTests {

    private func formatDelta(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : ""
        return String(format: "%@%.2f", sign, delta)
    }

    @Test func testPositiveDelta() {
        let value1 = 100.0
        let value2 = 105.0
        let delta = value2 - value1

        #expect(delta == 5.0)
        #expect(delta > 0)
    }

    @Test func testNegativeDelta() {
        let value1 = 105.0
        let value2 = 100.0
        let delta = value2 - value1

        #expect(delta == -5.0)
        #expect(delta < 0)
    }

    @Test func testZeroDelta() {
        let value1 = 100.0
        let value2 = 100.0
        let delta = value2 - value1

        #expect(delta == 0.0)
    }

    @Test func testDeltaFormatting() {
        let delta = 5.123456
        let formatted = formatDelta(delta)

        #expect(formatted == "+5.12")
    }

    @Test func testNegativeDeltaFormatting() {
        let delta = -5.123456
        let formatted = formatDelta(delta)

        #expect(formatted == "-5.12")
    }
}

// MARK: - HistoryError Tests

struct HistoryErrorTests {

    @Test func testModelContextNotConfiguredError() {
        let error = HistoryError.modelContextNotConfigured

        #expect(error.errorDescription == "Model context not configured")
    }

    @Test func testSaveFailedError() {
        let underlyingError = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Test save failure"
        ])
        let error = HistoryError.saveFailed(underlyingError)

        #expect(error.errorDescription?.contains("Failed to save reading") == true)
        #expect(error.errorDescription?.contains("Test save failure") == true)
    }

    @Test func testHistoryErrorIsLocalizedError() {
        let error: LocalizedError = HistoryError.modelContextNotConfigured
        #expect(error.errorDescription != nil)
    }
}

// MARK: - PressureHistoryManager Error Handling Tests

@MainActor
@Suite(.serialized)
struct PressureHistoryManagerErrorTests {

    @Test func testRecordReadingWithoutConfiguration() async {
        let manager = PressureHistoryManager()
        // Don't configure - should throw

        do {
            try await manager.recordReading(
                pressure: 101.325,
                altitude: 100.0,
                seaLevelPressure: 102.5
            )
            // Should not reach here
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as HistoryError {
            switch error {
            case .modelContextNotConfigured:
                #expect(true) // Expected error
            case .saveFailed:
                #expect(Bool(false), "Expected modelContextNotConfigured, got saveFailed")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test func testLoadRecentReadingsWithoutConfiguration() {
        let manager = PressureHistoryManager()
        // Don't configure

        manager.loadRecentReadings(for: .oneHour)

        // Should have empty readings, not crash
        #expect(manager.recentReadings.isEmpty)
    }

    @Test func testCalculateStatisticsWithoutConfiguration() {
        let manager = PressureHistoryManager()
        // Don't configure

        let stats = manager.statistics

        // Should return default/empty statistics
        #expect(stats.dataPointCount == 0)
        #expect(stats.minPressure == 0.0)
        #expect(stats.maxPressure == 0.0)
        #expect(stats.avgPressure == 0.0)
    }

    @Test func testCalculateTrendWithoutConfiguration() {
        let manager = PressureHistoryManager()
        // Don't configure

        let trend = manager.calculateTrend()

        // Should return unknown trend
        #expect(trend == .unknown)
    }
}
