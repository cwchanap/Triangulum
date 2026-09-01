# Almanac Sun and Tide Tab

**Date:** 2026-09-01  
**Branch:** `docs/almanac-sun-tides-design`  
**Status:** Approved for implementation planning

## Summary

Add a fifth primary tab, **Almanac**, to Triangulum. The tab combines worldwide
solar events with predicted tides for Canada, the United States, Japan, and
Hong Kong. A shared Almanac-only location and rolling seven-day date strip drive
two sections: **Sun** and **Tides**.

The first release remains deliberately narrow:

- Solar events are calculated locally for any valid coordinate.
- Tide predictions come directly from official regional sources.
- Tide values are predictions only; live observations are out of scope.
- The nearest eligible tide station is selected automatically, with a manual
  override when another nearby station is more representative.
- Complete normalized tide weeks are cached on device and remain usable offline.
- No backend, provider registry, favourites system, or SwiftData migration is
  introduced.

## Problem

Triangulum already calculates sunrise, sunset, twilight, and golden-hour events,
but the feature is reachable only through a small **Solar** utility tile and is
bound to the device's current GPS coordinate. It cannot support planning for a
remote place.

The app also has no tide display. Users planning photography, hiking, coastal
visits, or travel need daylight and predicted tide information for the same
place and local calendar day.

## Goals

1. Provide one first-class Almanac tab for location- and date-based natural
   events.
2. Let the user follow the device location or select one searched, fixed
   location without changing the Live dashboard's sensor context.
3. Show sunrise, sunset, daylight duration, twilight, and golden hour in the
   selected location's local time.
4. Show the next predicted tide, a daily hourly curve, exact high/low events,
   and source-station details for Canada, the United States, Japan, and Hong
   Kong.
5. Auto-select a useful nearby station while allowing a remembered manual
   override.
6. Remain useful offline after a station/week has been loaded once.
7. Keep the implementation maintainable and proportionate for a hobby project.

## Non-goals

The first release excludes:

- live or historical observed water levels;
- tidal currents, waves, marine weather, surge, and safety alerts;
- tide coverage outside Canada, the United States, Japan, and Hong Kong;
- notifications, widgets, calendar integration, and background refresh;
- multiple saved locations, favourites, folders, and location management;
- a station map;
- NOAA subordinate prediction stations;
- cross-datum conversion or comparisons between stations;
- harmonic prediction calculations performed by Triangulum;
- synthetic 15-minute values or minute-level precision claims;
- chart scrubbing, pinch zooming, and multi-day overlays;
- a backend, scheduled data pipeline, dependency-injection container, or
  runtime provider/plugin registry;
- a SwiftData schema change or backward-compatibility migration.

## Product structure

### Primary navigation

The tab order becomes:

```text
Live · Field · Almanac · Footprint · Settings
```

`Almanac` sits between `Field` and `Footprint`. The existing **Solar** tile is
removed from the Live dashboard, and `SolarEventsView` is retired after feature
parity is reached. Almanac becomes the single user-facing home for solar events.

`ProductTab` stays in `FieldHubView.swift`; add `.almanac` rather than moving the
enum solely for architectural neatness. Use the stable `calendar` SF Symbol.

### Almanac layout

The root screen contains shared context followed by a segmented section picker:

```text
ALMANAC

Vancouver, BC                           Change
Current Location
Pacific Daylight Time · UTC−7

‹ 7 days      1  2  3  4  5  6  7      7 days ›
                              Today

                         Sun | Tides
```

Location, time-zone context, and the seven-day strip remain visible when the
user switches sections. Both sections therefore describe the same selected
place and civil calendar date.

On each app launch Almanac restores the location mode and last fixed location,
then opens on "today" at that destination and defaults to **Sun**. The previous
selected date and active section are not persisted.

## State and local-time model

### Local civil date

Do not represent the selected Almanac day as device-local midnight. Introduce a
small Codable value:

```swift
struct LocalDate: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int
}

struct LocalDateRange: Codable, Hashable {
    let start: LocalDate
    let endInclusive: LocalDate
}
```

Calendar calculations use an explicit Gregorian `Calendar` and `TimeZone`.
This prevents Tokyo, Vancouver, and Hong Kong from silently sharing the
phone's day boundary.

The selected `LocalDate` is interpreted in the Almanac location time zone for
Sun and in the chosen station time zone for Tides. Tide and solar crossings are
stored as absolute `Date` instants. A daylight-saving transition may therefore
produce 23 or 25 hourly tide points; the model must not force exactly 24.

### Almanac location

```swift
enum AlmanacLocationMode: String, Codable {
    case current
    case selected
}

struct AlmanacLocation: Codable, Hashable {
    let mode: AlmanacLocationMode
    let latitude: Double
    let longitude: Double
    let displayName: String
    let timeZoneIdentifier: String
    let countryCode: String?
    let administrativeArea: String?
}
```

`AlmanacViewModel` owns this state. In **Current Location** mode it follows the
shared `LocationManager`; in **Selected Location** mode it stays fixed until the
user changes it. Changing Almanac location must not alter weather, maps,
satellites, snapshots, or any other Live sensor state.

Persist one Codable `UserDefaults` payload containing only:

- current versus selected mode;
- the last valid fixed location;
- a manual tide-station override and the coordinate where it was selected.

Do not add a SwiftData entity.

### Location search and GPS resolution

Reuse `AppleSearchCompleter` for suggestions and resolve a selected completion
through MapKit into:

- display name;
- coordinate;
- time-zone identifier;
- country code;
- administrative area.

If the first search result has no time zone, reverse-geocode its coordinate
once. Reject the selection with a clear error when the second lookup still has
no time zone; never fall back to the device time zone for a remote place.

For Current Location, reverse-geocode after the first valid GPS fix and again
only after movement of at least 5 km. Reuse the last placemark context for
smaller movement.

Changing to a different fixed location:

1. stores the new Almanac location;
2. resets the selected date to today at that destination;
3. resets the rolling seven-day window to start on that date;
4. clears the manual station override;
5. recalculates solar events immediately;
6. resolves tide coverage and the nearest station when Tides is needed.

When location permission is denied or restricted, show the existing Settings
remediation. Do not silently use stale GPS coordinates.

## Solar design

### Calculation boundary

Move `SolarDay` from `SolarEventsView.swift` into the Almanac feature. Preserve
all current thresholds and calculations:

- astronomical twilight: −18°;
- nautical twilight: −12°;
- civil twilight: −6°;
- sunrise/sunset: −0.833°;
- golden-hour boundary: +6°.

Change `ConstellationMapView.Astronomer.solarCrossing` to accept an explicit
`LocalDate` and `TimeZone` rather than reading `Calendar.current`.

`SolarDay` exposes the ten existing events, daylight duration, chronological
lookup, and an explicit state:

```swift
enum SolarState {
    case normal
    case polarDay
    case polarNight
}
```

When sunrise and sunset are both absent, determine polar day versus polar night
from the Sun altitude at destination-local noon. Do not treat every missing
crossing as one generic error.

### Sun presentation

Lead with three primary values:

```text
SUN · TUESDAY, SEPTEMBER 1

Sunrise          Daylight          Sunset
06:24            13h 31m           19:55
```

Below them, show a simple explanatory daylight track using civil dawn, sunrise,
sunset, and civil dusk. It is not a sky simulation.

For today at the destination, show the next solar event and a countdown updated
at most once per minute. Omit countdown language for other dates.

Retain the full event timeline below the summary:

```text
MORNING
Astronomical dawn
Nautical dawn
Civil dawn
Sunrise
Golden hour ends

EVENING
Golden hour begins
Sunset
Civil dusk
Nautical dusk
Astronomical dusk
```

