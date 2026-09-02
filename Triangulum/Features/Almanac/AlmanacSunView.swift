//
//  AlmanacSunView.swift
//  Triangulum
//

import SwiftUI

/// The Sun section: sunrise/daylight/sunset headline, the explanatory
/// daylight track (civil dawn → civil dusk), typed morning/evening event
/// lists, the next-event countdown (destination-local today only), and
/// explicit polar copy for polar day/night.
struct AlmanacSunView: View {
    @ObservedObject var viewModel: AlmanacViewModel
    /// Render trigger only: every today/countdown judgment reads the view
    /// model's injected clock, so the -ui-testing fixture stays deterministic
    /// and this tick (at most once per minute) keeps production copy fresh.
    @State private var minuteTick = 0

    /// Spec: countdown updates at most once per minute.
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // MARK: - Pure copy

    static let sunriseLabel = "Sunrise"
    static let daylightLabel = "Daylight"
    static let sunsetLabel = "Sunset"
    static let noMoreEventsText = "No more events today."
    static let emptyMorningText = "No morning events today."
    static let emptyEveningText = "No evening events today."
    static let missingTimeText = "—"

    /// "06:24" for a present event, "—" for a crossing that never happens.
    static func timeText(_ instant: Date?, in timeZone: TimeZone) -> String {
        guard let instant else { return missingTimeText }
        return AlmanacText.clockText(instant, in: timeZone)
    }

    /// Daylight duration between sunrise and sunset: "13h 31m". Polar days are
    /// 24h of sun-above-horizon, polar nights none; an unresolvable pair shows
    /// the same missing-time dash as the other headline metrics.
    static func daylightText(sunrise: Date?, sunset: Date?, state: SolarState) -> String {
        switch state {
        case .polarDay: return "24h 00m"
        case .polarNight: return "0h 00m"
        case .normal: break
        }
        guard let sunrise, let sunset else { return missingTimeText }
        let interval = sunset.timeIntervalSince(sunrise)
        guard interval > 0 else { return missingTimeText }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// Explicit polar copy shown under the headline when the Sun never
    /// crosses the −0.833° horizon that day.
    static func polarBannerText(state: SolarState) -> String? {
        switch state {
        case .polarDay: return "Polar day — the sun stays above the horizon all day."
        case .polarNight: return "Polar night — the sun stays below the horizon all day."
        case .normal: return nil
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: CelSpace.md) {
                sectionContent
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CelSpace.md)
            .padding(.top, CelSpace.sm)
            .padding(.bottom, CelSpace.lg)
        }
        .onReceive(minuteTimer) { _ in minuteTick += 1 }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let solarDay = viewModel.solarDay, let timeZone = viewModel.location?.timeZone {
            headlineCard(solarDay: solarDay, timeZone: timeZone)
            if viewModel.today(in: timeZone) == solarDay.date {
                nextEventCard(solarDay: solarDay, timeZone: timeZone)
            }
            DaylightTrackCard(solarDay: solarDay, timeZone: timeZone, now: viewModel.currentDate)
            eventsCard(solarDay: solarDay, timeZone: timeZone, title: "Morning",
                       kinds: Self.morningKinds, emptyText: Self.emptyMorningText)
            eventsCard(solarDay: solarDay, timeZone: timeZone, title: "Evening",
                       kinds: Self.eveningKinds, emptyText: Self.emptyEveningText)
        } else {
            noLocationCard
        }
    }

    // MARK: - Headline

    private func headlineCard(solarDay: SolarDay, timeZone: TimeZone) -> some View {
        VStack(spacing: CelSpace.sm) {
            InstrumentHeader(icon: "sun.max.fill", title: "Sun", tint: .celGold) {
                Text(AlmanacText.dayTitleText(dayStart(solarDay, in: timeZone), in: timeZone))
                    .font(.celTiny)
                    .foregroundStyle(Color.celTextDim)
            }

            let sunrise = solarDay.event(.sunrise)
            let sunset = solarDay.event(.sunset)
            let daylight = Self.daylightText(
                sunrise: sunrise,
                sunset: sunset,
                state: solarDay.state
            )

            // Summary metrics stack vertically when three-across does not fit.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: CelSpace.sm) {
                    MetricReadout(Self.sunriseLabel, value: Self.timeText(sunrise, in: timeZone),
                                  valueColor: .celAmber)
                    MetricReadout(Self.daylightLabel, value: daylight,
                                  valueColor: .celCyan)
                    MetricReadout(Self.sunsetLabel, value: Self.timeText(sunset, in: timeZone),
                                  alignment: .trailing, valueColor: .celAmber)
                }
                VStack(spacing: CelSpace.sm) {
                    MetricReadout(Self.sunriseLabel, value: Self.timeText(sunrise, in: timeZone),
                                  valueColor: .celAmber)
                    MetricReadout(Self.daylightLabel, value: daylight,
                                  valueColor: .celCyan)
                    MetricReadout(Self.sunsetLabel, value: Self.timeText(sunset, in: timeZone),
                                  valueColor: .celAmber)
                }
            }

