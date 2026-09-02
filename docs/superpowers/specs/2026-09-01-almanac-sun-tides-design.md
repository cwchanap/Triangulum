# Almanac Sun and Tide Tab

**Date:** 2026-09-01  
**Branch:** `docs/almanac-sun-tides-design`  
**Status:** Approved design; implementation plan updated after reuse review

## Summary

Add a fifth primary tab, **Almanac**, to Triangulum. The tab combines worldwide solar events with predicted tides for Canada, the United States, Japan, and Hong Kong. A shared Almanac-only location and rolling seven-day date strip drive two sections: **Sun** and **Tides**.

The first release remains deliberately narrow:

- Solar events are calculated locally for any valid coordinate.
- Tide predictions come directly from official regional sources.
- Tide values are predictions only; live observations are out of scope.
- The nearest eligible tide station is selected automatically, with a manual override when another nearby station is more representative.
- Normalized tide predictions are cached by station and local day so overlapping rolling windows remain useful offline.
- No backend, runtime provider registry, favourites system, bundled runtime data-resource layer, or SwiftData migration is introduced.

## Problem

Triangulum already calculates sunrise, sunset, twilight, and golden-hour events, but the feature is reachable only through a small **Solar** utility tile and is bound to the device's current GPS coordinate. It cannot support planning for a remote place.

The app also has no tide display. Users planning photography, hiking, coastal visits, or travel need daylight and predicted tide information for the same place and local calendar day.

## Goals

1. Provide one first-class Almanac tab for location- and date-based natural events.
2. Let the user follow the device location or select one searched, fixed location without changing the Live dashboard's sensor context.
3. Show sunrise, sunset, daylight duration, twilight, and golden hour in the selected location's local time.
4. Show the next predicted tide, a daily hourly curve, exact high/low events, and source-station details for Canada, the United States, Japan, and Hong Kong.
5. Auto-select a useful nearby station while allowing a remembered manual override.
6. Remain useful offline after a station/date range has been loaded once, including the next day when six of seven dates overlap the previous rolling range.
7. Keep implementation and maintenance cost proportionate for a hobby project.

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
- a backend, scheduled data pipeline, dependency-injection container, or runtime provider/plugin registry;
- a SwiftData schema change or backward-compatibility migration.

## Product structure

### Primary navigation

The tab order becomes:

```text
Live · Field · Almanac · Footprint · Settings
```

`Almanac` sits between `Field` and `Footprint`. The existing **Solar** tile is removed from the Live dashboard, and `SolarEventsView` is retired after Almanac reaches feature parity. Almanac becomes the single user-facing home for solar events.

`ProductTab` stays in `FieldHubView.swift`; add `.almanac` rather than moving the enum solely for architectural neatness. Use the stable `calendar` SF Symbol.

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

Location, time-zone context, and the seven-day strip remain visible when the user switches sections. Both sections therefore describe the same selected place and civil calendar date.

On each app launch Almanac restores the location mode and last fixed location, then opens on destination-local **today** and defaults to **Sun**. The previous selected date and active section are not persisted.

## State and local-time model

### Local civil date

Do not represent the selected Almanac day as device-local midnight. Introduce:

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

Calendar calculations use an explicit Gregorian `Calendar` and `TimeZone`. `LocalDate.noon(in:)` is constructed from local calendar components rather than `start + 12h`, so DST transition days remain correct.

The selected `LocalDate` is interpreted in the Almanac location time zone for Sun and in the chosen station time zone for Tides. Tide and solar events are stored as absolute `Date` instants. A daylight-saving transition may therefore produce 23 or 25 hourly tide points; the model must not force exactly 24.

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

`AlmanacViewModel` owns this state. In **Current Location** mode it follows the shared `LocationManager`; in **Selected Location** mode it stays fixed until the user changes it. Changing Almanac location must not alter weather, maps, satellites, snapshots, or other Live sensor state.

Persist one Codable `UserDefaults` payload containing only:

- current versus selected mode;
- the last valid fixed location;
- a manual tide-station override and the coordinate where it was selected.

Do not add a SwiftData entity.

### Location search and GPS resolution

Reuse `AppleSearchCompleter` for suggestions and resolve a selected completion through MapKit into display name, coordinate, time zone, country code, and administrative area.

If the first result has no time zone, reverse-geocode its coordinate once. Reject the selection when the second lookup still has no time zone; never fall back to the device time zone for a remote place.