Sunrise, sunset, and golden-hour rows receive stronger visual emphasis.
Solar calculations remain available worldwide even when Tides is unsupported.

## Tide architecture

### Closed provider boundary

`AlmanacViewModel` talks to one `TideService`:

```text
AlmanacViewModel
        |
        v
    TideService
        |-- TideCoverageResolver
        |-- TideStationSelector
        |-- TideStationTimeZoneResolver
        |-- TideDiskCache
        `-- explicit TideProvider switch
              |-- CanadaTideClient
              |-- UnitedStatesTideClient
              |-- JapanTideClient
              `-- HongKongTideClient
```

Each regional client conforms to one small internal protocol:

```swift
protocol TideProviderClient: Sendable {
    var provider: TideProvider { get }
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(
        station: TideStation,
        range: LocalDateRange
    ) async throws -> TideWeek
}
```

Production selection is an explicit switch over the closed `TideProvider` enum.
Do not build runtime registration, generic plugins, or a broad data-source
framework. Clients receive an injected `URLSession`; automated tests use local
fixtures through a custom `URLProtocol` and never call public services.

### Normalized model

```swift
enum TideProvider: String, Codable {
    case canadaCHS
    case unitedStatesNOAA
    case japanJMA
    case hongKongHKO
}

struct TideStation: Identifiable, Codable, Hashable {
    let id: String
    let provider: TideProvider
    let providerStationCode: String
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String?
    let datumLabel: String
    let supportsHourlyCurve: Bool
}

struct TideSample: Codable, Hashable {
    let instant: Date
    let heightMetres: Double
}

struct TideEvent: Codable, Hashable {
    enum Kind: String, Codable {
        case high
        case low
    }

    let kind: Kind
    let instant: Date
    let heightMetres: Double
}

struct TideWeek: Codable, Hashable {
    let station: TideStation
    let localDateRange: LocalDateRange
    let hourlySamples: [TideSample]
    let events: [TideEvent]
    let fetchedAt: Date
    let sourceAttribution: String
}
```

Provider catalogues may omit an IANA time-zone identifier. In particular, NOAA's
station collection exposes an offset rather than an IANA zone. After the nearest
station is selected, `TideService` resolves that station coordinate through one
injected Core Location resolver, stores the enriched station in the cached
catalogue, and only then requests predictions. This is one lookup per selected
unresolved station, not a reverse-geocode pass over the entire catalogue.

A complete `TideWeek` must always contain a station with a valid time zone.

Normalize heights to metres while preserving the provider's datum label.
Triangulum does not convert datums or imply that values from different stations
are directly comparable.

The chart line connects official hourly points. Exact high/low markers are
stored independently and may occur between those points. The UI must not claim
that line segments represent official minute-level predictions.

## Regional tide sources

### Canada — Canadian Hydrographic Service IWLS

Use the Canadian Hydrographic Service Integrated Water Level System REST API.
Load the official station catalogue and retain stations that can supply both an
hourly prediction series and exact high/low events. Request one normalized
seven-day range, using the documented hourly prediction and high/low series.

Display `Canadian Hydrographic Service`, retain the station datum, include the
required derivative-product notice, and show the non-navigation warning.

### United States — NOAA CO-OPS

Use the NOAA CO-OPS Metadata API for the tide-prediction catalogue and the Data
Retrieval API for predictions.

Retain only reference/harmonic stations (`type == "R"`) with a non-empty U.S.
state or territory code. Subordinate stations (`type == "S"`) are excluded
because they cannot supply the required hourly curve. Do not expose NOAA's
international `TEC`/`TWC` catalogue as U.S. coverage.

A complete week uses two prediction requests:

```text
product=predictions
application=Triangulum
station=<id>
datum=MLLW
time_zone=gmt
units=metric
format=json
interval=h
```

and the same request with `interval=hilo`.

GMT avoids ambiguous source timestamps across daylight-saving transitions.
Resolve the selected station's IANA time zone through the shared selected-station
resolver before converting and displaying those instants. Preserve `MLLW` and
show `NOAA CO-OPS` attribution.

