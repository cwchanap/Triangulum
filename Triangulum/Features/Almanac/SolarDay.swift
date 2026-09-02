//
//  SolarDay.swift
//  Triangulum
//
//  F2.3 — Sunrise/Sunset & Golden Hour (destination-aware)
//

import Foundation

// MARK: - SolarEventKind

/// The ten daily solar thresholds, in morning→evening order.
enum SolarEventKind: String, CaseIterable, Codable, Hashable {
    case astronomicalDawn, nauticalDawn, civilDawn, sunrise, morningGoldenEnd
    case eveningGoldenStart, sunset, civilDusk, nauticalDusk, astronomicalDusk

    var displayName: String {
        switch self {
        case .astronomicalDawn: "Astronomical dawn"
        case .nauticalDawn: "Nautical dawn"
        case .civilDawn: "Civil dawn"
        case .sunrise: "Sunrise"
        case .morningGoldenEnd: "Golden hour ends"
        case .eveningGoldenStart: "Golden hour begins"
        case .sunset: "Sunset"
        case .civilDusk: "Civil dusk"
        case .nauticalDusk: "Nautical dusk"
        case .astronomicalDusk: "Astronomical dusk"
        }
    }
}

enum SolarState: Equatable { case normal, polarDay, polarNight }
struct SolarEvent: Equatable { let kind: SolarEventKind; let instant: Date }

// MARK: - SolarDay

/// All solar event times for a destination-local calendar day and observer location.
/// Missing events mean the Sun never reaches that altitude (polar day/night).
struct SolarDay {
    let date: LocalDate
    let timeZone: TimeZone
    let latitude: Double
    let longitude: Double
    /// Polar classification, resolved from noon altitude when both -0.833° crossings are absent.
    let state: SolarState
    private let eventsByKind: [SolarEventKind: SolarEvent]

    init(date: LocalDate, timeZone: TimeZone, latitude: Double, longitude: Double) throws {
        self.date = date
        self.timeZone = timeZone
        self.latitude = latitude
        self.longitude = longitude

        let crossings: [(kind: SolarEventKind, altitudeDeg: Double, rising: Bool)] = [
            (.astronomicalDawn, -18.0, true),   // Sun at -18° rising — sky turns from black to deep blue
            (.nauticalDawn, -12.0, true),       // Sun at -12° rising — horizon faintly visible
            (.civilDawn, -6.0, true),           // Sun at  -6° rising
            (.sunrise, -0.833, true),           // Sun at -0.833° rising — golden hour begins
            (.morningGoldenEnd, 6.0, true),     // Sun at  +6° rising — golden hour ends
            (.eveningGoldenStart, 6.0, false),  // Sun at  +6° setting — golden hour begins
            (.sunset, -0.833, false),           // Sun at -0.833° setting — golden hour ends
            (.civilDusk, -6.0, false),          // Sun at  -6° setting
            (.nauticalDusk, -12.0, false),      // Sun at -12° setting
            (.astronomicalDusk, -18.0, false)   // Sun at -18° setting — sky fully dark
        ]
        var events: [SolarEventKind: SolarEvent] = [:]
        for crossing in crossings {
            guard let instant = ConstellationMapView.Astronomer.solarCrossing(
                altitudeDeg: crossing.altitudeDeg,
                rising: crossing.rising,
                localDate: date,
                timeZone: timeZone,
                latDeg: latitude,
                lonDeg: longitude
            ) else { continue }
            events[crossing.kind] = SolarEvent(kind: crossing.kind, instant: instant)
        }
        self.eventsByKind = events

        // Both -0.833° crossings absent → polar day or night, classified by noon altitude.
        if events[.sunrise] == nil && events[.sunset] == nil {
            let noon = try date.noon(in: timeZone)
            let sun = ConstellationMapView.Astronomer.sunEquatorial(date: noon)
            let lst = ConstellationMapView.Astronomer.localSiderealTime(date: noon, longitude: longitude)
            let noonAltitude = ConstellationMapView.Astronomer.altAz(eq: sun, lstHours: lst, latDeg: latitude).altDeg
            state = noonAltitude > -0.833 ? .polarDay : .polarNight
        } else {
            state = .normal
        }
    }

    /// The time of `kind` on this day, or nil when the Sun never reaches that altitude.
    func event(_ kind: SolarEventKind) -> Date? {
        eventsByKind[kind]?.instant
    }

    /// All non-nil events sorted chronologically.
    var allEvents: [SolarEvent] {
        eventsByKind.values.sorted { $0.instant < $1.instant }
    }

    /// The first event after `now`, or nil if all events are in the past.
    func nextEvent(after now: Date) -> SolarEvent? {
        allEvents.first { $0.instant > now }
    }
}
