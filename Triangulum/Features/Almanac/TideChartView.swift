//
//  TideChartView.swift
//  Triangulum
//

import Charts
import SwiftUI

// MARK: - Pure projections

extension TideDay {
    /// The first exact event strictly after `instant` (receiver order is the
    /// provider's chronological event order), or nil once all events passed.
    func nextEvent(after instant: Date) -> TideEvent? {
        events.first { $0.instant > instant }
    }
}

extension TideEventKind {
    /// Visible label for high/low waters (rows, chart, summaries).
    var displayName: String {
        switch self {
        case .high: "High"
        case .low: "Low"
        }
    }
}

// MARK: - TideChartView

/// One daily tide graph with only official points: the provider's hourly
/// samples as a default/linear line and the exact high/low events as
/// independent markers (triangle up for high water, triangle down for low —
/// shape and colour, not colour alone). No Catmull-Rom interpolation, no
/// `AreaMark` fill, no synthetic sub-hour precision.
struct TideChartView: View {
    let day: TideDay
    let timeZone: TimeZone
    /// Drawn as a dashed current-time rule only for today (nil otherwise).
    var now: Date?
    var height: CGFloat = 180

    private var dayStart: Date { (try? day.localDate.start(in: timeZone)) ?? .distantPast }
    private var dayEnd: Date { (try? day.localDate.endExclusive(in: timeZone)) ?? .distantFuture }

    /// Metre labels for rows and summaries, one decimal.
    static func heightText(_ metres: Double) -> String {
        String(format: "%.1f m", metres)
    }

    /// One VoiceOver-readable projection of the daily chart: date, height
    /// range, and the exact events in chronological order. The chart's
    /// accessibility label is this summary; exact copy is asserted through
    /// this pure helper (SwiftUI's accessibility tree is not materialized
    /// synchronously through the unit-test render seam).
    static func accessibilitySummary(
        samples: [TideSample],
        events: [TideEvent],
        timeZone: TimeZone
    ) -> String {
        var parts: [String] = []
        if let firstInstant = samples.first?.instant ?? events.first?.instant {
            parts.append("Tide chart for \(AlmanacText.fullDateText(firstInstant, in: timeZone)).")
        }

        // The range covers every rendered chart point: hourly samples AND
        // the exact high/low event markers.
        let heights = samples.map(\.heightMetres) + events.map(\.heightMetres)
        if let low = heights.min(), let high = heights.max() {
            parts.append(String(format: "Heights from %.1f to %.1f metres.", low, high))
        }

        for event in events.sorted(by: { $0.instant < $1.instant }) {
            parts.append(
                String(
                    format: "%@ water %.1f metres at %@.",
                    event.kind.displayName,
                    event.heightMetres,
                    AlmanacText.clockText(event.instant, in: timeZone)
                )
            )
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Chart {
            ForEach(day.hourlySamples, id: \.instant) { sample in
                LineMark(
                    x: .value("Time", sample.instant),
                    y: .value("Height", sample.heightMetres)
                )
                .foregroundStyle(Color.celCyan.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(day.events, id: \.instant) { event in
                PointMark(
                    x: .value("Time", event.instant),
                    y: .value("Height", event.heightMetres)
                )
                .symbol(event.kind == .high ? AnyChartSymbolShape(.triangle) : AnyChartSymbolShape(DownTriangleSymbol()))
                .foregroundStyle(event.kind == .high ? Color.celCyan : Color.celGold)
                .symbolSize(80)
            }
            if let now, now >= dayStart, now <= dayEnd {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(Color.celViolet.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(Color.celGrid)
                if let instant = value.as(Date.self) {
                    AxisValueLabel {
                        Text(AlmanacText.clockText(instant, in: timeZone))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.celTextDim)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.celGrid)
                AxisValueLabel()
            }
        }
        .chartYScale(domain: yDomain)
        .frame(height: height)
        .accessibilityLabel(
            Self.accessibilitySummary(samples: day.hourlySamples, events: day.events, timeZone: timeZone)
        )
    }

    private var yDomain: ClosedRange<Double> {
        let values = day.hourlySamples.map(\.heightMetres) + day.events.map(\.heightMetres)
        guard let min = values.min(), let max = values.max(), max - min > 0.001 else {
            return 0...5
        }
        let padding = (max - min) * 0.18
        return (min - padding)...(max + padding)
    }
}

// MARK: - Low-water marker

/// The built-in `.triangle` points up (high water); lows get an inverted
/// triangle so the two shapes differ at a glance.
private struct DownTriangleSymbol: ChartSymbolShape {
    var perceptualUnitRect: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