### Japan — Japan Meteorological Agency

Use the official annual fixed-width tide-table files:

```text
https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/{YEAR}/{STATION}.txt
```

Each daily line contains 24 hourly predicted heights plus up to four exact highs
and four exact lows. Parse the published 136-byte layout with byte-safe ASCII
slices, interpret times in `Asia/Tokyo`, convert centimetres to metres, and
preserve the JMA tide-table datum.

Bundle a compact station catalogue generated from every current row in the
verified annual JMA station table. Do not scrape the station page at runtime.
Cache each unmodified station/year source file and slice the requested rolling
seven-day range locally. A range crossing New Year loads two annual files.

Display `Japan Meteorological Agency` and disclose that Triangulum adapts the
JMA website data.

### Hong Kong — Hong Kong Observatory

Use the official annual open-data CSV endpoints:

- `HHOT` for predicted hourly astronomical tide heights;
- `HLT` for exact predicted high/low times and heights.

Bundle a small station catalogue built from the intersection of active stations
published by both datasets. Cache each unmodified station/year/source pair and
slice the requested seven-day range locally. A range crossing New Year may load
two years.

Parse quoted fields, commas inside quoted values, CRLF, UTF-8 BOM, and the exact
headers captured in canonical fixtures. Display `Hong Kong Observatory` and the
required Government/DATA.GOV.HK attribution.

### Source-contract gate

Before provider implementation begins, capture canonical live fixtures and
record current terms, attribution, client identification, and redistribution
conditions in `docs/almanac-tide-source-contracts.md`.

If an official source no longer permits direct iOS use or cannot supply a
complete hourly-plus-high/low result, disable that provider with an explicit
unavailable state. Do not add a proxy backend or silently substitute a
commercial provider in this task.

Official references:

- CHS IWLS: <https://www.tides.gc.ca/en/web-services-offered-canadian-hydrographic-service>
- CHS licence: <https://www.tides.gc.ca/en/licence-agreement?wbdisable=true>
- NOAA Data API: <https://api.tidesandcurrents.noaa.gov/api/dev>
- NOAA Metadata API: <https://api.tidesandcurrents.noaa.gov/mdapi/prod/>
- JMA tide tables: <https://www.data.jma.go.jp/kaiyou/db/tide/suisan/index.php>
- JMA fixed-width format: <https://ds.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/readme.html>
- JMA terms: <https://www.jma.go.jp/jma/kishou/info/coment.html>
- HKO hourly tides: <https://data.gov.hk/en-data/dataset/hk-hko-rss-hourly-heights-of-tides>
- HKO high/low tides: <https://data.gov.hk/en-data/dataset/hk-hko-rss-times-and-heights-of-high-and-low-tides>
- DATA.GOV.HK terms: <https://data.gov.hk/en/terms-and-conditions>

## Coverage and station selection

`TideCoverageResolver` uses resolved country/administrative metadata:

- Canada → CHS
- United States → NOAA
- Japan → JMA
- Hong Kong → HKO

Apply a narrow Hong Kong geographic fallback before broader China routing because
geocoders may return `CN`. Outside the four regions, Sun remains functional and
Tides shows an unsupported-region state.

For an eligible region:

1. Filter to stations capable of hourly samples and exact high/low events.
2. Calculate geodesic distance from the Almanac coordinate.
3. Auto-select the nearest eligible station only within 250 km.
4. Offer at most the nearest eight eligible stations for manual selection.
5. Never choose a station from another provider merely because it is closer.

A supported region with no eligible station inside 250 km shows
`No supported tide station nearby` rather than silently using a distant station.

A manual override persists for a fixed location until that location changes. In
Current Location mode, retain it through ordinary movement and clear it only
when the device moves more than 25 km from the override anchor, or when the user
chooses **Use Nearest Station**.

## Tide caching and refresh

### Storage

