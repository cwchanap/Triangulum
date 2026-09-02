//
//  AlmanacView.swift
//  Triangulum
//

import SwiftUI

// MARK: - Shared Almanac formatting/copy

/// Pure text projection for the Almanac UI: one shared namespace so the Sun
/// and Tides sections (and the presentation tests) format destination-local
/// times, time-zone lines, and countdowns identically. Formatters are created
/// per call with an explicit POSIX locale and destination time zone, so output
/// is deterministic regardless of the device locale.
enum AlmanacText {
    static func clockText(_ instant: Date, in timeZone: TimeZone) -> String {
        formatter(dateFormat: "HH:mm", timeZone: timeZone).string(from: instant)
    }

    /// "Tuesday, September 15" — section-date eyebrow copy.
    static func dayTitleText(_ date: Date, in timeZone: TimeZone) -> String {
        formatter(dateFormat: "EEEE, MMMM d", timeZone: timeZone).string(from: date)
    }

    /// "September 15, 2026" — chart-summary date copy.
    static func fullDateText(_ date: Date, in timeZone: TimeZone) -> String {
        formatter(dateFormat: "MMMM d, yyyy", timeZone: timeZone).string(from: date)
    }

    /// "Sep 15, 12:00" — last-update copy.
    static func shortDateTimeText(_ date: Date, in timeZone: TimeZone) -> String {
        formatter(dateFormat: "MMM d, HH:mm", timeZone: timeZone).string(from: date)
    }

    /// "Tue" — date-strip chip copy.
    static func weekdayText(_ date: Date, in timeZone: TimeZone) -> String {
        formatter(dateFormat: "EEE", timeZone: timeZone).string(from: date)
    }

    /// "Pacific Daylight Time · UTC−7" — readable name plus signed UTC offset
    /// at `date` (DST-aware for the name).
    static func timeZoneLine(_ timeZone: TimeZone, at date: Date) -> String {
        let style: TimeZone.NameStyle = timeZone.isDaylightSavingTime(for: date) ? .daylightSaving : .standard
        let name = timeZone.localizedName(for: style, locale: Locale(identifier: "en_US_POSIX"))
            ?? timeZone.identifier
        return "\(name) · \(utcOffsetText(timeZone, at: date))"
    }

    /// "in 3h 05m" / "in 12m"; `now` for an instant at or before `now`. The
    /// next-event filter only returns strictly-future instants, so `now` is
    /// the defensive branch for clock-skew between one-minute ticks.
    static func countdownText(from now: Date, to target: Date) -> String {
        let interval = target.timeIntervalSince(now)
        guard interval > 0 else { return "now" }
        let totalMinutes = Int(ceil(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "in \(hours)h \(String(format: "%02d", minutes))m" }
        return "in \(minutes)m"
    }

    static func locationModeText(_ mode: AlmanacLocationMode) -> String {
        switch mode {
        case .current: "Current Location"
        case .selected: "Selected Location"
        }
    }

    /// "Vancouver, British Columbia" — display name plus region when the
    /// resolver supplied one.
    static func placeLine(_ location: AlmanacLocation) -> String {
        guard let area = location.administrativeArea, !area.isEmpty else { return location.displayName }
        return "\(location.displayName), \(area)"
    }

    private static func utcOffsetText(_ timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "−" : "+"
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let remainderMinutes = totalMinutes % 60
        if remainderMinutes > 0 {
            return "UTC\(sign)\(hours):\(String(format: "%02d", remainderMinutes))"
        }
        return "UTC\(sign)\(hours)"
    }

    private static func formatter(dateFormat: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        formatter.timeZone = timeZone
        return formatter
    }
}

// MARK: - AlmanacView

/// Root Almanac screen: shared location/mode/time-zone context, the rolling
/// seven-day date strip, and the Sun | Tides section picker above the current
/// section's content. Owns the one `AlmanacViewModel` for the tab.
@MainActor
struct AlmanacView: View {
    @StateObject private var viewModel: AlmanacViewModel
    @StateObject private var searchCompleter = AppleSearchCompleter()
    @State private var showsLocationSheet = false

    private let dependencies: AlmanacDependencies
    private let locationManager: LocationManager?

