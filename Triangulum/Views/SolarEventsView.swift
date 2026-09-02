//
//  SolarEventsView.swift
//  Triangulum
//
//  F2.3 — Sunrise/Sunset & Golden Hour
//

import SwiftUI

// MARK: - SolarEventsView

struct SolarEventsView: View {
    @ObservedObject var locationManager: LocationManager

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    // Morning (Sun rising through each threshold) / evening, in display order.
    private static let morningKinds: [SolarEventKind] =
        [.astronomicalDawn, .nauticalDawn, .civilDawn, .sunrise, .morningGoldenEnd]
    private static let eveningKinds: [SolarEventKind] =
        [.eveningGoldenStart, .sunset, .civilDusk, .nauticalDusk, .astronomicalDusk]

    private var hasUsableLocation: Bool {
        locationManager.hasValidLocation
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // Temporary device-local bridge until Task 9 removes this screen.
    private var solarDay: SolarDay? {
        guard hasUsableLocation else { return nil }
        return try? SolarDay(date: LocalDate(selectedDate, in: .current),
                             timeZone: .current,
                             latitude: locationManager.latitude,
                             longitude: locationManager.longitude)
    }

    var body: some View {
        let solarDay = solarDay

        ScrollView {
            VStack(spacing: 0) {
                headerCard
                if let solarDay {
                    if isToday {
                        SolarCountdownCard(solarDay: solarDay, now: now)
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }
                    morningSection(solarDay: solarDay)
                    eveningSection(solarDay: solarDay)
                } else {
                    locationUnavailableCard
                }
            }
        }
        .background(StarfieldBackground(showConstellation: false))
        .navigationTitle("Solar Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.celBackgroundTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left").foregroundColor(.white)
                    }
                    if !isToday {
                        Button("Today") {
                            selectedDate = Calendar.current.startOfDay(for: Date())
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    }
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right").foregroundColor(.white)
                    }
                }
            }
        }
        .onReceive(timer) { _ in now = Date() }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateFormatter.string(from: selectedDate))
                .font(.headline)
                .foregroundColor(.celText)
            if hasUsableLocation {
                Text(String(format: "%.4f°, %.4f°",
                            locationManager.latitude, locationManager.longitude))
                    .font(.caption)
                    .foregroundColor(.celTextDim)
            } else {
                Text(locationManager.errorMessage.isEmpty
                     ? "Waiting for a location fix..."
                     : locationManager.errorMessage)
                    .font(.caption)
                    .foregroundColor(.celRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.celSurfaceTop.opacity(0.85))
    }

    private func section(solarDay: SolarDay, title: String, kinds: [SolarEventKind], emptyMessage: String) -> some View {
        let events: [SolarEvent] = kinds.compactMap { kind in
            solarDay.event(kind).map { SolarEvent(kind: kind, instant: $0) }
        }
        return sectionCard(title: title) {
            if events.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundColor(.celTextDim)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    SolarEventRow(icon: Self.icon(for: event.kind),
                                  label: event.kind.displayName,
                                  time: Self.timeFormatter.string(from: event.instant),
                                  accent: Self.accent(for: event.kind),
                                  isPast: isToday && event.instant < now,
                                  showDivider: index < events.count - 1)
                }
            }
        }
    }

    private func morningSection(solarDay: SolarDay) -> some View {
        section(solarDay: solarDay, title: "MORNING", kinds: Self.morningKinds,
                emptyMessage: "Sun does not rise at this location today.")
    }

    private func eveningSection(solarDay: SolarDay) -> some View {
        section(solarDay: solarDay, title: "EVENING", kinds: Self.eveningKinds,
                emptyMessage: "Sun does not set at this location today.")
    }

    private static func icon(for kind: SolarEventKind) -> String {
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

    private static func accent(for kind: SolarEventKind) -> Color {
        switch kind {
        case .sunrise, .sunset, .morningGoldenEnd, .eveningGoldenStart: .celAmber
        case .civilDawn, .civilDusk: .celCyan
        case .astronomicalDawn, .astronomicalDusk, .nauticalDawn, .nauticalDusk: .celText
        }
    }

    private var locationUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location required")
                .font(.headline)
                .foregroundColor(.celText)
            Text("Solar event times appear after location permissions are granted and a valid GPS fix is available.")
                .font(.subheadline)
                .foregroundColor(.celTextDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.celSurfaceTop.opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.celTextDim)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.celSurfaceTop.opacity(0.85))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - SolarEventRow

private struct SolarEventRow: View {
    let icon: String
    let label: String
    let time: String
    let accent: Color
    let isPast: Bool
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .frame(width: 24)
                Text(label)
                    .foregroundColor(.celText)
                Spacer()
                Text(time)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.celText)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .opacity(isPast ? 0.4 : 1.0)
            if showDivider {
                Divider().padding(.leading, 52)
            }
        }
    }
}

// MARK: - SolarCountdownCard

private struct SolarCountdownCard: View {
    let solarDay: SolarDay
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title3)
            if let next = solarDay.nextEvent(after: now) {
                let interval = next.instant.timeIntervalSince(now)
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                    if interval > 0 {
                        let hours = Int(interval) / 3600
                        let minutes = (Int(interval) % 3600) / 60
                        Text(hours > 0 ? "in \(hours)h \(minutes)m" : "in \(minutes)m")
                            .font(.caption)
                            .opacity(0.85)
                    } else {
                        Text("Happening now")
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
            } else {
                Text("No more events today")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding()
        .background(Color.celCyanDeep)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SolarEventsView(locationManager: LocationManager())
    }
}
