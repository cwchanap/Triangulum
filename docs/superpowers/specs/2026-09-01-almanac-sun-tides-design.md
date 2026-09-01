# Almanac Sun and Tide Tab

**Date:** 2026-09-01  
**Branch:** `docs/almanac-sun-tides-design`  
**Status:** Design approved; written specification ready for review

## Summary

Add a fifth primary tab, **Almanac**, to Triangulum. Almanac combines worldwide
solar events with predicted tides for Canada, the United States, Japan, and
Hong Kong. A shared location and seven-day date strip drive two sections:
**Sun** and **Tides**.

The first release stays deliberately narrow:

- Solar events are calculated locally for any valid coordinate.
- Tide predictions come directly from official regional sources.
- Tide values are predictions only; live observations are out of scope.
- The nearest eligible station is selected automatically, with a remembered
  manual override.
- Tide data is normalized and cached on-device.
- No backend, provider registry, favourites system, or new persistence schema is
  introduced.

## Problem

Triangulum already calculates sunrise, sunset, twilight, and golden-hour events,
but the feature is reachable only through a small **Solar** utility tile and is
bound to the device's current GPS coordinate. It cannot be used to plan for a
remote location.

The app also has no tide display. Users planning photography, hiking, coastal
visits, or travel need daylight and predicted tide information for the same
place and local calendar day.

## Goals

1. Provide one first-class Almanac tab for location- and date-based natural
   events.
2. Let the user use either the device location or one searched, fixed location
   without changing the Live dashboard's sensor context.
3. Present sunrise, sunset, daylight duration, twilight, and golden hour in the
   selected location's local time.
4. Present the next predicted tide, a daily hourly curve, exact high/low events,
   and source station metadata for Canada, the United States, Japan, and Hong
   Kong.
5. Remain useful offline after a tide week has been loaded once.
6. Keep implementation and maintenance cost appropriate for a hobby project.

## Non-goals

The first release excludes:

- live or historical observed water levels;
- tidal currents, waves, marine weather, surge, or safety alerts;
- global tide coverage outside Canada, the United States, Japan, and Hong Kong;
- notifications, widgets, calendar integration, or background refresh;
- multiple saved locations, favourites, folders, or location management;
- a station map;
- NOAA subordinate tide stations;
- cross-datum conversion or comparison between stations;
- harmonic prediction calculations performed by Triangulum;
- synthetic 15-minute values or minute-level curve claims;
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

`Almanac` sits between `Field` and `Footprint`, keeping field-planning surfaces
together. The existing **Solar** tile is removed from the Live dashboard.
Almanac becomes the only user-facing home for solar events.

`ProductTab` remains where it is today in `FieldHubView.swift`; add an
`.almanac` case rather than moving the enum solely for architectural neatness.

### Almanac layout

The root view contains a shared context header followed by a segmented section
picker:

```text
ALMANAC

Vancouver, BC                           Change
Current Location
PDT · UTC−7

‹ Week      31  1  2  3  4  5  6      Week ›
                         Today

                    Sun | Tides
```

The selected location, time-zone context, and seven-day strip remain visible
when switching sections. Both sections therefore describe the same selected
place and civil calendar date.

On each app launch Almanac restores the location mode and last fixed location,
then opens on "today" at that destination and defaults to **Sun**. The previous
selected date and active section are not persisted.

## Domain model and local-time rules

### Local civil date

Do not represent the selected Almanac day as device-local midnight. Introduce a
small Codable value such as:

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

Calendar calculations always use an explicit `TimeZone` and Gregorian
`Calendar`. This prevents Tokyo, Vancouver, and Hong Kong from silently sharing
the device's day boundary.

The selected `LocalDate` is defined in the active Almanac location's time zone.
Solar events use that location time zone. Tide samples and events use the tide
station's authoritative time zone. The same year-month-day is interpreted in
the station time zone for the Tides section. If the location and station time
zones differ, the station card displays the tide time zone explicitly.

Hourly source points are stored as absolute `Date` instants. A daylight-saving
transition may yield 23 or 25 hourly points for a local day; the model must not
force every day to contain exactly 24 samples.

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

