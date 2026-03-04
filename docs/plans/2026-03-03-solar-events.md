# F2.3 Solar Events (Sunrise/Sunset & Golden Hour) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `SolarEventsView` page showing the full solar timeline (twilight, golden hour, blue hour) with a live countdown and day-by-day date navigation.

**Architecture:** Extend `Astronomer` (inside `ConstellationMapView.swift`) with a `solarCrossing` method. Introduce a `SolarDay` value struct that pre-computes all 10 crossing times. `SolarEventsView` owns the date/time state and renders two sections (Morning, Evening) plus a live countdown card. No manager class needed — pure math.

**Tech Stack:** SwiftUI, Swift Testing (`import Testing`), existing `Astronomer` enum in `ConstellationMapView.swift`, `Color+Theme.swift` palette, `LocationManager` for lat/lon.

---

## Context You Must Know

### Key files
- `Triangulum/Views/ConstellationMapView.swift` — contains the `Astronomer` enum (lines ~547–974). Add new methods inside this enum. It also contains nested types `Equatorial`, `AltAz`, `Observer` used by the math.
- `Triangulum/Views/ContentView.swift` — toolbar at lines 87–126. New `NavigationLink` goes here alongside the existing star/compass/gear/footprint links.
- `Triangulum/Extensions/Color+Theme.swift` — Prussian Blue palette. Use `.prussianBlue`, `.prussianBlueLight`, `.prussianBlueDark`, `.prussianSoft`, `.prussianWarning` (orange), `.prussianAccent` (blue).
- `TriangulumTests/PlanetTests.swift` — example test file showing the `import Testing` + `#expect()` pattern.

### Build command
```bash
xcodebuild build -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A'
```

### Test command
```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests
```

### Existing `Astronomer` pattern to follow
The `nextPlanetEvent` method already implements the same hour-angle formula. `solarCrossing` is a focused variant: one body (the Sun), one altitude threshold, one direction (rising or setting), one calendar date.

```swift
// Existing pattern for reference (lines ~929–973 in ConstellationMapView.swift):
static func nextPlanetEvent(planets:date:latDeg:lonDeg:) -> PlanetEvent?
// Uses: localSiderealTime, sunEquatorial, cos(H) = (sin(h) - sin(lat)*sin(dec)) / (cos(lat)*cos(dec))
```

### Solar thresholds
| Event | `altitudeDeg` | `rising` |
|-------|--------------|---------|
| Astronomical dawn/dusk | -18.0 | true / false |
| Nautical dawn/dusk | -12.0 | true / false |
| Civil dawn/dusk (blue hour boundary) | -6.0 | true / false |
| Sunrise / Sunset | -0.833 | true / false |
| Morning golden end / Evening golden start | 6.0 | true / false |

---

## Task 1: Add `Astronomer.solarCrossing` — tests first

**Files:**
- Create: `TriangulumTests/SolarEventsTests.swift`
- Modify: `Triangulum/Views/ConstellationMapView.swift` (inside `Astronomer` enum, after `moonAgeDays`)

### Step 1: Create the test file with failing tests

Create `TriangulumTests/SolarEventsTests.swift`:

```swift
//
//  SolarEventsTests.swift
//  TriangulumTests
//

import Testing
import Foundation
@testable import Triangulum

struct SolarEventsTests {

    // San Francisco, March 3 2026 — mid-latitude, well-defined sunrise/set
    let sfLat = 37.7749
    let sfLon = -122.4194
    // Unix timestamp for 2026-03-03 local noon in San Francisco (UTC-8 in winter = 20:00 UTC)
    // 2026-03-03 20:00 UTC = 1741032000
    let march3: Date = Date(timeIntervalSince1970: 1741032000)

    // MARK: - solarCrossing nil for polar conditions

    @Test func testCircumpolarReturnsNilForAstronomicalTwilight() {
        // At lat=89°, the Sun never dips to -18° in summer — should return nil for some date
        // Use June 21 (summer solstice), when Arctic has midnight sun
        let summerSolstice = Date(timeIntervalSince1970: 1750291200) // ~2025-06-19 UTC
        let result = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -18.0, rising: true,
            date: summerSolstice, latDeg: 89.0, lonDeg: 0.0
        )
        #expect(result == nil)
    }

    @Test func testNeverRisesReturnsNil() {
        // At lat=-89°, the Sun never rises above -18° in June (polar night for South Pole)
        let summerSolstice = Date(timeIntervalSince1970: 1750291200)
        let result = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: summerSolstice, latDeg: -89.0, lonDeg: 0.0
        )
        #expect(result == nil)
    }

    // MARK: - solarCrossing approximate correctness

    @Test func testSunriseIsBeforeNoon() {
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        #expect(sunrise != nil)
        if let t = sunrise {
            // Sunrise in SF in March is around 06:30-07:00 local time.
            // Verify it falls in the morning hours (before noon).
            let cal = Calendar.current
            let hour = cal.component(.hour, from: t)
            #expect(hour >= 5 && hour <= 9)
        }
    }

    @Test func testSunsetIsAfterNoon() {
        let sunset = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: false,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        #expect(sunset != nil)
        if let t = sunset {
            let cal = Calendar.current
            let hour = cal.component(.hour, from: t)
            #expect(hour >= 17 && hour <= 21)
        }
    }

    @Test func testSunriseBeforeSunset() {
        let sunrise = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: true,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        let sunset = ConstellationMapView.Astronomer.solarCrossing(
            altitudeDeg: -0.833, rising: false,
            date: march3, latDeg: sfLat, lonDeg: sfLon
        )
        if let rise = sunrise, let set = sunset {
            #expect(rise < set)
        }
    }

    @Test func testTwilightOrderIsCorrect() {
        // astronomical < nautical < civil < sunrise
        let astro   = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -18.0,  rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let nautical = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -12.0, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let civil    = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -6.0,  rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let sunrise  = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -0.833, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        if let a = astro, let n = nautical, let c = civil, let s = sunrise {
            #expect(a < n)
            #expect(n < c)
            #expect(c < s)
        }
    }

    @Test func testGoldenHourEndIsAfterSunrise() {
        let sunrise    = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: -0.833, rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        let goldenEnd  = ConstellationMapView.Astronomer.solarCrossing(altitudeDeg: 6.0,   rising: true, date: march3, latDeg: sfLat, lonDeg: sfLon)
        if let s = sunrise, let g = goldenEnd {
            #expect(s < g)
        }
    }
}
```

### Step 2: Run the tests — expect BUILD FAILED (method doesn't exist yet)

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD FAILED` with `error: type 'ConstellationMapView.Astronomer' has no member 'solarCrossing'`

### Step 3: Add `solarCrossing` to `Astronomer` in `ConstellationMapView.swift`

In `ConstellationMapView.swift`, locate the closing `}` of `moonAgeDays` (around line 777). Insert the following block **before** the `// MARK: - Planet Positions` comment:

```swift
        // MARK: - Solar Crossings (for SolarEventsView)

        /// Returns the time on `date`'s calendar day when the Sun crosses `altitudeDeg`.
        /// - Parameters:
        ///   - altitudeDeg: Target altitude (negative = below horizon). e.g. -0.833 for sunrise.
        ///   - rising: true = morning crossing, false = evening crossing.
        ///   - date: Any moment on the target calendar day (local calendar used).
        ///   - latDeg: Observer latitude in degrees.
        ///   - lonDeg: Observer longitude in degrees.
        /// - Returns: nil if the Sun never reaches this altitude on this date (polar day/night).
        static func solarCrossing(
            altitudeDeg: Double,
            rising: Bool,
            date: Date,
            latDeg: Double,
            lonDeg: Double
        ) -> Date? {
            let rad = Double.pi / 180.0
            let latRad = latDeg * rad

            // Use local calendar noon as reference (Sun's Dec changes slowly; good approx for the day)
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            comps.hour = 12; comps.minute = 0; comps.second = 0; comps.nanosecond = 0
            guard let localNoon = Calendar.current.date(from: comps) else { return nil }

            let sunEq = sunEquatorial(date: localNoon)
            let decRad = sunEq.decDeg * rad

            // Hour angle H for the target altitude: cos(H) = (sin(h) - sin(lat)·sin(dec)) / (cos(lat)·cos(dec))
            let sinH = sin(altitudeDeg * rad)
            let cosHdenom = cos(latRad) * cos(decRad)
            guard abs(cosHdenom) > 1e-6 else { return nil }
            let cosH = (sinH - sin(latRad) * sin(decRad)) / cosHdenom
            guard cosH >= -1.0 && cosH <= 1.0 else { return nil }
            let H = acos(cosH) * 12.0 / Double.pi   // hours

            // Solar transit: when hour angle = 0 → LST = RA_sun
            let lst = localSiderealTime(date: localNoon, longitude: lonDeg)
            var transitOffset = sunEq.raHours - lst
            transitOffset = transitOffset.truncatingRemainder(dividingBy: 24)
            // Normalize to ±12h so transit stays close to noon
            if transitOffset > 12 { transitOffset -= 24 }
            if transitOffset < -12 { transitOffset += 24 }
            let transitDate = localNoon.addingTimeInterval(transitOffset * 3600)

            // Rising = transit − H, Setting = transit + H
            return transitDate.addingTimeInterval((rising ? -H : H) * 3600)
        }
```

### Step 4: Run tests — expect PASS

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests 2>&1 | grep -E "Test Case|SUCCEEDED|FAILED"
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add Triangulum/Views/ConstellationMapView.swift TriangulumTests/SolarEventsTests.swift
git commit -m "feat: add Astronomer.solarCrossing for solar event time calculations"
```

---

## Task 2: Create `SolarDay` struct

**Files:**
- Create (skeleton): `Triangulum/Views/SolarEventsView.swift`

`SolarDay` lives in the same file as `SolarEventsView`. Create the file now so the tests from Task 1 can reference `SolarDay`.

### Step 1: Add `SolarDay` tests to `SolarEventsTests.swift`

Append to `TriangulumTests/SolarEventsTests.swift`:

```swift
// MARK: - SolarDay Tests

struct SolarDayTests {

    let sfLat = 37.7749
    let sfLon = -122.4194
    let march3: Date = Date(timeIntervalSince1970: 1741032000)

    @Test func testSolarDayEventsAreChronological() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        let times = [
            day.astronomicalDawn, day.nauticalDawn, day.civilDawn,
            day.sunrise, day.morningGoldenEnd,
            day.eveningGoldenStart, day.sunset,
            day.civilDusk, day.nauticalDusk, day.astronomicalDusk
        ].compactMap { $0 }
        for i in 1..<times.count {
            #expect(times[i-1] < times[i], "Events out of order at index \(i)")
        }
    }

    @Test func testSolarDayAllNilAtNorthPoleInWinter() {
        // December 21 — polar night at 89°N, Sun never rises above -0.833°
        let dec21 = Date(timeIntervalSince1970: 1766361600) // ~2025-12-21
        let day = SolarDay(date: dec21, latitude: 89.0, longitude: 0.0)
        #expect(day.sunrise == nil)
        #expect(day.sunset == nil)
    }

    @Test func testSolarDayMorningGoldenEndAfterSunrise() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        if let rise = day.sunrise, let goldEnd = day.morningGoldenEnd {
            #expect(rise < goldEnd)
        }
    }

    @Test func testNextEventReturnsNilWhenAllPast() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        // Use a far-future "now" — after all events for the day
        let farFuture = march3.addingTimeInterval(24 * 3600)
        #expect(day.nextEvent(after: farFuture) == nil)
    }

    @Test func testNextEventReturnsFirstUpcoming() {
        let day = SolarDay(date: march3, latitude: sfLat, longitude: sfLon)
        // Use astronomical dawn as "now" — next should be nautical dawn
        if let astro = day.astronomicalDawn, let nautical = day.nauticalDawn {
            let next = day.nextEvent(after: astro.addingTimeInterval(1))
            #expect(next?.time == nautical)
        }
    }
}
```

### Step 2: Run tests — expect BUILD FAILED (`SolarDay` not defined yet)

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD FAILED` — `SolarDay` undefined.

