//
//  AlmanacTidesView.swift
//  Triangulum
//

import SwiftUI

/// The Tides section: next/first-tide summary (next + countdown only for the
/// station-local today), the linear official-points chart, the chronological
/// exact-event list, the station card (distance, time zone when different,
/// datum, attribution, update/cache state, Choose another station, the
/// planning-only warning), cached/offline and provider warnings, and
/// pull-to-refresh.
struct AlmanacTidesView: View {
    @ObservedObject var viewModel: AlmanacViewModel
    /// Render trigger only: every today/countdown judgment reads the view
    /// model's injected clock, so the -ui-testing fixture stays deterministic
    /// and this tick (at most once per minute) keeps production copy fresh.
    @State private var minuteTick = 0
    @State private var showsStationSheet = false

    /// Spec: countdown updates at most once per minute.
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // MARK: - Pure copy

    static let findingStationsText = "Finding nearby tide stations…"
    static let noPredictionsText = "No predicted events"
    static let noMoreEventsTodayText = "No more events today"
    static let offlinePredictionsText = "Offline — showing cached predictions."
    static let planningOnlyWarningText = "Predictions are for planning only, not navigation."
    static let chooseAnotherStationText = "Choose another station"

    static func loadingPredictionsText(stationName: String) -> String {
        "Loading predictions for \(stationName)…"
    }

    /// Summary headline: the next event leads only for the station-local
    /// today; other dates lead with the day's first event instead. A day
    /// with no published events says so regardless of date; "no more events
    /// today" is reserved for a today whose published events have all passed.
    static func summaryTitle(day: TideDay, isToday: Bool, now: Date) -> String {
        if day.events.isEmpty {
            return noPredictionsText
        }
        if isToday, day.nextEvent(after: now) == nil {
            return noMoreEventsTodayText
        }
        return isToday ? "Next tide" : "First tide"
    }

    static func summaryEvent(day: TideDay, isToday: Bool, now: Date) -> TideEvent? {
        guard let first = day.events.min(by: { $0.instant < $1.instant }) else { return nil }
        return isToday ? day.nextEvent(after: now) : first
    }

    static func distanceText(metres: Double) -> String {
        if metres < 1_000 {
            return String(format: "%.0f m away", metres)
        }
        return String(format: "%.1f km away", metres / 1_000)
    }

    static func stationLineText(station: TideStation, distanceMetres: Double) -> String {
        "\(station.name) · \(distanceText(metres: distanceMetres))"
    }

    /// "Updated Sep 15, 12:00" for fresh predictions; a stale cached day
    /// leads with "Cached" instead of claiming a successful update.
    static func updatedRowText(fetchedAt: Date, isStale: Bool, timeZone: TimeZone) -> String {
        let prefix = isStale ? "Cached" : "Updated"
        return "\(prefix) \(AlmanacText.shortDateTimeText(fetchedAt, in: timeZone))"
    }