    init(locationManager: LocationManager? = nil, dependencies: AlmanacDependencies) {
        self.dependencies = dependencies
        self.locationManager = locationManager
        _viewModel = StateObject(
            wrappedValue: AlmanacViewModel(dependencies: dependencies, locationManager: locationManager)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            contextHeader
            dateStrip
            sectionPicker
            sectionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .celestialBackground()
        .onAppear {
            // No restored fixed location (fresh launch, or .current mode with
            // no stored place): follow the device until a place is chosen.
            if viewModel.location == nil {
                viewModel.useCurrentLocation()
            }
        }
        .sheet(isPresented: $showsLocationSheet) {
            NavigationStack {
                AlmanacLocationSheet(
                    currentLocation: viewModel.location,
                    lastFixedLocation: viewModel.lastFixedLocation,
                    locationManager: locationManager,
                    completer: searchCompleter,
                    resolver: dependencies.locationResolver,
                    onSelectLocation: { viewModel.selectLocation($0) },
                    onUseCurrentLocation: { viewModel.useCurrentLocation() }
                )
                .navigationTitle("Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsLocationSheet = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Shared context

    @ViewBuilder
    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: CelSpace.sm) {
            HStack(alignment: .top, spacing: CelSpace.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ALMANAC").celEyebrow(.celTextDim, size: 10)
                    if let location = viewModel.location {
                        Text(AlmanacText.placeLine(location))
                            .font(.celDisplay(21, weight: .semibold))
                            .foregroundStyle(Color.celText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(AlmanacText.locationModeText(location.mode))
                            .celEyebrow(.celTextDim, size: 9)
                        if let timeZone = location.timeZone {
                            let anchor = dateAnchor(in: timeZone)
                            Text(AlmanacText.timeZoneLine(timeZone, at: anchor))
                                .font(.celLabel)
                                .foregroundStyle(Color.celTextDim)
                        }
                    } else {
                        Text("Locating…")
                            .font(.celDisplay(21, weight: .semibold))
                            .foregroundStyle(Color.celText)
                        Text("Sun and tide times appear once a place is known.")
                            .font(.celLabel)
                            .foregroundStyle(Color.celTextDim)
                    }
                }
                Spacer(minLength: 8)
                Button("Change") { showsLocationSheet = true }
                    .font(.celLabel)
                    .foregroundStyle(Color.celCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.celCyan.opacity(0.1))
                            .overlay(Capsule().strokeBorder(Color.celCyan.opacity(0.4), lineWidth: 0.5))
                    )
            }

            if let locationManager, viewModel.location == nil,
               locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                CelInlineMessage(text: "Location access denied", color: .celRed)
                HStack {
                    Spacer()
                    Button("Open Settings") { locationManager.openAppSettings() }
                        .font(.celLabel)
                        .foregroundStyle(Color.celCyan)
                }
            }
        }
        .padding(.horizontal, CelSpace.md)
        .padding(.top, CelSpace.sm)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// Time-zone names and offsets are evaluated at the selected date's local
    /// noon so a destination DST transition never mislabels the strip's day.
    private func dateAnchor(in timeZone: TimeZone) -> Date {
        guard let selectedDate = viewModel.selectedDate else { return viewModel.currentDate }
        return (try? selectedDate.noon(in: timeZone)) ?? viewModel.currentDate
    }

    // MARK: - Date strip

    private var dateStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                windowButton(icon: "chevron.left", label: "Previous 7 days", days: -7)
                dateChips
                windowButton(icon: "chevron.right", label: "Next 7 days", days: 7)
            }
            HStack {
                Spacer()
                todayButton
            }
        }
        .padding(.horizontal, CelSpace.md)
        .padding(.top, CelSpace.sm)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    private func windowButton(icon: String, label: String, days: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.moveWindow(byDays: days) }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("7 days")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(0.4)
            }
            .foregroundStyle(Color.celTextDim)
            .frame(width: 46)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .accessibilityLabel(label)
    }

    private var dateChips: some View {
        // The seven chips scroll horizontally on narrow phones and sit
        // centered when the full window fits.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { ForEach(chips) { chip($0) } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) { ForEach(chips) { chip($0) } }
            }
        }
    }

    private var chips: [DateChipModel] {
        guard let timeZone = viewModel.location?.timeZone else { return [] }
        return viewModel.visibleDates.compactMap { date in
            guard let instant = try? date.start(in: timeZone) else { return nil }
            return DateChipModel(
                date: date,
                weekday: AlmanacText.weekdayText(instant, in: timeZone),
                dayNumber: String(date.day)
            )
        }
    }

    private func chip(_ model: DateChipModel) -> some View {
        let isSelected = model.date == viewModel.selectedDate
        return Button {
            viewModel.selectDate(model.date)
        } label: {
            VStack(spacing: 2) {
                Text(model.weekday)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                Text(model.dayNumber)
                    .font(.celReadout(15, weight: isSelected ? .semibold : .regular))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.celText : Color.celTextDim)
            .frame(width: 40)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.celCyan.opacity(0.16) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.celCyan.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .accessibilityLabel("\(model.date.year) \(model.weekday), \(model.dayNumber)")
    }

    @ViewBuilder
    private var todayButton: some View {
        if viewModel.selectedDate == destinationToday {
            Text("Today")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.celTextFaint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        } else {
            Button {
                viewModel.selectToday()
            } label: {
                Label("Today", systemImage: "calendar")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.celCyan)
            }
        }
    }

    private var destinationToday: LocalDate? {
        guard let timeZone = viewModel.location?.timeZone else { return nil }
        return viewModel.today(in: timeZone)
    }

    // MARK: - Section picker

    private var sectionPicker: some View {
        Picker("Section", selection: $viewModel.section) {
            Text("Sun").tag(AlmanacViewModel.Section.sun)
            Text("Tides").tag(AlmanacViewModel.Section.tides)
        }
        .pickerStyle(.segmented)
        .tint(Color.celCyan)
        .padding(.horizontal, CelSpace.md)
        .padding(.top, CelSpace.sm)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.section {
        case .sun:
            AlmanacSunView(viewModel: viewModel)
        case .tides:
            AlmanacTidesView(viewModel: viewModel)
        }
    }
}

// MARK: - Date chip model

private struct DateChipModel: Identifiable {
    let date: LocalDate
    let weekday: String
    let dayNumber: String

    var id: LocalDate { date }
}