For Current Location, reverse-geocode after the first valid GPS fix and again only after movement of at least 5 km. Reuse the last placemark context for smaller movement.

Changing to a different fixed location:

1. stores the new Almanac location;
2. resets the selected date to today at that destination;
3. resets the rolling seven-day window to start on that date;
4. clears the manual station override;
5. recalculates solar events immediately;
6. resolves tide coverage and the nearest station when Tides is needed.

When location permission is denied or restricted, show the existing Settings remediation. Do not silently use stale GPS coordinates.

## Solar design

### Calculation boundary

Move `SolarDay` from `SolarEventsView.swift` into the Almanac feature. Preserve these thresholds:

- astronomical twilight: −18°;
- nautical twilight: −12°;
- civil twilight: −6°;
- sunrise/sunset: −0.833°;
- golden-hour boundary: +6°.

Change `ConstellationMapView.Astronomer.solarCrossing` to accept explicit `LocalDate` and `TimeZone` instead of `Calendar.current`.

Use a closed event kind rather than string labels:

```swift
enum SolarEventKind {
    case astronomicalDawn
    case nauticalDawn
    case civilDawn
    case sunrise
    case morningGoldenEnd
    case eveningGoldenStart
    case sunset
    case civilDusk
    case nauticalDusk
    case astronomicalDusk
}

enum SolarState {
    case normal
    case polarDay
    case polarNight
}
```

When sunrise and sunset are both absent, build destination-local noon, call the existing `Astronomer.sunEquatorial` + `localSiderealTime` + `altAz` path, and compare noon altitude with the same −0.833° horizon used by sunrise/sunset. Do not introduce a second solar-altitude formula.

### Sun presentation

Lead with:

```text
SUN · TUESDAY, SEPTEMBER 1

Sunrise          Daylight          Sunset
06:24            13h 31m           19:55
```

Below it, show a simple daylight track using civil dawn, sunrise, sunset, and civil dusk. It is explanatory, not a sky simulation.

For destination-local today, show the next solar event and a countdown updated at most once per minute. Omit countdown language for other dates.

Retain the full event timeline:

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

This wording intentionally replaces the older `Astronomical twilight` / `Blue hour begins` style on `SolarEventsView`; the new copy is part of the approved Almanac presentation and is pinned by `SolarEventKind.displayName` tests rather than arriving accidentally during migration.

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

`TideProvider` always contains all four supported regional cases. `TideProvider.enabled` is the production default after source-contract verification, but `TideCoverageResolver`, `TideService`, and live dependency construction consume the same injected enabled-provider set. This keeps disabled-provider behavior testable without mutating static global state.

Each regional client conforms to one small protocol:

```swift
protocol TideProviderClient {
    var provider: TideProvider { get }
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}
```

Production selection remains an explicit closed switch. Do not build runtime registration, generic plugins, or a broad data-source framework. Clients receive injected `URLSession`; automated tests use the repository's shared token-isolated custom `URLProtocol` and local fixtures.

### Normalized model

```swift
enum TideEventKind: String, Codable {
    case high
    case low
}

enum TideSourceKind: String, Codable {
    case annual
    case hourly
    case hilo
}

struct TideStation: Identifiable, Codable, Hashable {
    let id: String
    let provider: TideProvider
    let providerStationCode: String
    let name: String
    let latitude: Double
    let longitude: Double
    var timeZoneIdentifier: String?
    let datumLabel: String
    let supportsHourlyCurve: Bool
}

struct TideSample: Codable, Hashable {
    let instant: Date
    let heightMetres: Double
}

struct TideEvent: Codable, Hashable {
    let kind: TideEventKind
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

struct TideDay: Codable, Hashable {
    let station: TideStation
    let localDate: LocalDate
    let hourlySamples: [TideSample]
    let events: [TideEvent]
    let fetchedAt: Date
    let sourceAttribution: String
}
```

`TideWeek` is the provider-range result. `TideDay` is the normalized selected-day/display and disk-cache unit.

Normalize heights to metres while preserving the provider datum. Triangulum does not convert datums or imply that values from different stations are directly comparable.

The chart line connects official hourly points. Exact high/low markers are independent and may occur between them. The UI must not imply official sub-hour precision.

### Selected-station time zone