Use replaceable files below:

```text
Application Support/Almanac/Tides/
```

Suggested layout:

```text
catalogs/<schema>/<provider>.json
weeks/<schema>/<provider>/<station>/<range-start>.json
sources/jma/<station>/<year>.txt
sources/hko/<station>/<year>-hourly.csv
sources/hko/<station>/<year>-hilo.csv
```

The cache schema has an integer version. A mismatch is a clean miss; there is no
migration machinery.

Normalized `TideWeek` entries are fresh for 24 hours. Remote CHS/NOAA station
catalogues are fresh for 30 days. Annual JMA/HKO source files are immutable for
their station/year cache key.

### Stale-while-refresh behavior

Loading follows a simple two-call flow owned by the view model:

1. Resolve coverage and station.
2. Return a complete fresh or stale cached week immediately when present.
3. A fresh result stops there.
4. A stale result remains on screen while the view model starts one forced
   refresh.
5. A successful refresh atomically replaces the cache and screen result.
6. A failed refresh preserves stale content and adds a non-blocking warning.
7. With no cache, fetch once and show a full error only if that fetch fails.

Do not add an `AsyncStream`, reachability monitor, background scheduler, or app
launch preload. Tide work begins only while Almanac is active or when its
location/station/seven-day range changes.

### Atomic completeness

Write normalized weeks atomically only after all validation succeeds:

- station metadata is complete and has a valid time zone;
- hourly samples parse successfully;
- exact high/low events parse successfully;
- values belong to the requested station and datum;
- timestamps intersect the requested range;
- all heights are finite.

Providers requiring two responses, especially NOAA and HKO, commit them as one
logical result. A partial result never replaces an earlier complete cache.

## Tides presentation

### State progression

Distinguish station resolution from prediction loading:

```text
Finding nearby tide stations…
Loading predictions for Vancouver…
```

Explicit states are:

- unsupported region;
- no supported station nearby;
- loading station catalogue;
- resolving selected-station time zone;
- loading predictions;
- fresh/live predictions;
- cached/offline predictions;
- provider temporarily unavailable;
- prediction format changed;
- no predictions published for the selected range.

### Summary, chart, and events

For today at the station, lead with the next high or low event after the current
instant, including type, local time, height, countdown, station, and distance.
After the last event today, the card may show tomorrow's first event with an
explicit **Tomorrow** label.

For another selected date, show the first event of that date and omit the
countdown.

Use native Swift Charts for one daily graph containing:

- official hourly samples as a line;
- exact high/low events as independent labelled markers;
- station-local time on the horizontal axis;
- metres on the vertical axis;
- a current-time rule only for today.

No third-party chart package is added. High and low use labels and symbols, not
colour alone. Repeat every exact event below the chart:

```text
03:18   Low      1.1 m
09:27   High     4.0 m
15:34   Low      1.5 m
21:43   High     3.7 m
```

The station card shows:

- station name and distance;
- station time zone when different from the selected location;
- datum;
- official provider attribution;
- last successful update and live/cached/offline state;
- **Choose another station**;
- `Predictions are for planning only, not navigation.`

Pull-to-refresh performs a forced tide refresh. Provider failure never erases
usable cached predictions.

## Shared date navigation

Default to today in the active location's time zone and show seven consecutive
selectable dates starting on that day.

- Previous and next move the entire window exactly seven days.
- Selecting a day updates Sun and Tides together.
- **Today** re-anchors the window at the current destination-local date.
- Moving within one loaded tide range changes presentation only.
- Moving the window loads or requests the corresponding range.

There is no arbitrary date picker in v1. A provider may return no predictions
outside its publication horizon; show the explicit no-predictions state.

## View-model data flow

`AlmanacView` owns one `@StateObject AlmanacViewModel` and receives the shared
`LocationManager` plus a small feature dependency value.