`AlmanacViewModel` owns the Almanac location. It observes the shared
`LocationManager` only while in Current Location mode. A selected location is
fixed until changed and does not alter weather, maps, satellites, snapshots, or
any other Live sensor state.

Persist only:

- the selected location mode;
- the last valid fixed location;
- the manual tide station override and the coordinate at which it was chosen.

Use one Codable `UserDefaults` value. No SwiftData entity is required.

### Location search

Reuse `AppleSearchCompleter` for suggestions. Resolve a selected completion
through MapKit into:

- a display name;
- coordinate;
- time-zone identifier;
- country code and administrative area.

If the first placemark has no time zone, perform one reverse-geocode lookup for
the resolved coordinate. If the second lookup still has no time zone, reject
that selection with a clear search error rather than falling back to the device
time zone.

For Current Location, reverse geocode only after the first valid fix and after
meaningful movement, not on every GPS callback. Reuse the last resolved
placemark while movement remains below the tide-override threshold.

Changing to a different fixed location:

1. updates the shared Almanac location;
2. resets the selected day to today at the new destination;
3. resets the visible seven-day window around that day;
4. clears the manual tide-station override;
5. recalculates solar events immediately;
6. resolves tide coverage and the nearest station.

When Current Location permission is denied or restricted, show the existing
Settings remediation. Do not silently use stale GPS coordinates.

## Solar design

### Calculation boundary

Move `SolarDay` out of `SolarEventsView.swift` into the Almanac feature. Preserve
its existing calculation source, twilight thresholds, golden-hour thresholds,
and tests. The calculation accepts an explicit local date, coordinate, and time
zone rather than reading the device's current location or time zone.

The old `SolarEventsView` is removed after Almanac reaches parity. No second
solar UI remains.

### Sun summary

Lead with the most important values:

```text
SUN · MONDAY, AUGUST 31

Sunrise          Daylight          Sunset
06:24            13h 31m           19:55
```

Below the values, show a simple explanatory daylight track using the calculated
civil twilight, sunrise, sunset, and civil dusk boundaries. It is not an
astronomical sky simulation.

When the selected date is today at the destination, show the next relevant
solar event and a countdown updated at most once per minute. Omit countdown
language for other dates.

### Solar detail timeline

Retain the existing events in two secondary groups:

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
Twilight rows remain available but secondary.

Differentiate polar states rather than treating every missing crossing as one
error. Examples:

- `Sun does not set on this date.`
- `Sun remains below the horizon on this date.`
- `Astronomical twilight does not occur on this date.`

Solar calculation is local and remains available worldwide even when Tides is
unsupported.

## Tide architecture

### Closed provider boundary

`AlmanacViewModel` talks to one concrete `TideService`:

```text
AlmanacViewModel
        |
        v
    TideService
        |-- TideCoverageResolver
        |-- TideDiskCache
        `-- explicit TideProvider switch
              |-- CanadaTideClient
              |-- UnitedStatesTideClient
              |-- JapanTideClient
              `-- HongKongTideClient
```

Each regional client conforms to one small internal protocol for normalization
and test substitution:

```swift
protocol TideProviderClient {
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(
        station: TideStation,
        range: LocalDateRange
    ) async throws -> TideWeek
}
```

Production selection is an explicit `switch` over the closed `TideProvider`
enum. Do not build runtime registration, generic plugins, or a broad data-source
framework.

Each client receives an injected `URLSession`. Automated tests use local
fixtures through the project's existing custom `URLProtocol` pattern and never
call public services.

### Normalized tide model

