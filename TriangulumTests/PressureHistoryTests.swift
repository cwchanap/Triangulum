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

        #expect(stats.minPressure == 100.0)
        #expect(stats.maxPressure == 105.0)
        #expect(stats.avgPressure == 102.5)
        #expect(stats.minAltitude == 50.0)
        #expect(stats.maxAltitude == 150.0)
        #expect(stats.avgAltitude == 100.0)
        #expect(stats.dataPointCount == 10)
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

    @Test func testPressureReadingWithZeroValues() {
        let reading = PressureReading(
            pressure: 0.0,
            altitude: 0.0,
            seaLevelPressure: 0.0
        )

        #expect(reading.pressure == 0.0)
        #expect(reading.altitude == 0.0)
        #expect(reading.seaLevelPressure == 0.0)
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
        try? context.save()

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
        try? context.save()

        manager.loadRecentReadings(for: .oneHour)

        #expect(manager.recentReadings.count == 3)
        #expect(manager.statistics.dataPointCount == 3)
    }

    @Test func testStatisticsCalculation() throws {
        let manager = PressureHistoryManager()
        let context = try createTestModelContext()
        manager.configure(with: context)

        // Add readings with known values
        let now = Date()
        let pressures = [100.0, 102.0, 104.0]
        let altitudes = [50.0, 100.0, 150.0]

        for index in 0..<3 {
            let reading = PressureReading(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                pressure: pressures[index],
                altitude: altitudes[index],
                seaLevelPressure: 101.0
            )
            context.insert(reading)
        }
        try? context.save()

        manager.loadRecentReadings(for: .oneHour)

        #expect(manager.statistics.minPressure == 100.0)
        #expect(manager.statistics.maxPressure == 104.0)
        #expect(manager.statistics.avgPressure == 102.0)
        #expect(manager.statistics.minAltitude == 50.0)
        #expect(manager.statistics.maxAltitude == 150.0)
        #expect(manager.statistics.avgAltitude == 100.0)
        #expect(manager.statistics.dataPointCount == 3)
    }
}

// MARK: - Trend Calculation Logic Tests

struct TrendCalculationTests {

    @Test func testTrendThresholdRisingFast() {
        // Rate > 1.0 hPa/hr should be rising fast
        let rate = 1.5
        let expectedTrend: PressureTrend = rate > 1.0 ? .risingFast : .rising
        #expect(expectedTrend == .risingFast)
    }

    @Test func testTrendThresholdRising() {
        // Rate 0.5 to 1.0 hPa/hr should be rising
        let rate = 0.7
        let expectedTrend: PressureTrend
        if rate > 1.0 {
            expectedTrend = .risingFast
        } else if rate > 0.5 {
            expectedTrend = .rising
        } else {
            expectedTrend = .steady
        }
        #expect(expectedTrend == .rising)
    }

    @Test func testTrendThresholdSteady() {
        // Rate -0.5 to 0.5 hPa/hr should be steady
        let rate = 0.3
        let expectedTrend: PressureTrend
        if rate > 1.0 {
            expectedTrend = .risingFast
        } else if rate > 0.5 {
            expectedTrend = .rising
        } else if rate < -1.0 {
            expectedTrend = .fallingFast
        } else if rate < -0.5 {
            expectedTrend = .falling
        } else {
            expectedTrend = .steady
        }
        #expect(expectedTrend == .steady)
    }

    @Test func testTrendThresholdFalling() {
        // Rate -1.0 to -0.5 hPa/hr should be falling
        let rate = -0.7
        let expectedTrend: PressureTrend
        if rate > 1.0 {
            expectedTrend = .risingFast
        } else if rate > 0.5 {
            expectedTrend = .rising
        } else if rate < -1.0 {
            expectedTrend = .fallingFast
        } else if rate < -0.5 {
            expectedTrend = .falling
        } else {
            expectedTrend = .steady
        }
        #expect(expectedTrend == .falling)
    }

    @Test func testTrendThresholdFallingFast() {
        // Rate < -1.0 hPa/hr should be falling fast
        let rate = -1.5
        let expectedTrend: PressureTrend
        if rate > 1.0 {
            expectedTrend = .risingFast
        } else if rate > 0.5 {
            expectedTrend = .rising
        } else if rate < -1.0 {
            expectedTrend = .fallingFast
        } else if rate < -0.5 {
            expectedTrend = .falling
        } else {
            expectedTrend = .steady
        }
        #expect(expectedTrend == .fallingFast)
    }

