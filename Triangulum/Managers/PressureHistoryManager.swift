import Foundation
import SwiftData
import Combine

/// Errors that can occur during pressure history recording
enum HistoryError: LocalizedError {
    case modelContextNotConfigured
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelContextNotConfigured:
            return "Model context not configured"
        case .saveFailed(let error):
            return "Failed to save reading: \(error.localizedDescription)"
        }
    }
}

/// Pressure trend direction based on rate of change
enum PressureTrend: String {
    case risingFast = "rising_fast"
    case rising = "rising"
    case steady = "steady"
    case falling = "falling"
    case fallingFast = "falling_fast"
    case unknown = "unknown"

    var symbol: String {
        switch self {
        case .risingFast: return "↑↑"
        case .rising: return "↑"
        case .steady: return "→"
        case .falling: return "↓"
        case .fallingFast: return "↓↓"
        case .unknown: return "?"
        }
    }

    var prediction: String {
        switch self {
        case .risingFast: return "Clearing, fair weather ahead"
        case .rising: return "Weather improving"
        case .steady: return "Stable conditions"
        case .falling: return "Weather deteriorating"
        case .fallingFast: return "Storm approaching"
        case .unknown: return "Collecting data..."
        }
    }

    var systemImage: String {
        switch self {
        case .risingFast: return "arrow.up.circle.fill"
        case .rising: return "arrow.up.circle"
        case .steady: return "arrow.right.circle"
        case .falling: return "arrow.down.circle"
        case .fallingFast: return "arrow.down.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Time range for graph display
enum TimeRange: String, CaseIterable {
    case oneHour = "1H"
    case sixHours = "6H"
    case oneDay = "24H"
    case sevenDays = "7D"

    var seconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .sixHours: return 21600
        case .oneDay: return 86400
        case .sevenDays: return 604800
        }
    }

    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .sixHours: return "6 Hours"
        case .oneDay: return "24 Hours"
        case .sevenDays: return "7 Days"
        }
    }
}

/// Statistics for a set of pressure readings
struct PressureStatistics {
    let minPressure: Double
    let maxPressure: Double
    let avgPressure: Double
    let minAltitude: Double
    let maxAltitude: Double
    let avgAltitude: Double
    let dataPointCount: Int

    static let empty = PressureStatistics(
        minPressure: 0, maxPressure: 0, avgPressure: 0,
        minAltitude: 0, maxAltitude: 0, avgAltitude: 0,
        dataPointCount: 0
    )
}

/// Manages historical pressure data collection, storage, and trend analysis
@MainActor
class PressureHistoryManager: ObservableObject {

    // MARK: - Published Properties

    @Published var trend: PressureTrend = .unknown
    @Published var changeRate: Double = 0.0  // hPa per hour
    @Published var statistics: PressureStatistics = .empty
    @Published var recentReadings: [PressureReading] = []
    @Published var fetchError: Error?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var lastRecordedTime: Date?
    private let minimumRecordingInterval: TimeInterval = 60  // 1 minute
    private let minimumTrendDataSeconds: TimeInterval = 30 * 60  // 30 minutes
    private let retentionPeriod: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    // MARK: - Initialization