            if let polarCopy = Self.polarBannerText(state: solarDay.state) {
                CelInlineMessage(
                    text: polarCopy,
                    icon: solarDay.state == .polarDay ? "sun.max.fill" : "moon.fill",
                    color: solarDay.state == .polarDay ? .celAmber : .celCyan
                )
            }
        }
        .instrumentCard(tint: .celGold)
    }

    private func dayStart(_ solarDay: SolarDay, in timeZone: TimeZone) -> Date {
        (try? solarDay.date.start(in: timeZone)) ?? viewModel.currentDate
    }

    // MARK: - Next event (destination-local today only)

    private func nextEventCard(solarDay: SolarDay, timeZone: TimeZone) -> some View {
        HStack(spacing: CelSpace.sm) {
            if let next = solarDay.nextEvent(after: viewModel.currentDate) {
                Image(systemName: Self.icon(for: next.kind))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Self.accent(for: next.kind))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.kind.displayName)
                        .font(.celBody(15, weight: .semibold))
                        .foregroundStyle(Color.celText)
                    Text(Self.timeText(next.instant, in: timeZone))
                        .font(.celLabel)
                        .foregroundStyle(Color.celTextDim)
                }
                Spacer()
                Text(AlmanacText.countdownText(from: viewModel.currentDate, to: next.instant))
                    .font(.celReadout(15))
                    .foregroundStyle(Color.celAmber)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.celTextDim)
                    .frame(width: 34)
                Text(Self.noMoreEventsText)
                    .font(.celBody(15, weight: .semibold))
                    .foregroundStyle(Color.celTextDim)
                Spacer()
            }
        }
        .padding(.vertical, 2)
        .instrumentCard(tint: .celCyan)
    }

    // MARK: - Typed event lists

    private func eventsCard(solarDay: SolarDay, timeZone: TimeZone, title: String,
                            kinds: [SolarEventKind], emptyText: String) -> some View {
        let events: [SolarEvent] = kinds.compactMap { kind in
            solarDay.event(kind).map { SolarEvent(kind: kind, instant: $0) }
        }
        let isToday = viewModel.today(in: timeZone) == solarDay.date

        return VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.celTextDim)
                .padding(.bottom, CelSpace.xs)
            if events.isEmpty {
                Text(emptyText)
                    .font(.celLabel)
                    .foregroundStyle(Color.celTextFaint)
                    .padding(.vertical, CelSpace.xs)
            } else {
                ForEach(Array(events.enumerated()), id: \.element.kind) { index, event in
                    if index > 0 {
                        CelDivider()
                            .padding(.vertical, 4)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: Self.icon(for: event.kind))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Self.accent(for: event.kind))
                            .frame(width: 22)
                        Text(event.kind.displayName)
                            .font(.celBody(14))
                            .foregroundStyle(Color.celText)
                        Spacer()
                        Text(Self.timeText(event.instant, in: timeZone))
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.celText)
                    }
                    .opacity(isToday && event.instant < viewModel.currentDate ? 0.45 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard(tint: .celGold, cornerTicks: false)
    }

    private var noLocationCard: some View {
        VStack(alignment: .leading, spacing: CelSpace.xs) {
            Text("No place yet")
                .font(.celBody(16, weight: .semibold))
                .foregroundStyle(Color.celText)
            Text("Sun times appear after you choose a location or allow access to your current position.")
                .font(.celLabel)
                .foregroundStyle(Color.celTextDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard(tint: .celGold, cornerTicks: false)
    }

    // MARK: - Kind iconography

    static let morningKinds: [SolarEventKind] =
        [.astronomicalDawn, .nauticalDawn, .civilDawn, .sunrise, .morningGoldenEnd]
    static let eveningKinds: [SolarEventKind] =
        [.eveningGoldenStart, .sunset, .civilDusk, .nauticalDusk, .astronomicalDusk]

    static func icon(for kind: SolarEventKind) -> String {
        switch kind {
        case .astronomicalDawn, .astronomicalDusk: "moon.stars.fill"
        case .nauticalDawn, .nauticalDusk: "moon.fill"
        case .civilDawn: "circle.lefthalf.filled"
        case .civilDusk: "circle.righthalf.filled"
        case .sunrise: "sunrise.fill"
        case .sunset: "sunset.fill"
        case .morningGoldenEnd, .eveningGoldenStart: "sun.max.fill"
        }
    }

    static func accent(for kind: SolarEventKind) -> Color {
        switch kind {
        case .sunrise, .sunset, .morningGoldenEnd, .eveningGoldenStart: .celAmber
        case .civilDawn, .civilDusk: .celCyan
        case .astronomicalDawn, .astronomicalDusk, .nauticalDawn, .nauticalDusk: .celText
        }
    }
}

// MARK: - Daylight track

/// Explanatory civil-dawn→civil-dusk arc, not a sky simulation: the day is a
/// 24-hour strip whose zones (night / twilight / daylight) come from the four
/// civil boundaries actually crossed that day. Decorative — hidden from
/// VoiceOver, since the exact times live in the MORNING/EVENING event rows.
private struct DaylightTrackCard: View {
    let solarDay: SolarDay
    let timeZone: TimeZone
    /// Fallback anchor from the injected clock for the (unreachable for real
    /// dates) invalid-local-day branch of `dayInterval`.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: CelSpace.sm) {
            Text("DAYLIGHT TRACK").celEyebrow(size: 10)
            DaylightTrack(
                markers: markers,
                dayInterval: dayInterval,
                fillsFullDay: fillsFullDay,
                timeZone: timeZone
            )
            HStack(spacing: CelSpace.sm) {
                legend(color: .celCyanDeep.opacity(0.8), text: "Twilight")
                legend(color: .celGold, text: "Daylight")
                legend(color: Color.celTextFaint.opacity(0.35), text: "Night")
            }
            Text("From civil dawn to civil dusk — an explanatory arc, not a sky simulation.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.celTextFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard(tint: .celCyan, cornerTicks: false)
        .accessibilityHidden(true)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.celTextDim)
        }
    }

    /// The civil boundaries in chronological order (subset that exists today).
    private var markers: [(kind: SolarEventKind, instant: Date)] {
        [.civilDawn, .sunrise, .sunset, .civilDusk].compactMap { kind in
            solarDay.event(kind).map { (kind, $0) }
        }
        .sorted { $0.instant < $1.instant }
    }

    private var dayInterval: (start: Date, end: Date) {
        let start = (try? solarDay.date.start(in: timeZone)) ?? now
        let end = (try? solarDay.date.endExclusive(in: timeZone)) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// Polar day has no horizon crossings at all; the whole strip is daylight.
    private var fillsFullDay: Bool {
        solarDay.state == .polarDay
    }
}