```swift
enum TideProvider: String, Codable {
    case canadaCHS
    case unitedStatesNOAA
    case japanJMA
    case hongKongHKO
}

struct TideStation: Identifiable, Codable, Hashable {
    let id: String                 // provider + providerStationCode
    let provider: TideProvider
    let providerStationCode: String
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
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

Normalize heights to metres, but preserve the provider's published datum label.
Triangulum does not convert datums and does not imply that values from different
stations are directly comparable.

The hourly line connects official hourly points. Exact high/low markers are
stored independently and may occur between hourly points. The UI must not claim
that line segments represent official minute-level predictions.

## Regional tide sources

### Canada — Canadian Hydrographic Service IWLS

Use the Canadian Hydrographic Service Integrated Water Level System REST API.
It exposes JSON endpoints for stations, station metadata, tide tables, data, and
time-series definitions. Select stations that publish both the hourly
prediction series and high/low events required by the common model.

Request one seven-day prediction range per normalized week. Cache the station
catalogue so opening Almanac does not repeatedly consume the published API
limits of three requests per second and thirty requests per minute. Seven-day
hourly requests fit within the service's published lower-resolution limit.

Display attribution as `Canadian Hydrographic Service` and preserve the
station's official vertical datum label.

### United States — NOAA CO-OPS

Use the NOAA CO-OPS Metadata API for the tide-prediction station catalogue and
the Data Retrieval API for predictions.

A complete week requires two Data API requests:

```text
product=predictions
interval=h
units=metric
time_zone=gmt
format=json
datum=MLLW
application=Triangulum
```

and the same request with:

```text
interval=hilo
```

UTC responses avoid ambiguous local timestamps across daylight-saving changes;
Triangulum formats the resulting instants in the station time zone.

Only harmonic/reference prediction stations are eligible. NOAA documents that
subordinate prediction stations provide high/low values only and cannot supply
the hourly curve. Do not synthesize a curve from subordinate-station offsets.

### Japan — Japan Meteorological Agency tide tables

Use the official Japan Meteorological Agency astronomical tide-table
publication. It provides station coordinates, tide-table datum, exact high/low
predictions, and hourly predicted heights and permits a displayed range of up
to 35 days.

`JapanTideClient` requests the selected seven-day range from the published tide
page and parses only the station metadata, hourly table, and high/low table
needed by the normalized model. Parsing remains feature-local and is protected
by checked-in Japanese response fixtures. Do not parse unrelated presentation
markup and do not calculate tides from harmonic constituents.

JMA values are published in centimetres relative to the station tide-table
datum and in Japan Standard Time. Convert centimetres to metres while
preserving the datum label and JST instants.

A changed or incomplete JMA format produces `invalidProviderResponse`; it does
not overwrite a valid cache.

### Hong Kong — Hong Kong Observatory open data

Use the Hong Kong Observatory annual CSV APIs:

- `HHOT` for predicted hourly astronomical tide heights;
- `HLT` for predicted high/low times and heights.

The request unit is station plus year. Cache each source CSV pair and slice the
selected normalized week locally. A week that crosses New Year may require two
station-year pairs.

Keep the small HKO station catalogue as feature-owned metadata derived from the
official datasets. Display attribution as `Hong Kong Observatory` and preserve
the source datum.

### Source-contract gate

Before implementation is considered complete, verify and record the current
terms of use, required attribution, client identification, and redistribution
conditions for all four official sources. The app must provide any required
application identifier or attribution.

If a source's current terms prohibit direct iOS use, disable that region behind
a clear unsupported-source state rather than silently proxying it through a new
backend or substituting an unapproved commercial provider in this task.

Official references:

- CHS IWLS: <https://www.tides.gc.ca/en/web-services-offered-canadian-hydrographic-service>
- NOAA Data API: <https://api.tidesandcurrents.noaa.gov/api/dev>
- NOAA Metadata API: <https://api.tidesandcurrents.noaa.gov/mdapi/prod/>
- JMA tide tables: <https://www.data.jma.go.jp/kaiyou/db/tide/suisan/index.php>
- HKO hourly tides: <https://data.gov.hk/en-data/dataset/hk-hko-rss-hourly-heights-of-tides>
- HKO high/low tides: <https://data.gov.hk/en-data/dataset/hk-hko-rss-times-and-heights-of-high-and-low-tides>

## Coverage and station selection

### Regional coverage

`TideCoverageResolver` uses resolved jurisdiction metadata to select one of the
four providers. Apply a small feature-owned Hong Kong geographic fallback before
country-code routing because geocoders may return a broader Chinese country
classification.

Supported routes are:

- Canada -> CHS
- United States -> NOAA
- Japan -> JMA
- Hong Kong -> HKO

Do not choose a station from another provider simply because it is physically
closer. Outside these regions the Sun section remains functional while Tides
shows an unsupported-region message.

### Automatic station selection

For an eligible region:

1. Filter the catalogue to stations capable of both hourly samples and exact
   high/low events.
2. Calculate geodesic distance from the Almanac coordinate using Core Location.
3. Select the nearest eligible station only when it is within 250 km.
4. Offer up to the nearest eight eligible stations in the manual picker.
5. Show station name, distance, time zone, datum, and provider before or beside
   the prediction details.

A supported region with no eligible station inside 250 km shows
`No supported tide station nearby`. It must not silently use a remote coastal
station.

### Manual station override

The station sheet lists up to eight stations ordered by distance and includes a
`Use Nearest Station` action.

For a fixed Selected Location, changing the location clears the override. In
Current Location mode, normal GPS movement retains the override. Clear it only
after the device moves more than 25 km from the coordinate where the override
was selected, or when the user explicitly chooses `Use Nearest Station`.

## Tide caching and refresh

### Storage

Use replaceable JSON and source files below:

```text
Application Support/Almanac/Tides/
```

Suggested layout:

```text
catalogs/<schema>/<provider>.json
weeks/<schema>/<provider>/<station>/<week-start>.json
sources/hko/<station>/<year>-hourly.csv
sources/hko/<station>/<year>-hilo.csv
```

The cache schema has a small integer version. A mismatch is a clean cache miss;
there is no migration code.

### Weekly cache key

The normalized prediction cache key is:

```text
schema-version / provider / station-id / local-week-start
```

Changing only the selected date inside that week must not trigger another
network request.

### Loading behavior

Use a small stale-while-refresh flow:

1. Display a valid cached week immediately.
2. Treat it as fresh for 24 hours.
3. Refresh when stale data is opened online, on station or week change when no
   fresh cache exists, on retry, or on pull-to-refresh.
4. If refresh fails, keep cached content visible and show its last-updated time.
5. If no cache exists, show the stable user-facing error and Retry action.

No background scheduler or app-launch preload is added. Tide work starts only
when Almanac appears or its active location/station/week changes. Leaving the
screen cancels disposable in-flight tasks without deleting cache entries.

### Atomic completeness

Write a fetched week to a temporary file and replace the existing entry only
after all validation succeeds:

- station metadata is complete;
- hourly samples parse successfully;
- exact high/low events parse successfully;
- all values belong to the requested station and datum;
- timestamps intersect the requested local week;
- values use finite numeric heights.

Providers requiring two source responses, especially NOAA and HKO, commit them
as one logical result. A partial response must not overwrite an earlier complete
week.

## Tides UI

### State progression

Distinguish station resolution from data loading:

```text
Finding nearby tide stations…
Loading predictions for Vancouver…
```

Supported user-facing states are:

- unsupported region;
- no supported station nearby;
- loading station catalogue;
- loading predictions;
- live/fresh predictions;
- cached or offline predictions;
- provider temporarily unavailable;
- prediction format changed;
- no predictions published for the selected dates.

### Next-event summary

For today at the station, show the next high or low event after the current
instant, including type, time, height, countdown, station, and distance.

For another selected date, show the first event of that date and omit the
countdown. If all events for today have passed, the summary may show the first
event tomorrow with an explicit `Tomorrow` label while the chart and event list
remain scoped to today.

### Hourly chart

Use native Swift Charts. Plot:

- official hourly source samples as the line;
- exact high/low events as independent markers;
- destination/station-local times on the horizontal axis;
- metres on the vertical axis;
- a current-time rule only for today.

High and low must be communicated through labels and symbols, not colour alone.
No third-party chart dependency is introduced.

Provide a chart accessibility summary describing the daily minimum, maximum,
and event order. Repeat every exact value in the event list so the graph is not
the only way to access the data.

### Event and station details

Below the chart, show a chronological list:

```text
03:18   Low      1.1 m
09:27   High     4.0 m
15:34   Low      1.5 m
21:43   High     3.7 m
```

The station card shows:

- station name;
- distance from the selected location;
- station time zone when relevant;
- datum;
- official provider attribution;
- last successful update;
- `Choose another station`.

Cached content remains visible after a refresh failure. Example labels:

- `Updated today at 14:12`
- `Cached · Updated Aug 29`
- `Offline · Updated Aug 29`

## Shared date navigation

Default to today in the active location's time zone. Display seven consecutive
selectable dates in a horizontally scrollable strip.

- Previous and next controls move the visible window by seven days.
- Selecting a day updates Sun and Tides together.
- A Today action returns to the current destination-local date and containing
  week.
- Moving within one loaded tide week changes presentation only.
- Moving to another week requests or loads the corresponding cache entry.

There is no arbitrary date picker in v1. Providers may return no data for weeks
outside their published prediction horizon; show the explicit no-predictions
state.

## View-model data flow

`AlmanacView` owns one `@StateObject AlmanacViewModel` and receives only the
shared `LocationManager` from `ContentView`.

```text
ContentView
   `-- AlmanacView(locationManager)
          `-- AlmanacViewModel
                 |-- observes GPS in Current Location mode
                 |-- resolves searched/current placemark context
                 |-- calculates SolarDay locally
                 `-- asks TideService for station + TideWeek
```