```text
ContentView
   `-- AlmanacView(locationManager, dependencies)
          `-- AlmanacViewModel
                 |-- observes GPS only in Current Location mode
                 |-- resolves search/current placemark context
                 |-- calculates SolarDay locally
                 `-- asks TideService for station + TideWeek
```

For a location or range change:

1. resolve the active coordinate and location time zone;
2. reset destination-local date state when required;
3. recalculate solar events synchronously;
4. resolve tide coverage;
5. resolve the automatic or overridden station;
6. resolve that station's time zone when its catalogue lacks one;
7. display a complete cached week immediately;
8. perform a forced refresh when the cache is stale or the user requests it.

Use cancellable task properties and a request generation/key check so an older
location or range response cannot overwrite a newer selection.

## Error model

Keep provider details out of the view:

```swift
enum TideLoadError: Error, Equatable {
    case unsupportedRegion
    case noStationNearby
    case networkUnavailable
    case providerUnavailable
    case invalidProviderResponse
    case noPredictions
}
```

Provider clients log underlying HTTP/decoding errors but expose only these
stable categories. Location search and permission failures remain separate
Almanac location states.

Do not add automatic exponential retries, notifications, destructive cache
clearing, or a generic error framework. Retry and pull-to-refresh are enough.

## Accessibility and responsive layout

Use native Dynamic Type. On narrow iPhones, the date strip scrolls horizontally
and summary metrics may stack. On iPad, retain a centered single content column;
do not create a second dashboard implementation.

- Decorative solar/tide art is hidden from VoiceOver.
- Exact tide values appear in rows, not only the chart.
- Chart markers expose high/low labels and heights.
- The chart exposes a summary of daily minimum, maximum, and event order.
- Countdown updates occur at most once per minute and do not trigger repeated
  announcements.
- Time-zone labels use readable text plus UTC offset.
- Loading and cached/offline states have concise accessibility labels.

## Expected implementation boundary

Create feature code under:

```text
Triangulum/Features/Almanac/
├── AlmanacDependencies.swift
├── AlmanacLocation.swift
├── AlmanacLocationResolver.swift
├── AlmanacLocationSheet.swift
├── AlmanacSunView.swift
├── AlmanacTidesView.swift
├── AlmanacView.swift
├── AlmanacViewModel.swift
├── LocalDate.swift
├── SolarDay.swift
├── TideChartView.swift
├── TideCoverageResolver.swift
├── TideDiskCache.swift
├── TideModels.swift
├── TideService.swift
├── TideStationSheet.swift
├── TideStationTimeZoneResolver.swift
├── CanadaTideClient.swift
├── UnitedStatesTideClient.swift
├── JapanTideClient.swift
├── HongKongTideClient.swift
└── Resources/
    ├── JapanTideStations.json
    └── HongKongTideStations.json