Some remote catalogues do not expose an IANA identifier. Resolve only the selected unresolved station coordinate through Core Location. The resolver itself is stateless; the resolved identifier is written back into that station's cached provider catalogue. The catalogue is the single persistence source of truth for station time-zone enrichment.

When a remote catalogue refreshes, preserve a previously resolved non-nil time-zone identifier for a matching station if the fresh provider row still lacks one. Do not keep a second station-time-zone map in `UserDefaults`.

JMA and HKO compiled station catalogues have known fixed zones and bypass this resolution path.

## Regional tide sources

### Canada — Canadian Hydrographic Service IWLS

Use the Canadian Hydrographic Service IWLS REST API. Load the station catalogue, retrieve hourly prediction data through the documented prediction data series, and retrieve exact high/low predictions through the documented **tide tables** endpoint.

The source-contract gate must capture both non-empty forms for Vancouver before CHS remains enabled. Display `Canadian Hydrographic Service`, retain the official datum, include required derivative-product attribution, and show the planning-only warning.

### United States — NOAA CO-OPS

Use NOAA CO-OPS Metadata API for the tide-prediction catalogue and Data Retrieval API for predictions.

Retain only U.S. reference/harmonic stations (`type == "R"`) with valid U.S. jurisdiction data and hourly prediction support. Exclude subordinate (`type == "S"`) stations. Do not expose non-U.S. catalogue records as U.S. coverage.

A complete range uses two prediction requests:

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

GMT avoids ambiguous source timestamps across DST changes. Resolve the selected station's IANA zone before display. Preserve `MLLW` and show `NOAA CO-OPS` attribution.

### Japan — Japan Meteorological Agency

Use official annual fixed-width files:

```text
https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/{YEAR}/{STATION}.txt
```

Each daily record contains 24 hourly predicted heights plus exact highs/lows. Parse the documented 136-byte layout with byte-safe slices, interpret times in `Asia/Tokyo`, convert centimetres to metres, and preserve the JMA tide-table datum.

Keep the production station catalogue as compiled Swift data generated from the verified official station table. Do not scrape HTML at runtime and do not add a bundled JSON resource loader. Cache validated station/year source files and slice requested dates locally. A range crossing New Year loads two annual files.

Display `Japan Meteorological Agency` and the required source disclosure.

### Hong Kong — Hong Kong Observatory

Use official annual open-data endpoints:

- `HHOT` for predicted hourly astronomical tide heights;
- `HLT` for exact predicted high/low times and heights.

Keep the small production station catalogue as compiled Swift data built from the active intersection of both datasets. Do not add runtime JSON resource loading. Cache each validated station/year/source pair and slice requested HKT dates locally. A range crossing New Year may load two years.

Parse quoted fields, quoted commas, CRLF, UTF-8 BOM, and exact captured headers. Display `Hong Kong Observatory` and required Government/DATA.GOV.HK attribution.

### Source-contract gate

Before provider implementation begins, capture slim canonical fixtures and record current terms, attribution, client identification, redistribution conditions, exact request URLs, and capture date in `docs/almanac-tide-source-contracts.md`.

For every enabled provider, Task 1 must prove the checked-in source material is readable and non-empty for both common-model inputs. Test fixtures are loaded from the checked-out source tree through a `#filePath`-anchored helper; they are not app/test-bundle runtime resources.

If a source no longer permits direct iOS use or cannot supply a complete hourly-plus-high/low result, keep its `TideProvider` case but remove it from the production enabled set and surface provider unavailable. Do not add a proxy or commercial substitute in this task.

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

Apply a narrow Hong Kong geographic fallback before broader China routing because geocoders may return `CN`. Outside these regions, Sun remains functional and Tides shows unsupported region.

For an eligible region:

1. Filter to stations capable of hourly samples and exact high/low events.
2. Calculate geodesic distance from the Almanac coordinate.
3. Auto-select the nearest eligible station only within 250 km.
4. Offer at most the nearest eight eligible stations for manual selection.
5. Never choose a station from another provider merely because it is closer.

A supported region with no eligible station inside 250 km shows `No supported tide station nearby`.

A manual override persists for a fixed location until that location changes. In Current Location mode, retain it through ordinary movement and clear it only when the device moves more than 25 km from the override anchor, or when the user chooses **Use Nearest Station**.

## Tide caching and refresh

### Storage

Use replaceable files below:

```text
Application Support/Almanac/Tides/
  catalogs/v1/<provider>.json
  days/v1/<provider>/<station>/<yyyy-mm-dd>.json
  sources/jma/<station>/<year>.txt
  sources/hko/<station>/<year>-hourly.csv
  sources/hko/<station>/<year>-hilo.csv
```

The schema has an integer version; mismatch is a clean miss with no migration machinery.

Normalized prediction days and remote CHS/NOAA catalogues are fresh for **30 days**. Validated JMA/HKO annual source files are immutable for station/year/source-kind.

The normalized cache is keyed per station and local day rather than rolling-range start. This is required because the visible seven-day strip moves every day: a range fetched on September 1 must still provide September 2–7 cache hits when the September 2 window opens offline.

### Cache-first behavior

The view model follows the same simple behavior already used by satellite TLE loading: fresh cache first, stale cache as usable fallback, then an explicit refresh attempt. The Almanac cache is a new file cache rather than a reuse of `TLECache`, because TLE storage is type-specific and UserDefaults-backed.

For the selected day:

1. Resolve coverage and station.
2. Return a fresh or stale cached `TideDay` immediately when present.
3. A fresh hit stops unless the user explicitly pulls to refresh.
4. A stale hit remains on screen while one range refresh is attempted.
5. A missing day triggers one fetch for the current rolling seven-day range.
6. A successful range validates completely, then writes normalized local-day entries.
7. A failed refresh preserves any cached selected day and adds a non-blocking warning.

Do not add reachability monitoring, AsyncStream, background scheduling, launch preload, or exponential retries.

### Complete-response gate

Provider clients return `TideWeek` only after all required source inputs validate:

- station metadata is complete;
- station time zone is valid;
- hourly samples parse successfully;
- exact high/low events parse successfully;
- values belong to the requested station/datum;
- timestamps intersect the requested range;
- heights are finite.

Providers requiring two responses, especially NOAA and HKO, return no `TideWeek` when either half fails. `TideDiskCache.saveCompleteRange` partitions a complete normalized result into local days, encodes all day entries before writes, and atomically replaces each day file. A partial provider response therefore never creates or replaces normalized day entries.

## Tides presentation

### State progression

Distinguish station resolution from prediction loading:

```text
Finding nearby tide stations…
Loading predictions for Vancouver…
```

Explicit states are:

- unsupported region;
- supported provider currently unavailable;
- no supported station nearby;
- loading station catalogue;
- resolving selected-station time zone;
- loading predictions;
- fresh predictions;
- cached/offline predictions;
- provider temporarily unavailable;
- prediction format changed;
- no predictions published for the selected dates.

### Summary, chart, and events

For today at the station, lead with the next high or low event after the current instant, including type, local time, height, countdown, station, and distance.

For another date, show the first event of that date and omit countdown. After today's last event, the summary may show tomorrow when tomorrow's cache entry is available; otherwise `No more events today` is acceptable.

Use native Swift Charts for one daily graph containing:

- official hourly samples as a default/linear line;
- exact high/low events as independent labelled markers;
- station-local time on the horizontal axis;
- metres on the vertical axis;
- a current-time rule only for today.

Do not use Catmull-Rom interpolation or an `AreaMark` fill. High and low use labels/symbols rather than colour alone. Repeat every exact event in a chronological list.

The station card shows station name/distance, station time zone when different, datum, official attribution, last successful update and cache state, **Choose another station**, and `Predictions are for planning only, not navigation.`

Pull-to-refresh performs a forced range refresh. Provider failure never erases usable cached predictions.

## Shared date navigation

Default to today in the active location time zone and show seven consecutive selectable dates starting on that day.

- Previous and next move the window exactly seven days.
- Selecting a day updates Sun and Tides together.
- **Today** re-anchors at current destination-local date.
- Selecting a day already in normalized day cache requires no network request.
- A missing/stale day may trigger one current-range refresh according to cache policy.

There is no arbitrary date picker in v1.

## View-model data flow

`AlmanacView` owns one `@StateObject AlmanacViewModel` and receives shared `LocationManager` plus a small feature dependency value.

```text
ContentView
   `-- AlmanacView(locationManager, dependencies)
          `-- AlmanacViewModel
                 |-- observes GPS only in Current Location mode
                 |-- resolves search/current placemark context
                 |-- calculates SolarDay locally
                 `-- asks TideService for station + cached TideDay / refreshed TideWeek