    static func tideWarningText(_ warning: TideLoadError) -> String {
        switch warning {
        case .unsupportedRegion:
            "Tide predictions aren't available for this region."
        case .providerUnavailable:
            "The tide provider for this region is temporarily unavailable."
        case .noStationNearby:
            "No supported tide station nearby."
        case .networkUnavailable:
            "Couldn't reach the tide service."
        case .invalidProviderResponse:
            "The tide provider returned an unexpected response."
        case .noPredictions:
            "No tide predictions were published for these dates."
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
        .refreshable {
            await viewModel.loadTides(forceRefresh: true)
        }
        .onReceive(minuteTimer) { _ in minuteTick += 1 }
        .sheet(isPresented: $showsStationSheet) {
            if let context = viewModel.stationContext {
                NavigationStack {
                    TideStationSheet(
                        selectedStation: context.selected,
                        alternatives: context.nearbyStations,
                        onSelect: { station in
                            viewModel.selectStation(station)
                            showsStationSheet = false
                        },
                        onUseNearestStation: {
                            viewModel.useNearestStation()
                            showsStationSheet = false
                        }
                    )
                    .navigationTitle("Choose a station")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsStationSheet = false }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let context = viewModel.stationContext {
            if let day = viewModel.tideDay {
                let isToday = viewModel.today(in: context.timeZone) == day.localDate

                if viewModel.tideIsStale {
                    CelInlineMessage(text: Self.offlinePredictionsText,
                                     icon: "clock.arrow.circlepath", color: .celAmber)
                } else if let warning = viewModel.tideWarning {
                    CelInlineMessage(text: Self.tideWarningText(warning),
                                     color: .celAmber)
                }

                summaryCard(day: day, context: context, isToday: isToday)
                chartCard(day: day, context: context, isToday: isToday)
                eventsCard(day: day, context: context)
                stationCard(day: day, context: context)
            } else if let warning = viewModel.tideWarning {
                messageCard(title: Self.tideWarningText(warning),
                            hint: warning == .unsupportedRegion
                                ? "Sun times remain available in the Sun section."
                                : "Pull to refresh to try again.")
            } else {
                loadingCard(text: Self.loadingPredictionsText(stationName: context.selected.name))
            }
        } else if let warning = viewModel.tideWarning {
            messageCard(title: Self.tideWarningText(warning),
                        hint: warning == .unsupportedRegion
                            ? "Sun times remain available in the Sun section."
                            : "Pull to refresh to try again.")
        } else {
            loadingCard(text: Self.findingStationsText)
        }
    }

    // MARK: - Summary

    private func summaryCard(day: TideDay, context: TideStationContext, isToday: Bool) -> some View {
        let event = Self.summaryEvent(day: day, isToday: isToday, now: viewModel.currentDate)

        return VStack(alignment: .leading, spacing: CelSpace.sm) {
            InstrumentHeader(icon: "water.waves",
                             title: Self.summaryTitle(day: day, isToday: isToday, now: viewModel.currentDate),
                             tint: .celCyan) {
                // A day without exact events already puts its long title in
                // the header; the trailing date stays only for event days.
                if event != nil {
                    Text(AlmanacText.dayTitleText(dayStart(day, in: context.timeZone), in: context.timeZone))
                        .font(.celTiny)
                        .foregroundStyle(Color.celTextDim)
                }
            }

            if let event {
                HStack(spacing: 10) {
                    Image(systemName: event.kind == .high ? "arrow.up" : "arrow.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(event.kind == .high ? Color.celCyan : Color.celGold)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.kind.displayName)
                            .font(.celBody(15, weight: .semibold))
                            .foregroundStyle(Color.celText)
                        Text("\(AlmanacText.clockText(event.instant, in: context.timeZone)) · \(TideChartView.heightText(event.heightMetres))")
                            .font(.celLabel)
                            .foregroundStyle(Color.celTextDim)
                    }
                    Spacer()
                    if isToday {
                        Text(AlmanacText.countdownText(from: viewModel.currentDate, to: event.instant))
                            .font(.celReadout(16))
                            .foregroundStyle(Color.celAmber)
                    }
                }
                Text(Self.stationLineText(station: day.station, distanceMetres: context.distanceMetres))
                    .font(.celTiny)
                    .foregroundStyle(Color.celTextFaint)
            } else {
                Text(day.events.isEmpty
                     ? "No exact high or low waters were published for this date."
                     : "All of today's predicted high and low waters have passed.")
                    .font(.celLabel)
                    .foregroundStyle(Color.celTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .instrumentCard(tint: .celCyan)
    }

    private func dayStart(_ day: TideDay, in timeZone: TimeZone) -> Date {
        (try? day.localDate.start(in: timeZone)) ?? viewModel.currentDate
    }

    // MARK: - Chart

    private func chartCard(day: TideDay, context: TideStationContext, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: CelSpace.sm) {
            InstrumentHeader(icon: "chart.xyaxis.line", title: "Tide curve", tint: .celCyan) {
                StatusPill("Metres", color: .celCyanDeep)
            }
            TideChartView(
                day: day,
                timeZone: context.timeZone,
                now: isToday ? viewModel.currentDate : nil
            )
            Text("Official hourly predictions; markers show the exact high and low waters. Linear chart, no sub-hour precision.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.celTextFaint)
        }
        .instrumentCard(tint: .celCyan)
    }

    // MARK: - Chronological events

    private func eventsCard(day: TideDay, context: TideStationContext) -> some View {
        let events = day.events.sorted { $0.instant < $1.instant }

        return VStack(alignment: .leading, spacing: 0) {
            Text("EVENTS").celEyebrow(size: 10)
                .padding(.bottom, CelSpace.xs)
            if events.isEmpty {
                Text("No exact high or low waters were published for this date.")
                    .font(.celLabel)
                    .foregroundStyle(Color.celTextFaint)
            } else {
                ForEach(Array(events.enumerated()), id: \.element.instant) { index, event in
                    if index > 0 {
                        CelDivider()
                            .padding(.vertical, 4)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: event.kind == .high ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(event.kind == .high ? Color.celCyan : Color.celGold)
                            .frame(width: 22)
                        Text(event.kind.displayName)
                            .font(.celBody(14))
                            .foregroundStyle(Color.celText)
                        Spacer()
                        Text(TideChartView.heightText(event.heightMetres))
                            .font(.celLabel)
                            .foregroundStyle(Color.celTextDim)
                        Text(AlmanacText.clockText(event.instant, in: context.timeZone))
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.celText)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard(tint: .celCyan, cornerTicks: false)
    }

    // MARK: - Station card

    /// Whether the station's own zone differs from the Almanac LOCATION's
    /// zone: the station card then shows the station-local time (and the
    /// amber pill). The location zone — not the context zone, which is the
    /// station's own — is the comparison baseline, so the row appears only
    /// when the station really does sit in another zone.
    static func showsStationTimeZoneRow(stationZone: TimeZone?, locationZone: TimeZone?) -> Bool {
        guard let stationZone, let locationZone else { return false }
        return stationZone.identifier != locationZone.identifier
    }

    private func stationCard(day: TideDay, context: TideStationContext) -> some View {
        let stationZoneDiffers = Self.showsStationTimeZoneRow(
            stationZone: day.station.timeZone,
            locationZone: viewModel.location?.timeZone
        )

        return VStack(alignment: .leading, spacing: CelSpace.xs) {
            InstrumentHeader(icon: "mappin.and.ellipse", title: "Station", tint: .celGold) {
                if stationZoneDiffers {
                    StatusPill("Local time zone", color: .celAmber)
                }
            }

            VStack(alignment: .leading, spacing: CelSpace.xs) {
                Text(day.station.name)
                    .font(.celBody(16, weight: .semibold))
                    .foregroundStyle(Color.celText)

                stationRow(label: "Distance",
                           value: Self.distanceText(metres: context.distanceMetres))
                if stationZoneDiffers, let stationZone = day.station.timeZone {
                    stationRow(label: "Local time",
                               value: AlmanacText.timeZoneLine(stationZone, at: contextAnchor(day: day, in: stationZone)))
                }
                stationRow(label: "Datum", value: day.station.datumLabel)
                stationRow(label: "Source", value: day.sourceAttribution)
                stationRow(label: "Last update",
                           value: Self.updatedRowText(fetchedAt: day.fetchedAt,
                                                      isStale: viewModel.tideIsStale,
                                                      timeZone: context.timeZone))
                // Required derivative-product notice, next to the source
                // attribution (TideProvider.attributionNotice).
                if let notice = day.station.provider.attributionNotice {
                    Text(notice)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.celTextFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, CelSpace.xs)
                }
            }

            Button {
                showsStationSheet = true
            } label: {
                HStack {
                    Text(Self.chooseAnotherStationText)
                        .font(.celLabel)
                        .foregroundStyle(Color.celCyan)
                    Spacer()
                    CelChevron()
                }
                .padding(.top, CelSpace.xs)
            }

            CelInlineMessage(text: Self.planningOnlyWarningText,
                             icon: "info.circle.fill", color: .celCyan)
        }
        .instrumentCard(tint: .celGold)
    }

    /// Anchor instant for the station zone's DST-aware name: the displayed
    /// day's local noon in that zone.
    private func contextAnchor(day: TideDay, in timeZone: TimeZone) -> Date {
        (try? day.localDate.noon(in: timeZone)) ?? day.fetchedAt
    }

    private func stationRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .celEyebrow(size: 9)
            Spacer()
            Text(value)
                .font(.celLabel)
                .foregroundStyle(Color.celText)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Loading / message states

    private func loadingCard(text: String) -> some View {
        VStack(spacing: CelSpace.sm) {
            ProgressView()
                .tint(Color.celCyan)
            Text(text)
                .font(.celLabel)
                .foregroundStyle(Color.celTextDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CelSpace.xl)
        .instrumentCard(tint: .celCyan)
    }

    private func messageCard(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: CelSpace.xs) {
            Text(title)
                .font(.celBody(15, weight: .semibold))
                .foregroundStyle(Color.celText)
            Text(hint)
                .font(.celLabel)
                .foregroundStyle(Color.celTextDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentCard(tint: .celAmber)
    }
}
