import SwiftUI
import Charts

struct BarometerDetailView: View {
    @ObservedObject var barometerManager: BarometerManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTimeRange: TimeRange = .oneHour

    private var historyManager: PressureHistoryManager? {
        barometerManager.historyManager
    }

    private var readings: [PressureReading] {
        guard let historyManager = historyManager else { return [] }
        let cutoffDate = Date().addingTimeInterval(-selectedTimeRange.seconds)
        return historyManager.recentReadings.filter { $0.timestamp > cutoffDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current readings card
                    currentReadingsCard

                    // Time range picker
                    timeRangePicker

                    // Pressure chart
                    pressureChartCard

                    // Altitude chart
                    altitudeChartCard

                    // Statistics card
                    statisticsCard
                }
                .padding()
            }
            .background(Color.prussianSoft.opacity(0.3))
            .navigationTitle("Pressure History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.prussianAccent)
                }
            }
            .onAppear {
                historyManager?.loadRecentReadings(for: selectedTimeRange)
            }
            .onChange(of: selectedTimeRange) { _, _ in
                historyManager?.loadRecentReadings(for: selectedTimeRange)
            }
        }
    }

    // MARK: - Current Readings Card

    private var currentReadingsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "barometer")
                    .font(.title2)
                    .foregroundColor(.prussianAccent)
                Text("Current Reading")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Pressure")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text("\(barometerManager.pressure, specifier: "%.2f") kPa")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.prussianBlueDark)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Sea Level")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text("\(barometerManager.seaLevelPressure, specifier: "%.2f") kPa")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.prussianBlueDark)
                }
            }

            // Trend indicator
            if let historyManager = historyManager {
                TrendIndicatorView(historyManager: historyManager)
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Pressure Chart

    private var pressureChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundColor(.prussianAccent)
                Text("Pressure")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                Text("kPa")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }

            if readings.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(readings) { reading in
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Pressure", reading.pressure)
                    )
                    .foregroundStyle(Color.prussianAccent)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Pressure", reading.pressure)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.prussianAccent.opacity(0.3), Color.prussianAccent.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: pressureYDomain)
                .frame(height: 200)
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Altitude Chart

    private var altitudeChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mountain.2")
                    .foregroundColor(.prussianSuccess)
                Text("Altitude")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                Text("meters")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }

            if readings.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(readings) { reading in
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Altitude", reading.altitude)
                    )
                    .foregroundStyle(Color.prussianSuccess)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Altitude", reading.altitude)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.prussianSuccess.opacity(0.3), Color.prussianSuccess.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: altitudeYDomain)
                .frame(height: 200)
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Statistics Card

    private var statisticsCard: some View {
        let stats = PressureHistoryManager.calculateStatistics(for: readings)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(.prussianAccent)
                Text("Statistics")
                    .font(.headline)
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                Text("\(stats.dataPointCount) readings")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }

            if stats.dataPointCount == 0 {
                Text("No data available for selected time range")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                HStack(spacing: 0) {
                    // Pressure statistics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sea-level Pressure (kPa)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.prussianBlueLight)

                        StatRow(label: "Min", value: String(format: "%.2f", stats.minPressure))
                        StatRow(label: "Max", value: String(format: "%.2f", stats.maxPressure))
                        StatRow(label: "Avg", value: String(format: "%.2f", stats.avgPressure))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .frame(height: 80)

                    // Altitude statistics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Altitude (m)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.prussianBlueLight)

                        StatRow(label: "Min", value: String(format: "%.1f", stats.minAltitude))
                        StatRow(label: "Max", value: String(format: "%.1f", stats.maxAltitude))
                        StatRow(label: "Avg", value: String(format: "%.1f", stats.avgAltitude))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                }
            }
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Helper Views

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundColor(.prussianBlueLight.opacity(0.5))
            Text("No data available")
                .font(.caption)
                .foregroundColor(.prussianBlueLight)
            Text("Data will appear as readings are collected")
                .font(.caption2)
                .foregroundColor(.prussianBlueLight.opacity(0.7))
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color.white, Color.prussianSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.prussianBlue.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Chart Configuration

    private var xAxisFormat: Date.FormatStyle {
        switch selectedTimeRange {
        case .oneHour, .sixHours:
            return .dateTime.hour().minute()
        case .oneDay:
            return .dateTime.hour()
        case .sevenDays:
            return .dateTime.weekday(.abbreviated)
        }
    }

    private var pressureYDomain: ClosedRange<Double> {
        guard !readings.isEmpty else { return 95...105 }
        let pressures = readings.map { $0.pressure }
        let minP = (pressures.min() ?? 100) - 0.5
        let maxP = (pressures.max() ?? 102) + 0.5
        return minP...maxP
    }

    private var altitudeYDomain: ClosedRange<Double> {
        guard !readings.isEmpty else { return 0...100 }
        let altitudes = readings.map { $0.altitude }
        let minA = (altitudes.min() ?? 0) - 10
        let maxA = (altitudes.max() ?? 100) + 10
        return minA...maxA
    }
}

// MARK: - Stat Row Component

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.prussianBlueLight)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.prussianBlueDark)
        }
    }
}

#Preview {
    let manager = BarometerManager(locationManager: LocationManager())
    manager.pressure = 101.325
    manager.seaLevelPressure = 103.2
    manager.isAvailable = true

    return BarometerDetailView(barometerManager: manager)
}