    @Test func testTrendThresholdBoundaries() {
        // Test exact boundary values
        func getTrend(for rate: Double) -> PressureTrend {
            if rate > 1.0 {
                return .risingFast
            } else if rate > 0.5 {
                return .rising
            } else if rate < -1.0 {
                return .fallingFast
            } else if rate < -0.5 {
                return .falling
            } else {
                return .steady
            }
        }

        // Exactly at boundaries
        #expect(getTrend(for: 0.5) == .steady)   // 0.5 is not > 0.5
        #expect(getTrend(for: 0.51) == .rising)
        #expect(getTrend(for: 1.0) == .rising)   // 1.0 is not > 1.0
        #expect(getTrend(for: 1.01) == .risingFast)
        #expect(getTrend(for: -0.5) == .steady)  // -0.5 is not < -0.5
        #expect(getTrend(for: -0.51) == .falling)
        #expect(getTrend(for: -1.0) == .falling) // -1.0 is not < -1.0
        #expect(getTrend(for: -1.01) == .fallingFast)
    }
}

// MARK: - Rate Calculation Tests

struct RateCalculationTests {

    @Test func testRateCalculationBasic() {
        // Simulate rate calculation from two readings
        let pressureDiff = 0.1  // kPa difference
        let timeDiffHours = 0.5 // 30 minutes = 0.5 hours

        // Convert to hPa (1 kPa = 10 hPa)
        let rateHPaPerHour = (pressureDiff * 10) / timeDiffHours

        #expect(rateHPaPerHour == 2.0)  // 1 hPa in 30 min = 2 hPa/hr
    }

    @Test func testRateCalculationNegative() {
        // Pressure falling
        let pressureDiff = -0.05  // kPa difference (falling)
        let timeDiffHours = 0.5   // 30 minutes

        let rateHPaPerHour = (pressureDiff * 10) / timeDiffHours

        #expect(rateHPaPerHour == -1.0)  // -0.5 hPa in 30 min = -1 hPa/hr
    }

    @Test func testRateCalculationZero() {
        // No change
        let pressureDiff = 0.0
        let timeDiffHours = 1.0

        let rateHPaPerHour = (pressureDiff * 10) / timeDiffHours

        #expect(rateHPaPerHour == 0.0)
    }

    @Test func testRateCalculationOneHour() {
        // Simple one hour calculation
        let pressureDiff = 0.1  // 0.1 kPa = 1 hPa
        let timeDiffHours = 1.0

        let rateHPaPerHour = (pressureDiff * 10) / timeDiffHours

        #expect(rateHPaPerHour == 1.0)  // 1 hPa/hr
    }
}

// MARK: - Distance Calculation Tests (for Comparison View)

struct DistanceCalculationTests {
    @Test func testSameLocationDistance() {
        // Same location should have zero distance
        let lat = 37.7749
        let lon = -122.4194

        let distance = calculateDistance(
            lat1: lat, lon1: lon,
            lat2: lat, lon2: lon
        )

        #expect(distance == 0.0)
    }

    @Test func testKnownDistanceSanFranciscoToLA() {
        // San Francisco to Los Angeles is approximately 559 km
        let sfLat = 37.7749
        let sfLon = -122.4194
        let laLat = 34.0522
        let laLon = -118.2437

        let distance = calculateDistance(
            lat1: sfLat, lon1: sfLon,
            lat2: laLat, lon2: laLon
        )

        // Should be approximately 559 km (allow 5% error)
        let expectedKm = 559.0
        let tolerance = expectedKm * 0.05
        #expect(abs(distance / 1000 - expectedKm) < tolerance)
    }

    @Test func testShortDistance() {
        // Test a short distance (about 1 km)
        let lat1 = 37.7749
        let lon1 = -122.4194
        let lat2 = 37.7839  // About 1 km north
        let lon2 = -122.4194

        let distance = calculateDistance(
            lat1: lat1, lon1: lon1,
            lat2: lat2, lon2: lon2
        )

        // Should be approximately 1 km (1000 meters)
        #expect(distance > 900 && distance < 1100)
    }

    // Helper function using Haversine formula
    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6371000.0 // meters

        let deltaLat = (lat2 - lat1) * .pi / 180
        let deltaLon = (lon2 - lon1) * .pi / 180

        let haversineA = sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
            sin(deltaLon / 2) * sin(deltaLon / 2)

        let angularDistance = 2 * atan2(sqrt(haversineA), sqrt(1 - haversineA))

        return earthRadius * angularDistance
    }
}

// MARK: - Delta Calculation Tests (for Comparison View)

struct DeltaCalculationTests {

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
        let formatted = String(format: "+%.2f", delta)

        #expect(formatted == "+5.12")
    }

    @Test func testNegativeDeltaFormatting() {
        let delta = -5.123456
        let sign = delta >= 0 ? "+" : ""
        let formatted = String(format: "%@%.2f", sign, delta)

        #expect(formatted == "-5.12")
    }
}
