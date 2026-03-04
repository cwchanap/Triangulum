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
    let sunset: Date?              // Sun at -0.833° setting — blue hour begins
    let civilDusk: Date?           // Sun at  -6° setting — blue hour ends
    let nauticalDusk: Date?        // Sun at -12° setting
    let astronomicalDusk: Date?    // Sun at -18° setting — sky fully dark

    init(date: Date, latitude: Double, longitude: Double) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude

        let sc = ConstellationMapView.Astronomer.solarCrossing
        astronomicalDawn   = sc(-18.0,   true,  date, latitude, longitude)
        nauticalDawn       = sc(-12.0,   true,  date, latitude, longitude)
        civilDawn          = sc( -6.0,   true,  date, latitude, longitude)
        sunrise            = sc( -0.833, true,  date, latitude, longitude)
        morningGoldenEnd   = sc(  6.0,   true,  date, latitude, longitude)
        eveningGoldenStart = sc(  6.0,   false, date, latitude, longitude)
        sunset             = sc( -0.833, false, date, latitude, longitude)
        civilDusk          = sc( -6.0,   false, date, latitude, longitude)
        nauticalDusk       = sc(-12.0,   false, date, latitude, longitude)
        astronomicalDusk   = sc(-18.0,   false, date, latitude, longitude)
    }

    /// All non-nil events sorted chronologically.
    var allEvents: [(label: String, time: Date)] {
        let raw: [(String, Date?)] = [
            ("Astronomical twilight",       astronomicalDawn),
            ("Nautical twilight",           nauticalDawn),
            ("Blue hour begins",            civilDawn),
            ("Sunrise",                     sunrise),
            ("Golden hour ends",            morningGoldenEnd),
            ("Golden hour begins",          eveningGoldenStart),
            ("Sunset",                      sunset),
            ("Blue hour ends",              civilDusk),
            ("Nautical twilight ends",      nauticalDusk),
            ("Astronomical twilight ends",  astronomicalDusk),
        ]
        return raw.compactMap { label, time in time.map { (label, $0) } }
               .sorted { $0.time < $1.time }
    }

    /// The first event after `now`, or nil if all events are in the past.
    func nextEvent(after now: Date) -> (label: String, time: Date)? {
        allEvents.first { $0.time > now }
    }
}

// MARK: - SolarEventsView (placeholder — full UI in Task 3)

struct SolarEventsView: View {
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        Text("Solar Events — coming in Task 3")
            .navigationTitle("Solar Events")
    }
}