### Step 3: Create `SolarEventsView.swift` with `SolarDay`

Create `Triangulum/Views/SolarEventsView.swift`:

```swift
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
        astronomicalDawn   = sc(altitudeDeg: -18.0,   rising: true,  date: date, latDeg: latitude, lonDeg: longitude)
        nauticalDawn       = sc(altitudeDeg: -12.0,   rising: true,  date: date, latDeg: latitude, lonDeg: longitude)
        civilDawn          = sc(altitudeDeg:  -6.0,   rising: true,  date: date, latDeg: latitude, lonDeg: longitude)
        sunrise            = sc(altitudeDeg:  -0.833, rising: true,  date: date, latDeg: latitude, lonDeg: longitude)
        morningGoldenEnd   = sc(altitudeDeg:   6.0,   rising: true,  date: date, latDeg: latitude, lonDeg: longitude)
        eveningGoldenStart = sc(altitudeDeg:   6.0,   rising: false, date: date, latDeg: latitude, lonDeg: longitude)
        sunset             = sc(altitudeDeg:  -0.833, rising: false, date: date, latDeg: latitude, lonDeg: longitude)
        civilDusk          = sc(altitudeDeg:  -6.0,   rising: false, date: date, latDeg: latitude, lonDeg: longitude)
        nauticalDusk       = sc(altitudeDeg: -12.0,   rising: false, date: date, latDeg: latitude, lonDeg: longitude)
        astronomicalDusk   = sc(altitudeDeg: -18.0,   rising: false, date: date, latDeg: latitude, lonDeg: longitude)
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
```