private struct DaylightTrack: View {
    let markers: [(kind: SolarEventKind, instant: Date)]
    let dayInterval: (start: Date, end: Date)
    let fillsFullDay: Bool
    let timeZone: TimeZone

    /// Zone color that starts at each civil boundary.
    private func colorAfter(_ kind: SolarEventKind) -> Color {
        switch kind {
        case .civilDawn, .sunset: .celCyanDeep.opacity(0.55)
        case .sunrise: .celGold.opacity(0.85)
        default: Color.celTextFaint.opacity(0.18)
        }
    }

    private func fraction(of instant: Date) -> CGFloat {
        let total = dayInterval.end.timeIntervalSince(dayInterval.start)
        guard total > 0 else { return 0 }
        let value = instant.timeIntervalSince(dayInterval.start) / total
        return CGFloat(min(max(value, 0), 1))
    }

    /// Colored zones spanning the full day: night until the first boundary,
    /// then the color that starts at each boundary until the next one.
    /// Polar day (no crossings, sun up all day) fills entirely with daylight;
    /// polar night with no crossings stays night.
    private var zones: [(from: CGFloat, to: CGFloat, color: Color)] {
        if markers.isEmpty {
            return fillsFullDay
                ? [(0, 1, .celGold.opacity(0.85))]
                : [(0, 1, Color.celTextFaint.opacity(0.18))]
        }
        var zones: [(from: CGFloat, to: CGFloat, color: Color)] = []
        var cursor: CGFloat = 0
        var current = Color.celTextFaint.opacity(0.18)
        for marker in markers {
            let position = fraction(of: marker.instant)
            if position > cursor {
                zones.append((cursor, position, current))
            }
            current = colorAfter(marker.kind)
            cursor = position
        }
        if cursor < 1 {
            zones.append((cursor, 1, current))
        }
        return zones
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let trackHeight: CGFloat = 10

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                    Capsule()
                        .fill(zone.color)
                        .frame(width: max(0, (zone.to - zone.from) * width))
                        .offset(x: zone.from * width)
                }
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    Rectangle()
                        .fill(Color.celText.opacity(0.9))
                        .frame(width: 1, height: trackHeight + 5)
                        .offset(x: fraction(of: marker.instant) * width - 0.5)
                }
            }
            .frame(height: trackHeight)

            // Time labels under each boundary marker, kept on-screen at the
            // edges by clamping the label frame.
            ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                let x = fraction(of: marker.instant) * width
                Text(AlmanacText.clockText(marker.instant, in: timeZone))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.celTextDim)
                    .frame(width: 46, alignment: .center)
                    .position(x: min(max(x, 23), width - 23), y: trackHeight + 12)
            }
        }
        .frame(height: 34)
    }
}