For a location or week change:

1. resolve the active coordinate and location time zone;
2. set or reset the destination-local selected day as required;
3. recalculate solar events synchronously;
4. resolve tide-region coverage;
5. resolve the automatic or manually overridden station;
6. display a valid cached week immediately;
7. fetch and atomically replace the cache when required.

Use cancellable `Task` properties in the view model so a newer location,
station, or week selection cannot be overwritten by an older response.

## Error model

Keep provider details out of the view with a closed user-oriented enum:

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

Provider clients may log the underlying HTTP or decoding error, but UI copy is
stable. Do not add automatic exponential retries, notifications, destructive
cache clearing, or a generic error framework. Retry and pull-to-refresh are
sufficient.

Location search and permission failures remain separate Almanac location states
rather than being forced into `TideLoadError`.

## Accessibility and responsive layout

Use native Dynamic Type. On narrow iPhones, the date strip scrolls horizontally
and summary cards stack when needed. On iPad, retain a centered single content
column; do not create a separate dashboard implementation.

- Decorative solar/tide art is hidden from VoiceOver.
- Exact tide values are available in rows, not only the chart.
- Chart markers have high/low labels and values.
- Countdown updates occur at most once per minute and do not force repeated
  announcements.
- Time-zone labels are readable text, not abbreviations alone.
- Loading and cached/offline states expose concise accessibility labels.

