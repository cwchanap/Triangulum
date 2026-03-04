# F2.3 Sunrise/Sunset & Golden Hour — Design Document

**Date:** 2026-03-03
**Feature:** F2.3 from PRD-Feature-Roadmap.md
**Status:** Approved, ready for implementation

---

## Overview

Add a dedicated `SolarEventsView` page to Triangulum that displays the full timeline of solar events for any date — astronomical/nautical/civil twilight, blue hour, sunrise/sunset, and golden hour — with a live countdown to the next upcoming event and day-by-day date navigation.

---

## Requirements

| ID | Requirement | Priority | Included |
|----|-------------|----------|---------|
| F2.3.1 | Sunrise and sunset times | Must Have | ✅ |
| F2.3.2 | Civil, nautical, astronomical twilight | Should Have | ✅ |
| F2.3.3 | Golden hour start/end times | Must Have | ✅ |
| F2.3.4 | Blue hour timing | Should Have | ✅ |
| F2.3.5 | Countdown to next solar event | Should Have | ✅ |
| F2.3.6 | Integrate with constellation map | Should Have | Deferred |

F2.3.6 (ConstellationMapView header integration) is deferred to a follow-up — the `SolarDay` struct can be reused then.

---

## Architecture

### New types

**`SolarDay` (value struct, in `SolarEventsView.swift`)**

Pre-computes all solar event times for a given date and observer location by calling `Astronomer.solarCrossing(...)` for each altitude threshold. A nil value means the event does not occur (e.g. midnight sun / polar night).

```swift
struct SolarDay {
    let date: Date
    let latitude: Double
    let longitude: Double

    // Morning (rising crossings)
    let astronomicalDawn: Date?    // Sun at -18°, rising
    let nauticalDawn: Date?        // Sun at -12°, rising
    let civilDawn: Date?           // Sun at  -6°, rising  (blue hour begins)
    let sunrise: Date?             // Sun at -0.833°, rising (golden hour begins)
    let morningGoldenEnd: Date?    // Sun at  +6°, rising

    // Evening (setting crossings)
    let eveningGoldenStart: Date?  // Sun at  +6°, setting
    let sunset: Date?              // Sun at -0.833°, setting (blue hour begins)
    let civilDusk: Date?           // Sun at  -6°, setting  (blue hour ends)
    let nauticalDusk: Date?        // Sun at -12°, setting
    let astronomicalDusk: Date?    // Sun at -18°, setting
}
```

**`Astronomer.solarCrossing(altitudeDeg:rising:date:latDeg:lonDeg:) -> Date?` (new static method)**

Analytical calculation of when the Sun crosses a given altitude threshold on a given date. Uses the same hour-angle formula as `nextPlanetEvent`:

```
cos(H) = (sin(h) - sin(lat)·sin(dec)) / (cos(lat)·cos(dec))
```

- `altitudeDeg`: target altitude (negative = below horizon)
- `rising`: true for the morning crossing, false for evening
- Returns `nil` when `|cosH| > 1` (circumpolar / never rises at this altitude for this lat/date)
- Returns a `Date` in the local calendar for the given date's day

### Modified files

**`ConstellationMapView.swift`** — add `Astronomer.solarCrossing(...)` static method to the `Astronomer` enum.

**`ContentView.swift`** — add `NavigationLink` to `SolarEventsView` in the toolbar (sun icon: `"sun.max.fill"`), passing `locationManager`.

### New files

**`Triangulum/Views/SolarEventsView.swift`** — the complete view, containing:
- `SolarDay` struct
- `SolarEventsView` body
- `SolarEventRow` subview (icon + label + time string)
- `SolarCountdownCard` subview (live countdown)

**`TriangulumTests/SolarEventsTests.swift`** — unit tests for `solarCrossing` and `SolarDay`.

---

## UI Layout