    init() {}

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        cleanupOldData()
        loadRecentReadings(for: .oneHour)
        calculateTrend()
    }

    // MARK: - Data Recording

    /// Records a new pressure reading if enough time has passed since the last one
    /// - Parameters:
    ///   - pressure: Current pressure reading in kPa (stored as-is)
    ///   - altitude: Altitude in meters (from GPS)
    ///   - seaLevelPressure: Sea-level adjusted pressure in kPa (converted to hPa for trend calculations)
    func recordReading(pressure: Double, altitude: Double, seaLevelPressure: Double) async throws {
        guard let modelContext = modelContext else {
            throw HistoryError.modelContextNotConfigured
        }

        // Check if enough time has passed since last recording
        let now = Date()
        if let lastTime = lastRecordedTime,
           now.timeIntervalSince(lastTime) < minimumRecordingInterval {
            return
        }

        // Create and save new reading
        let reading = PressureReading(
            timestamp: now,
            pressure: pressure,
            altitude: altitude,
            seaLevelPressure: seaLevelPressure
        )

        modelContext.insert(reading)
        do {
            try modelContext.save()
            lastRecordedTime = now
        } catch {
            throw HistoryError.saveFailed(error)
        }

        // Update recent readings and recalculate trend
        recentReadings.append(reading)

        // Remove readings older than retention period from in-memory buffer to prevent unbounded growth
        let retentionCutoff = now.addingTimeInterval(-retentionPeriod)
        recentReadings = recentReadings.filter { $0.timestamp > retentionCutoff }

        calculateTrend()
        calculateStatistics()

        // Periodically clean up old data
        if Int.random(in: 0..<60) == 0 {
            cleanupOldData()
        }
    }

    // MARK: - Data Retrieval

    /// Fetches readings for a specific time range
    /// - Parameter timeRange: The time range to fetch readings for
    /// - Returns: Array of readings, or empty array if context not configured or fetch fails
    func fetchReadings(for timeRange: TimeRange) -> [PressureReading] {
        guard let modelContext = modelContext else {
            print("⚠️ PressureHistoryManager: Cannot fetch readings - context not configured")
            return []
        }

        let cutoffDate = Date().addingTimeInterval(-timeRange.seconds)

        let descriptor = FetchDescriptor<PressureReading>(
            predicate: #Predicate { $0.timestamp > cutoffDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            let results = try modelContext.fetch(descriptor)
            fetchError = nil  // Clear error on successful fetch
            return results
        } catch {
            print("❌ PressureHistoryManager: Failed to fetch readings: \(error.localizedDescription)")
            fetchError = error  // Surface error for UI observability
            return []
        }
    }

    /// Loads recent readings into memory for the specified time range
    func loadRecentReadings(for timeRange: TimeRange) {
        recentReadings = fetchReadings(for: timeRange)
        calculateStatistics()
    }

    // MARK: - Trend Analysis

    /// Calculates the current pressure trend based on recent data
    private func calculateTrend() {
        guard let modelContext = modelContext else {
            trend = .unknown
            changeRate = 0
            return
        }

        // Add a buffer to ensure we capture enough data points spanning the minimum period
        let fetchBufferSeconds: TimeInterval = 300  // 5 minutes buffer
        let fetchStart = Date().addingTimeInterval(-minimumTrendDataSeconds - fetchBufferSeconds)

        let descriptor = FetchDescriptor<PressureReading>(
            predicate: #Predicate { $0.timestamp > fetchStart },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            let readings = try modelContext.fetch(descriptor)

            // Require at least 3 samples for meaningful trend calculation
            guard readings.count >= 3 else {
                trend = .unknown
                changeRate = 0
                return
            }

            // Calculate rate of change in hPa per hour
            guard let first = readings.first, let last = readings.last else {
                trend = .unknown
                changeRate = 0
                return
            }

            let timeDiff = last.timestamp.timeIntervalSince(first.timestamp)
            // Enforce minimum time span before calculating rate
            guard timeDiff >= minimumTrendDataSeconds else {
                trend = .unknown
                changeRate = 0
                return
            }

            // Use seaLevelPressure for weather trends (altitude-normalized)
            let pressureDiff = last.seaLevelPressure - first.seaLevelPressure
            let hoursElapsed = timeDiff / 3600

            // Convert to hPa (1 kPa = 10 hPa)
            let rateHPaPerHour = (pressureDiff * 10) / hoursElapsed
            changeRate = rateHPaPerHour

            // Determine trend based on rate
            // Thresholds in hPa/hour
            if rateHPaPerHour > 1.0 {
                trend = .risingFast
            } else if rateHPaPerHour > 0.5 {
                trend = .rising
            } else if rateHPaPerHour < -1.0 {
                trend = .fallingFast
            } else if rateHPaPerHour < -0.5 {
                trend = .falling
            } else {
                trend = .steady
            }

        } catch {
            print("Failed to calculate trend: \(error)")
            trend = .unknown
            changeRate = 0
        }
    }

    /// Calculates statistics for the current set of readings
    private func calculateStatistics() {
        guard !recentReadings.isEmpty else {
            statistics = .empty
            return
        }

        // Use seaLevelPressure for weather statistics (altitude-normalized)
        let pressures = recentReadings.map { $0.seaLevelPressure }
        let altitudes = recentReadings.map { $0.altitude }

        statistics = PressureStatistics(
            minPressure: pressures.min() ?? 0,
            maxPressure: pressures.max() ?? 0,
            avgPressure: pressures.reduce(0, +) / Double(pressures.count),
            minAltitude: altitudes.min() ?? 0,
            maxAltitude: altitudes.max() ?? 0,
            avgAltitude: altitudes.reduce(0, +) / Double(altitudes.count),
            dataPointCount: recentReadings.count
        )
    }

    // MARK: - Statistics Helpers

    /// Calculates statistics for a given array of pressure readings
    /// - Parameter readings: Array of pressure readings to analyze
    /// - Returns: Statistics calculated from the provided readings
    static func calculateStatistics(for readings: [PressureReading]) -> PressureStatistics {
        guard !readings.isEmpty else {
            return .empty
        }

        // Use seaLevelPressure for weather statistics (altitude-normalized)
        let pressures = readings.map { $0.seaLevelPressure }
        let altitudes = readings.map { $0.altitude }

        return PressureStatistics(
            minPressure: pressures.min() ?? 0,
            maxPressure: pressures.max() ?? 0,
            avgPressure: pressures.reduce(0, +) / Double(pressures.count),
            minAltitude: altitudes.min() ?? 0,
            maxAltitude: altitudes.max() ?? 0,
            avgAltitude: altitudes.reduce(0, +) / Double(altitudes.count),
            dataPointCount: readings.count
        )
    }

    // MARK: - Data Cleanup

    /// Removes readings older than the retention period
    private func cleanupOldData() {
        guard let modelContext = modelContext else {
            print("⚠️ PressureHistoryManager: Cannot cleanup - context not configured")
            return
        }

        let cutoffDate = Date().addingTimeInterval(-retentionPeriod)

        let descriptor = FetchDescriptor<PressureReading>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )

        do {
            let oldReadings = try modelContext.fetch(descriptor)
            for reading in oldReadings {
                modelContext.delete(reading)
            }

            if !oldReadings.isEmpty {
                do {
                    try modelContext.save()
                    print("✓ PressureHistoryManager: Cleaned up \(oldReadings.count) old pressure readings")
                } catch {
                    print("❌ PressureHistoryManager: Failed to save after deletions: \(error.localizedDescription)")
                }
            }
        } catch {
            print("❌ PressureHistoryManager: Failed to cleanup old readings: \(error.localizedDescription)")
        }
    }
}