## Expected file boundary

Create the feature under:

```text
Triangulum/Features/Almanac/
├── AlmanacView.swift
├── AlmanacViewModel.swift
├── AlmanacLocation.swift
├── AlmanacLocationSheet.swift
├── LocalDate.swift
├── SolarDay.swift
├── TideModels.swift
├── TideService.swift
├── TideCoverageResolver.swift
├── TideDiskCache.swift
├── CanadaTideClient.swift
├── UnitedStatesTideClient.swift
├── JapanTideClient.swift
└── HongKongTideClient.swift
```

This is an expected responsibility boundary, not a requirement to create empty
files. Combine very small models when that reduces churn without mixing
provider parsing, cache I/O, view-model state, and SwiftUI presentation.

Narrow existing-file changes:

- `Triangulum/Views/ContentView.swift`
  - add the Almanac tab;
  - remove the Solar utility tile;
  - pass the shared `LocationManager`.
- `Triangulum/Views/FieldHubView.swift`
  - add `.almanac` to `ProductTab` with an appropriate title and SF Symbol.
- `Triangulum/Views/SolarEventsView.swift`
  - remove after the calculation model and UI behavior are migrated.
- `TriangulumTests/SolarEventsTests.swift`
  - retain and adapt existing calculation tests to the moved `SolarDay`.
- `TriangulumUITests/TriangulumUITests.swift`
  - update the four-tab assertion to five tabs;
  - add one deterministic Almanac smoke test.

## Verification strategy

### Local date and solar tests

Retain existing solar tests and add:

- destination-local today differs correctly from device-local today;
- seven-day windows cross month and year boundaries;
- daylight-saving changes preserve 23/25-hour local days;
- switching locations recalculates the correct destination day;
- sunrise, sunset, twilight, golden-hour ordering, next-event selection, and
  polar conditions remain correct.

