//
//  SolarEventsView.swift
//  Triangulum
//
//  F2.3 — Sunrise/Sunset & Golden Hour
//

import SwiftUI

// MARK: - SolarDay

/// All solar event times for a given calendar day and observer location.
/// Times are nil when the Sun never reaches that altitude (polar day/night).
struct SolarDay {
    let date: Date
    let latitude: Double
    let longitude: Double

    // Morning (Sun rising through each threshold)
    let astronomicalDawn: Date?    // Sun at -18° rising  — sky turns from black to deep blue
    let nauticalDawn: Date?        // Sun at -12° rising  — horizon faintly visible
    let civilDawn: Date?           // Sun at  -6° rising  — blue hour begins
    let sunrise: Date?             // Sun at -0.833° rising — golden hour begins
    let morningGoldenEnd: Date?    // Sun at  +6° rising  — golden hour ends

    // Evening (Sun setting through each threshold)
    let eveningGoldenStart: Date?  // Sun at  +6° setting — golden hour begins
    let sunset: Date?              // Sun at -0.833° setting — golden hour ends
    let civilDusk: Date?           // Sun at  -6° setting — blue hour ends
    let nauticalDusk: Date?        // Sun at -12° setting
    let astronomicalDusk: Date?    // Sun at -18° setting — sky fully dark

    init(date: Date, latitude: Double, longitude: Double) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude

        let solarCrossing = ConstellationMapView.Astronomer.solarCrossing
        astronomicalDawn = solarCrossing(-18.0, true, date, latitude, longitude)
        nauticalDawn = solarCrossing(-12.0, true, date, latitude, longitude)
        civilDawn = solarCrossing(-6.0, true, date, latitude, longitude)
        sunrise = solarCrossing(-0.833, true, date, latitude, longitude)
        morningGoldenEnd = solarCrossing(6.0, true, date, latitude, longitude)
        eveningGoldenStart = solarCrossing(6.0, false, date, latitude, longitude)
        sunset = solarCrossing(-0.833, false, date, latitude, longitude)
        civilDusk = solarCrossing(-6.0, false, date, latitude, longitude)
        nauticalDusk = solarCrossing(-12.0, false, date, latitude, longitude)
        astronomicalDusk = solarCrossing(-18.0, false, date, latitude, longitude)
    }

    /// All non-nil events sorted chronologically.
    var allEvents: [(label: String, time: Date)] {
        let raw: [(String, Date?)] = [
            ("Astronomical twilight", astronomicalDawn),
            ("Nautical twilight", nauticalDawn),
            ("Blue hour begins", civilDawn),
            ("Sunrise", sunrise),
            ("Golden hour ends", morningGoldenEnd),
            ("Golden hour begins", eveningGoldenStart),
            ("Sunset", sunset),
            ("Blue hour ends", civilDusk),
            ("Nautical twilight ends", nauticalDusk),
            ("Astronomical twilight ends", astronomicalDusk)
        ]
        return raw.compactMap { label, time in time.map { (label, $0) } }
               .sorted { $0.time < $1.time }
    }

    /// The first event after `now`, or nil if all events are in the past.
    func nextEvent(after now: Date) -> (label: String, time: Date)? {
        allEvents.first { $0.time > now }
    }
}

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

    private var hasUsableLocation: Bool {
        locationManager.hasValidLocation
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        let solarDay = hasUsableLocation
            ? SolarDay(date: selectedDate,
                       latitude: locationManager.latitude,
                       longitude: locationManager.longitude)
            : nil

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
        .background(Color.prussianSoft.ignoresSafeArea())
        .navigationTitle("Solar Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.prussianBlue, for: .navigationBar)
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
                .foregroundColor(.prussianBlueDark)
            if hasUsableLocation {
                Text(String(format: "%.4f°, %.4f°",
                            locationManager.latitude, locationManager.longitude))
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            } else {
                Text(locationManager.errorMessage.isEmpty
                     ? "Waiting for a location fix..."
                     : locationManager.errorMessage)
                    .font(.caption)
                    .foregroundColor(.prussianError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.85))
    }

    private func morningSection(solarDay: SolarDay) -> some View {
        let hasMorningEvents = solarDay.astronomicalDawn != nil || solarDay.nauticalDawn != nil
            || solarDay.civilDawn != nil || solarDay.sunrise != nil || solarDay.morningGoldenEnd != nil
        return sectionCard(title: "MORNING") {
            if hasMorningEvents {
                if let t = solarDay.astronomicalDawn {
                    SolarEventRow(icon: "moon.stars.fill", label: "Astronomical twilight",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianBlueDark, isPast: isToday && t < now)
                }
                if let t = solarDay.nauticalDawn {
                    SolarEventRow(icon: "moon.fill", label: "Nautical twilight",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianBlueDark, isPast: isToday && t < now)
                }
                if let t = solarDay.civilDawn {
                    SolarEventRow(icon: "circle.lefthalf.filled", label: "Blue hour begins",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianAccent, isPast: isToday && t < now)
                }
                if let t = solarDay.sunrise {
                    SolarEventRow(icon: "sunrise.fill", label: "Sunrise · Golden hour",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianWarning, isPast: isToday && t < now)
                }
                if let t = solarDay.morningGoldenEnd {
                    SolarEventRow(icon: "sun.max.fill", label: "Golden hour ends",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianWarning, isPast: isToday && t < now,
                                  showDivider: false)
                }
            } else {
                Text("Sun does not rise at this location today.")
                    .font(.subheadline)
                    .foregroundColor(.prussianBlueLight)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func eveningSection(solarDay: SolarDay) -> some View {
        let hasEveningEvents = solarDay.eveningGoldenStart != nil || solarDay.sunset != nil
            || solarDay.civilDusk != nil || solarDay.nauticalDusk != nil || solarDay.astronomicalDusk != nil
        return sectionCard(title: "EVENING") {
            if hasEveningEvents {
                if let t = solarDay.eveningGoldenStart {
                    SolarEventRow(icon: "sun.max.fill", label: "Golden hour begins",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianWarning, isPast: isToday && t < now)
                }
                if let t = solarDay.sunset {
                    SolarEventRow(icon: "sunset.fill", label: "Sunset · Blue hour",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianWarning, isPast: isToday && t < now)
                }
                if let t = solarDay.civilDusk {
                    SolarEventRow(icon: "circle.righthalf.filled", label: "Blue hour ends",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianAccent, isPast: isToday && t < now)
                }
                if let t = solarDay.nauticalDusk {
                    SolarEventRow(icon: "moon.fill", label: "Nautical twilight",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianBlueDark, isPast: isToday && t < now)
                }
                if let t = solarDay.astronomicalDusk {
                    SolarEventRow(icon: "moon.stars.fill", label: "Astronomical twilight",
                                  time: Self.timeFormatter.string(from: t),
                                  accent: .prussianBlueDark, isPast: isToday && t < now,
                                  showDivider: false)
                }
            } else {
                Text("Sun does not set at this location today.")
                    .font(.subheadline)
                    .foregroundColor(.prussianBlueLight)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var locationUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location required")
                .font(.headline)
                .foregroundColor(.prussianBlueDark)
            Text("Solar event times appear after location permissions are granted and a valid GPS fix is available.")
                .font(.subheadline)
                .foregroundColor(.prussianBlueLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.prussianBlueLight)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.85))
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
                    .foregroundColor(.prussianBlueDark)
                Spacer()
                Text(time)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.prussianBlueDark)
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
                let interval = next.time.timeIntervalSince(now)
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.label)
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
        .background(Color.prussianBlue)
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