```
┌─────────────────────────────────────────┐
│ [← Back]    Solar Events   [◀][Today][▶]│  nav bar
├─────────────────────────────────────────┤
│  Monday, March 3, 2026                  │
│  📍 37.3382°, -122.0274°                │
├─────────────────────────────────────────┤
│  ⏱  Sunset in  2h 34m                  │  countdown card (live)
├─────────────────────────────────────────┤
│  MORNING                                │  Section header
│  🌑  Astronomical twilight    05:12     │  greyed if past
│  🌒  Nautical twilight        05:43     │
│  🔵  Blue hour begins         06:14     │  blue accent
│  🌅  Sunrise · Golden hour    06:42     │  orange accent
│  ☀️   Golden hour ends         07:38    │  orange accent
├─────────────────────────────────────────┤
│  EVENING                                │
│  ☀️   Golden hour begins       18:15   │  orange accent
│  🌇  Sunset · Blue hour        19:11   │  orange accent
│  🔵  Blue hour ends            19:39   │  blue accent
│  🌒  Nautical twilight ends    20:10   │
│  🌑  Astronomical twilight     20:41   │
└─────────────────────────────────────────┘
```

### Interaction details

- **Date navigation**: `◀` / `▶` chevron buttons advance by one day; "Today" button resets to current date. Buttons are plain `Button` views in `navigationBarTrailing` or a custom date row.
- **Countdown card**: Updates every 60 seconds via `Timer.publish`. Shows the next upcoming event: "Sunset in 2h 34m" or "Sunrise tomorrow in 11h 02m" (crosses midnight gracefully). When there is no next event today (polar night scenario), shows "No events today".
- **Past event dimming**: When `selectedDate` is today, events whose time is before `now` are rendered at 0.4 opacity.
- **Nil event handling**: If a crossing returns nil (e.g. polar night at -18°), that row is omitted from the list.
- **Location display**: Shows `lat, lon` rounded to 4 decimal places (matches ConstellationMapView header style).
- **Timezone**: All times displayed in device local timezone (matching existing app behavior).

### Color accents

| Event type | Accent color |
|------------|-------------|
| Golden hour rows | `.orange` / warm gold |
| Blue hour rows | `.blue` |
| Twilight rows | default text color |
| Countdown card | `.prussianBlue` background, white text |

---

## Solar Event Thresholds

| Event | Sun altitude | Notes |
|-------|-------------|-------|
| Astronomical twilight | −18° | Sky fully dark |
| Nautical twilight | −12° | Horizon faintly visible |
| Civil twilight / blue hour | −6° | Enough light to work outside |
| Sunrise / Sunset | −0.833° | Standard (accounts for refraction + disc radius) |
| Golden hour end/start | +6° | Approximate; soft directional light |

---

## Data Flow

```
locationManager.latitude/longitude (ObservedObject)
selectedDate (@State, default today)
       ↓
SolarDay.init(date:latitude:longitude:)
  ↓ calls Astronomer.solarCrossing(altitudeDeg:rising:date:latDeg:lonDeg:)
  ↓ for each of the 10 crossing combinations
       ↓
SolarEventsView renders:
  SolarCountdownCard (next event, Timer 60s)
  SolarEventRow × N (each non-nil event)
```

---

## Testing Plan

**`TriangulumTests/SolarEventsTests.swift`**

- `testSolarCrossingReturnsNilAboveArctic`: lat=89°, -18° crossing → nil
- `testSolarCrossingReturnsSunriseInValidRange`: known date at mid-latitude → Date within ±30 min of tabulated value
- `testSolarDayEventsAreInChronologicalOrder`: all non-nil morning events < noon < all non-nil evening events
- `testSolarDayAllNilAtPolarNight`: lat=90°, December 21 → all nils
- `testGoldenHourEndsAfterSunrise`: morningGoldenEnd > sunrise
- `testCountdownNextEventIsFirstUpcoming`: given a known time, nextEvent returns the correct upcoming entry

---

## Files to Create / Modify

| File | Action |
|------|--------|
| `Triangulum/Views/SolarEventsView.swift` | Create |
| `Triangulum/Views/ConstellationMapView.swift` | Modify — add `Astronomer.solarCrossing` |
| `Triangulum/Views/ContentView.swift` | Modify — add toolbar NavigationLink |
| `TriangulumTests/SolarEventsTests.swift` | Create |