### Coverage and station tests

- Canada, United States, Japan, and Hong Kong route to the correct provider.
- Hong Kong geographic fallback wins over broader China metadata.
- Unsupported locations retain Sun and reject Tides.
- The nearest eligible station inside 250 km is selected.
- A station beyond 250 km is rejected.
- NOAA subordinate/non-hourly stations are excluded.
- A fixed-location change clears the manual override.
- Current-location movement below 25 km retains the override; movement beyond
  25 km clears it.

### Provider fixture tests

Check in compact representative source fixtures for CHS, NOAA, JMA, and HKO.
For each adapter verify:

- station metadata and coordinates;
- provider time-zone handling;
- hourly samples;
- exact high/low events;
- conversion to metres;
- datum preservation;
- response range validation;
- malformed and partial response rejection.

NOAA and HKO tests must prove that one successful source response and one failed
source response do not produce a cacheable `TideWeek`.

### Cache and service tests

- A fresh cache displays without waiting for the network.
- Stale cached content survives a refresh failure.
- A complete refresh atomically replaces the previous week.
- A partial provider result leaves the previous cache untouched.
- Date changes inside a week do not refetch.
- Station/week changes use distinct keys.
- A cache-version mismatch is a clean miss.
- HKO New Year weeks combine the correct two station-year source pairs.

### View-model tests

- Current and selected locations remain isolated from the app's Live location
  consumers.
- Switching Sun/Tides preserves location and selected day.
- Changing location resets the day to destination-local today.
- Restoring a fixed location does not restore an obsolete selected day.
- Older asynchronous responses cannot overwrite newer selections.
- Today countdowns use the destination or station time zone.
- Unsupported tides never disable solar output.

### UI tests

Keep UI automation small and deterministic:

1. Update the shell test to expect `Live`, `Field`, `Almanac`, `Footprint`, and
   `Settings`.
2. Add one Almanac smoke test that launches with injected fixed location and
   tide fixtures, opens Almanac, confirms the location/date context, switches
   Sun to Tides, and sees the tide summary, chart accessibility label, and
   station details.

UI tests must not require GPS permission, the current wall-clock date, or public
network access. No screenshot-golden suite is required.

### Build gate

The single implementation PR is complete when:

- focused Almanac tests and all existing solar tests pass;
- all four provider fixture suites pass;
- cache fallback and incomplete-response protection pass;
- the Triangulum scheme builds for available iPhone and iPad simulators;
- the five-tab shell test and deterministic Almanac smoke test pass;
- automated tests make no live network calls;
- the source-contract gate is documented and satisfied for every enabled
  provider.

## Delivery

Deliver this feature in one PR. Suggested implementation order:

```text
LocalDate and normalized models
-> move SolarDay and preserve tests
-> coverage resolver and station selection
-> disk cache
-> four provider adapters with fixtures
-> TideService
-> AlmanacViewModel
-> Almanac SwiftUI screens and chart
-> tab wiring and old Solar screen removal
-> unit/UI/build verification
```

Do not split individual providers or the UI into separate PRs unless the agreed
scope changes. A region whose official source fails the source-contract or
fixture feasibility gate should be visibly disabled in the same PR rather than
replaced with new infrastructure.

## Risks and mitigations

### Official source format drift

JMA's published table and annual HKO CSV files may change format. Keep parsers
small, fixture-tested, and strict. Preserve the last complete cache and show the
prediction-format error instead of displaying partially parsed values.

### Inconsistent station coverage

The geometrically nearest station is not always the best local reference. The
250 km cap prevents obviously irrelevant matches, while the nearest-eight
manual picker gives the user control without a full station browser.

### Time-zone ambiguity

Never infer remote times from the device time zone. Require a resolved location
time zone and use the provider station time zone for tide instants. Store
absolute instants and local civil dates as different types.

### Datum misunderstanding

Always place the station datum near predicted heights. Do not convert or compare
station values. Heights are planning information, not navigational clearance.

### Provider outage and offline use

Load cached content first, refresh only while Almanac is active, and never erase
a complete cache on refresh failure. No backend is added solely to mask public
provider outages.