```

This is a responsibility boundary, not a requirement to create empty files.
Combine very small types when that reduces churn without mixing provider
parsing, cache I/O, view-model state, and SwiftUI presentation.

Narrow existing-file changes:

- `ContentView.swift`: add Almanac, pass the shared location manager, remove the
  Solar utility tile, and select deterministic dependencies in the UI-test mode.
- `FieldHubView.swift`: add `.almanac` to `ProductTab`.
- `ConstellationMapView+Solar.swift`: accept explicit local date/time zone.
- `SolarEventsView.swift`: keep compiling during migration, then delete.
- `Log.swift`: add an Almanac category.
- Existing solar tests: retain and adapt calculation coverage.
- UI tests: update the shell assertion and add one deterministic Almanac smoke
  test.

The Xcode project uses file-system-synchronised groups, so implementation must
not edit `project.pbxproj` solely to add these files.

## Verification strategy

### Local date and solar

Cover:

- one instant mapping to different destination dates;
- rolling seven-day ranges across month/year boundaries;
- 23/25-hour daylight-saving days;
- explicit destination-time-zone solar crossings;
- sunrise/sunset/twilight/golden-hour ordering;
- next-event selection;
- polar day and polar night.

### Coverage and station selection

Cover:

- Canada, United States, Japan, and Hong Kong routing;
- Hong Kong fallback taking precedence over broader China metadata;
- unsupported locations retaining Sun while rejecting Tides;
- nearest eligible station within 250 km;
- rejection beyond 250 km;
- maximum eight manual choices;
- NOAA reference-only and U.S.-jurisdiction filtering;
- fixed-location override reset;
- Current Location override retention below 25 km and reset above it;
- selected-station time-zone resolution and catalogue persistence.

### Provider fixtures

Capture representative official fixtures for CHS, NOAA, JMA, and HKO. For each
adapter verify:

- station metadata and coordinates;
- request contract;
- hourly samples;
- exact high/low events;
- time-zone handling;
- units normalized to metres;
- datum and attribution preservation;
- malformed/partial response rejection;
- two-year combination for JMA/HKO New Year ranges.

NOAA and HKO tests must prove that one successful source response plus one failed
source response does not produce a cacheable week.

### Cache, service, and view model

Cover:

- fresh cache returning without network work;
- stale cache rendering before forced refresh;
- stale cache surviving refresh failure;
- complete refresh atomically replacing the prior result;
- corrupt/version-mismatched entries becoming clean misses;
- date changes inside one range avoiding refetch;
- station/range changes using distinct keys;
- location isolation from Live consumers;
- destination-local startup reset;
- cancellation/generation checks preventing stale async overwrite;
- unsupported Tides never disabling solar output.

### UI and build gates

Keep UI automation small and deterministic:

1. The shell test expects exactly `Live`, `Field`, `Almanac`, `Footprint`, and
   `Settings`.
2. One fixture-backed smoke test opens Almanac, confirms Vancouver/date/Sun,
   switches to Tides, and sees the next-event summary, chart accessibility
   label, station, datum, and attribution.

UI tests must not require GPS permission, current wall-clock time, or a public
network. No screenshot-golden suite is required.

The implementation is complete when:

- focused Almanac and existing solar tests pass;
- all four provider fixture suites pass;
- all unit and UI tests pass with parallel testing disabled;
- the app builds for generic iOS and available phone/tablet simulators;
- SwiftLint passes;
- automated tests make no live network calls;
- source-contract verification is recorded for every enabled provider.

## Delivery

Deliver all implementation work in one PR. Use incremental, reviewable commits
inside that PR, but do not split providers or UI into separate PRs unless the
approved scope changes.

Suggested order:

```text
Source contracts and fixtures
→ LocalDate and persisted selection
→ destination-time-zone solar migration
→ tide domain, coverage, station selection, and cache
→ four provider adapters
→ station-time-zone resolution and TideService
→ AlmanacViewModel and location search
→ Sun UI
→ Tides UI and chart
→ tab wiring and old Solar removal
→ deterministic UI fixture and full verification
```

A region that fails the source-contract or complete-fixture gate is visibly
disabled in the same implementation PR rather than replaced with new
infrastructure.

## Risks and mitigations

### Official source drift

JMA fixed-width files and HKO CSV headers may change. Keep parsers strict,
small, and fixture-tested. Preserve the last complete cache and report a
prediction-format error rather than showing partial values.

### Station time-zone gaps

Some catalogues provide an offset but not an IANA identifier. Resolve only the
selected unresolved station coordinate, cache the enriched result, and reject a
week when no valid station time zone can be obtained.

### Inconsistent station coverage

The geometrically nearest station may not best represent a harbour or bay. The
250 km cap prevents obviously irrelevant matches, while the nearest-eight
manual picker gives the user control without a full station browser.

### Datum misunderstanding

Place the station datum beside predicted heights and include the planning-only,
non-navigation warning. Do not convert or compare station values.

### Provider outage and offline use

Render complete cached data first, refresh only while Almanac is active, and
never erase a complete cache after a failed refresh. Do not add a backend solely
to mask public-provider outages.