### Step 4: Run tests — expect PASS

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests 2>&1 | grep -E "Test Case|SUCCEEDED|FAILED"
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add Triangulum/Views/SolarEventsView.swift TriangulumTests/SolarEventsTests.swift
git commit -m "feat: add SolarDay struct with solarCrossing-based event computation"
```

---

## Task 3: Build the full `SolarEventsView` UI

**Files:**
- Modify: `Triangulum/Views/SolarEventsView.swift` (replace placeholder body)

### Step 1: Replace the placeholder `SolarEventsView` body

Replace everything after the `SolarDay` struct in `SolarEventsView.swift` with:

```swift
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

    private var solarDay: SolarDay {
        SolarDay(date: selectedDate,
                 latitude: locationManager.latitude,
                 longitude: locationManager.longitude)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard
                SolarCountdownCard(solarDay: solarDay, now: now)
                    .padding(.horizontal)
                    .padding(.top, 12)
                morningSection
                eveningSection
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
            Text(String(format: "%.4f°, %.4f°",
                        locationManager.latitude, locationManager.longitude))
                .font(.caption)
                .foregroundColor(.prussianBlueLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.85))
    }

    private var morningSection: some View {
        sectionCard(title: "MORNING") {
            if let t = solarDay.astronomicalDawn {
                SolarEventRow(icon: "moon.stars.fill", label: "Astronomical twilight",
                              time: Self.timeFormatter.string(from: t),
                              accent: .primary, isPast: isToday && t < now)
            }
            if let t = solarDay.nauticalDawn {
                SolarEventRow(icon: "moon.fill", label: "Nautical twilight",
                              time: Self.timeFormatter.string(from: t),
                              accent: .primary, isPast: isToday && t < now)
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
                              accent: .prussianWarning, isPast: isToday && t < now)
            }
        }
    }

    private var eveningSection: some View {
        sectionCard(title: "EVENING") {
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
                              accent: .primary, isPast: isToday && t < now)
            }
            if let t = solarDay.astronomicalDusk {
                SolarEventRow(icon: "moon.stars.fill", label: "Astronomical twilight",
                              time: Self.timeFormatter.string(from: t),
                              accent: .primary, isPast: isToday && t < now)
            }
        }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accent == .primary ? .prussianBlueDark : accent)
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
            Divider().padding(.leading, 52)
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
                let hours = Int(interval) / 3600
                let minutes = (Int(interval) % 3600) / 60
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.label)
                        .font(.subheadline.weight(.semibold))
                    Text("in \(hours)h \(minutes)m")
                        .font(.caption)
                        .opacity(0.85)
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
```

### Step 2: Build and verify

```bash
xcodebuild build -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` — no errors.

### Step 3: Commit

```bash
git add Triangulum/Views/SolarEventsView.swift
git commit -m "feat: implement SolarEventsView with event timeline and countdown"
```

---

## Task 4: Wire `SolarEventsView` into `ContentView` toolbar

**Files:**
- Modify: `Triangulum/Views/ContentView.swift` (lines 99–124, toolbar block)

### Step 1: Add the `NavigationLink` to `ContentView.swift`

Locate the toolbar block in `ContentView.swift`. It currently has links for ConstellationMapView, CompassPageView, PreferencesView, FootprintView (around lines 99–124). Add the `SolarEventsView` link **after** the ConstellationMapView link (after line 106):

```swift
// Add after the ConstellationMapView NavigationLink:
NavigationLink(destination: SolarEventsView(locationManager: locationManager)) {
    Image(systemName: "sun.max.fill")
        .font(.title2)
        .foregroundColor(.white)
}
```

The resulting toolbar block should look like:

```swift
ToolbarItemGroup(placement: .navigationBarTrailing) {
    Button { ... } label: { /* reorder icon */ }

    NavigationLink(destination: ConstellationMapView(
        locationManager: locationManager,
        satelliteManager: satelliteManager
    )) {
        Image(systemName: "star.fill")
            .font(.title2)
            .foregroundColor(.white)
    }

    // ← INSERT HERE
    NavigationLink(destination: SolarEventsView(locationManager: locationManager)) {
        Image(systemName: "sun.max.fill")
            .font(.title2)
            .foregroundColor(.white)
    }

    NavigationLink(destination: CompassPageView(locationManager: locationManager)) {
        Image(systemName: "location.north.fill")
            .font(.title2)
            .foregroundColor(.white)
    }

    NavigationLink(destination: PreferencesView(locationManager: locationManager)) {
        Image(systemName: "gearshape.fill")
            .font(.title2)
            .foregroundColor(.white)
    }

    NavigationLink(destination: FootprintView(snapshotManager: snapshotManager)) {
        Image(systemName: "location.fill")
            .font(.title2)
            .foregroundColor(.white)
    }
}
```

### Step 2: Build and verify

```bash
xcodebuild build -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Run full unit test suite (excluding the pre-existing failing satellite test)

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,arch=arm64,id=8C62B7B3-4164-4AA9-9348-530977CE965A' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests \
  -skip-testing:TriangulumTests/SatelliteTests/testNextPassDebouncesWorkItem \
  2>&1 | grep -E "Test Case.*failed|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`

### Step 4: Commit

```bash
git add Triangulum/Views/ContentView.swift
git commit -m "feat: add SolarEventsView navigation link to toolbar"
```

---

## Done — Verification Checklist

After all tasks complete, verify manually in the simulator:

- [ ] Sun icon appears in the toolbar on the main screen
- [ ] Tapping it opens SolarEventsView with today's date
- [ ] All 10 events appear (or fewer if some are nil for your location)
- [ ] Events are in chronological order
- [ ] Countdown card shows a sensible "X in Yh Zm" message
- [ ] Tapping `‹` shows yesterday's events
- [ ] Tapping `›` then shows today again (and "Today" button disappears)
- [ ] Tapping "Today" returns to current date
- [ ] Past events are dimmed when viewing today
- [ ] Night vision mode is NOT needed here (no ConstellationMapView integration)