```

For location/date changes:

1. resolve active coordinate and location time zone;
2. reset destination-local date state when required;
3. recalculate solar events synchronously;
4. resolve tide coverage from the injected enabled-provider set;
5. resolve automatic or overridden station;
6. resolve that station's IANA zone if the catalogue lacks one and persist enrichment in the cached catalogue;
7. display cached selected-day predictions immediately when present;
8. refresh the current seven-day range only when missing/stale or explicitly requested.

Use cancellable tasks plus a generation token/key check before applying async results, matching the existing SatelliteManager token-checked result-application pattern. Cancellation alone is not the correctness boundary.

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

Provider clients log underlying HTTP/decoding failures but expose stable categories. Location search/permission failures remain separate Almanac location states. Retry and pull-to-refresh are sufficient.

## Accessibility and responsive layout

Use native Dynamic Type. On narrow iPhones, the date strip scrolls horizontally and summary metrics may stack. On iPad, retain a centered single content column rather than creating another dashboard.

- Decorative solar/tide art is hidden from VoiceOver.
- Exact tide values appear in rows, not only the chart.
- Chart markers expose high/low labels and heights.
- The chart exposes a summary of daily minimum, maximum, and event order.
- Countdown updates occur at most once per minute.
- Time-zone labels use readable text plus UTC offset.
- Loading and cached/offline states have concise accessibility labels.

Unit rendering reuses the existing UIWindow-retaining `renderHost` as a crash/layout seam. Exact accessibility copy is asserted through pure presentation helpers and the deterministic XCUITest because SwiftUI's UIKit accessibility tree is not reliably materialized synchronously in that unit-test helper.

## Expected implementation boundary

Create cohesive feature code under:

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
├── TideProvider.swift
├── TideProviderClient.swift
├── TideService.swift
├── TideStationSelector.swift
├── TideStationSheet.swift
├── TideStationTimeZoneResolver.swift
├── CanadaTideClient.swift
├── UnitedStatesTideClient.swift
├── JapanTideClient.swift
├── JapanTideStations.swift
├── HongKongTideClient.swift
└── HongKongTideStations.swift
```

JMA/HKO production catalogues are compiled Swift data; there is no new `Resources/` runtime-loading convention. Test fixtures remain under `TriangulumTests/Fixtures/Almanac/` and are loaded source-relative through a test-only helper.

This introduces `Triangulum/Features/` as a feature-local convention without reorganizing existing sensor code. Update `CLAUDE.md` in the implementation PR so later work does not scatter Almanac code back into `Views/Managers/Models/Utilities`.

Narrow existing-file changes:

- `ContentView.swift`: add Almanac, remove Solar tile, use deterministic Almanac dependencies whenever existing `-ui-testing` is active.
- `FieldHubView.swift`: add `.almanac` to `ProductTab`.
- `ConstellationMapView+Solar.swift`: accept explicit local date/time zone.
- `SolarEventsView.swift`: keep compiling during migration, then delete.
- `Log.swift`: add Almanac category.
- `WeatherManagerTestHelpers.swift`: delegate its existing fake transport to one shared test helper.
- `CelComponentRenderingTests.swift`: use one extracted shared `renderHost`.
- `CLAUDE.md`: document `Features/Almanac`.
- UI tests: update shell assertion and add one deterministic Almanac smoke test using existing `-ui-testing` only.

The Xcode project uses file-system-synchronised groups. No implementation step depends on adding bundled JSON/text/CSV runtime resources, so `project.pbxproj` should not need modification.

## Verification strategy

### Source gate

Before parser work:

- record terms/request shapes for all four sources;
- capture slim canonical fixtures;
- prove every named fixture is readable and non-empty from the checked-out source tree;
- validate basic source shape;
- keep only providers with verified hourly + exact high/low inputs in the production enabled set.

### Local date and solar

Cover:

- one instant mapping to different destination dates;
- rolling seven-day ranges across month/year boundaries;
- 23/25-hour DST days;
- explicit destination-time-zone solar crossings;
- exact `SolarEventKind` display-name mapping;
- sunrise/sunset/twilight/golden-hour ordering;
- next-event selection;
- polar day/night through existing `Astronomer.altAz`.

### Coverage and station selection

Cover:

- injected enabled-provider routing for all four regions;
- disabled supported provider distinct from unsupported region;
- Hong Kong fallback before broader China metadata;
- nearest eligible station within 250 km;
- rejection beyond 250 km;
- maximum eight manual choices;
- NOAA reference-only/U.S.-jurisdiction filtering;
- fixed-location override reset;
- Current Location override retention below 25 km and reset above it;
- selected-station time-zone resolution stored in cached catalogue only.

### Provider fixtures

For CHS, NOAA, JMA, and HKO verify station metadata, request contract, hourly samples, exact high/low events, time-zone handling, metre normalization, datum/attribution, malformed/partial rejection, and two-year JMA/HKO ranges.

NOAA/HKO tests must prove that one successful half plus one failed half does not return a cacheable `TideWeek`.

### Cache, service, and view model

Cover:

- Sep 1 range fetch produces Sep 2 selected-day cache hit without network;
- normalized days remain fresh for 30 days;
- stale day is usable before refresh;
- stale day survives refresh failure;
- complete provider range validates before any normalized day writes;
- schema mismatch is a miss;
- catalogue enrichment survives reload/refresh;
- same injected enabled set controls coverage and dispatch;
- location isolation from Live consumers;
- destination-local startup reset;
- cancellation plus generation checks prevent stale async overwrite;
- unsupported/unavailable Tides never disable Sun.

### UI and build gates

Keep UI automation small and deterministic:

1. Shell test expects exactly `Live`, `Field`, `Almanac`, `Footprint`, `Settings`.
2. One `-ui-testing` fixture-backed smoke opens Almanac, confirms fixed Vancouver/date/Sun, switches to Tides, and verifies summary, chart accessibility label, station, datum, attribution, and planning-only warning.

UI tests must not require GPS permission, wall-clock time, or public network. No screenshot-golden suite is required.

The implementation is complete when focused Almanac/existing solar tests pass, all four enabled provider fixture suites pass, all unit/UI tests pass with parallel testing disabled, iPhone/iPad/generic builds succeed, SwiftLint passes, automated tests make no live network calls, and source-contract verification is recorded for every enabled provider.

## Delivery

Deliver the approved feature in **one PR**. Use incremental reviewable commits inside the PR, but do not split already-approved provider coverage into separate PRs unless scope is explicitly changed.

The provider boundary still ensures later maintenance is isolated: each source owns one client/parser and fixture suite behind a closed switch. That maintenance property does not require fragmenting this feature delivery.

Suggested order:

```text
Source contracts + slim fixtures + enabled-provider gate
→ LocalDate and preferences
→ destination-aware solar migration
→ tide domain + day-keyed cache
→ shared URLProtocol + four clients
→ TideService + station-time-zone catalogue enrichment
→ AlmanacViewModel + Apple search
→ Sun/Tides UI + shared renderHost
→ tab wiring + Solar removal + deterministic UI smoke + CLAUDE.md
```

A region that fails the source-contract/fixture gate is visibly disabled in this same PR rather than replaced with new infrastructure.

## Risks and mitigations

### Source-contract feasibility

A regional source may not expose or permit both required prediction forms. Task 1 is a hard gate: capture the real request/response pair before writing its client. A failed source is disabled before parser/UI work, not special-cased afterward.

### Official format drift

JMA fixed-width files and HKO CSV headers may change. Keep parsers strict, small, and fixture-tested. Report prediction-format errors rather than displaying partial values.

### Rolling-window cache overlap

A cache keyed by seven-day start would miss tomorrow despite six overlapping dates. Normalize complete fetched ranges into station/local-day entries and test the Sep 1 → Sep 2 reuse path explicitly.

### Station time-zone gaps

Resolve only the selected unresolved station. Persist enrichment in the cached station catalogue and merge that value through catalogue refresh when the provider still omits it. Do not maintain a second UserDefaults map.

### Inconsistent station coverage

The geometrically nearest station may not best represent a harbour or bay. The 250 km cap prevents obviously irrelevant matches; the nearest-eight picker provides a small manual correction surface.

### Datum misunderstanding

Place station datum beside predicted heights and include the planning-only, non-navigation warning. Do not convert or compare station values.

### Provider outage and offline use

Follow the existing fresh-cache/stale-fallback/refresh behavior pattern, but use a file cache appropriate to tide data rather than reusing TLECache storage. Never erase cached selected-day predictions after refresh failure, and do not add a backend solely to mask provider outages.
