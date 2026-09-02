# Almanac Sun and Tide Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fifth Almanac tab that shows destination-local solar events worldwide and official predicted tides for Canada, the United States, Japan, and Hong Kong, with nearest-station selection and offline caching.

**Architecture:** Keep the feature under `Triangulum/Features/Almanac/`. `AlmanacViewModel` owns Almanac-only location, rolling seven-day range, selected day, and Sun/Tides state. `TideService` uses one explicit closed `TideProvider` switch, a selected-station time-zone resolver, and one actor-backed disk cache. Provider tests reuse the repo's existing token-isolated `URLProtocol` seam after extracting it to a shared test helper; SwiftUI smoke tests likewise reuse one shared render host. There is no backend, package dependency, runtime provider registry, or SwiftData migration.

**Tech Stack:** Swift 5 language mode (`SWIFT_VERSION = 5.0`) on the repository's current latest-stable Xcode/Swift toolchain, SwiftUI, Swift Charts, MapKit, CoreLocation, Foundation `URLSession`/`FileManager`/`UserDefaults`, Swift Testing, XCTest UI tests, SwiftLint, iOS 18.5+. Match the repo's existing concurrency seams: `@MainActor` for feature UI/state that owns published values, an `actor` for disk cache serialization, injected `URLSession` for networking, and no whole-app isolation migration.

**Spec:** `docs/superpowers/specs/2026-09-01-almanac-sun-tides-design.md`

## Global Constraints

- Deliver all implementation in this one PR; incremental task commits remain in this PR.
- Do not edit `Triangulum.xcodeproj/project.pbxproj`; the project uses file-system-synchronised groups.
- Add no package, backend, reachability monitor, background refresh, favourites system, SwiftData model, or generic dependency container.
- Use `LocalDate` for destination/station civil days and `Date` for event instants.
- Use selected-location time for Sun and selected-station time for Tides.
- Keep Sun available worldwide; Tides is limited to Canada, the United States, Japan, and Hong Kong.
- Plot official hourly tide points with default/linear `LineMark` interpolation and exact official high/low `PointMark`s. Do not use Catmull-Rom interpolation, `AreaMark`, or synthetic finer precision.
- Auto-select only an eligible station within 250 km and show at most eight manual alternatives.
- Preserve a complete stale cache after refresh failure; never replace it with a partial provider response.
- Provider tests use checked-in slim fixtures and injected `URLSession`; automated tests make no public requests.
- Reuse one shared test `URLProtocol` transport and one shared SwiftUI render host; do not create Almanac-only copies.
- Run tests with `-parallel-testing-enabled NO`.
- Display provider attribution, datum, update state, and `Predictions are for planning only, not navigation.`
- A provider is routed only when it is present in `TideProvider.enabled`; a source-contract failure removes it from that set and surfaces `.providerUnavailable` while Sun continues to work.

## Local Command Setup

```bash
xcodebuild -showdestinations -project Triangulum.xcodeproj -scheme Triangulum
export TRIANGULUM_IPHONE_DESTINATION='platform=iOS Simulator,name=iPhone 17'
export TRIANGULUM_IPAD_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

Replace either destination with an exact available simulator name from `-showdestinations` when that model is not installed.

---

### Task 1: Lock slim source fixtures, provider enablement, and attribution

**Files:**
- Create: `docs/almanac-tide-source-contracts.md`
- Create: `Triangulum/Features/Almanac/TideProvider.swift`
- Create: `TriangulumTests/TideProviderTests.swift`
- Create: `TriangulumTests/Fixtures/Almanac/CHS/stations-vancouver.json`
- Create: `TriangulumTests/Fixtures/Almanac/CHS/vancouver-hourly.json`
- Create: `TriangulumTests/Fixtures/Almanac/CHS/vancouver-hilo.json`
- Create: `TriangulumTests/Fixtures/Almanac/NOAA/stations-selection.json`
- Create: `TriangulumTests/Fixtures/Almanac/NOAA/san-francisco-hourly.json`
- Create: `TriangulumTests/Fixtures/Almanac/NOAA/san-francisco-hilo.json`
- Create: `TriangulumTests/Fixtures/Almanac/JMA/tokyo-station.txt`
- Create: `TriangulumTests/Fixtures/Almanac/JMA/tokyo-2026.txt`
- Create: `TriangulumTests/Fixtures/Almanac/HKO/tai-po-kau-2026-hourly.csv`
- Create: `TriangulumTests/Fixtures/Almanac/HKO/tai-po-kau-2026-hilo.csv`

**Interfaces:**
- Produces: `TideProvider`, `TideProvider.enabled`, provider attribution/source metadata, and immutable slim fixtures used by later parser tests.

- [ ] **Step 1: Verify and record the four official source contracts**

Create `docs/almanac-tide-source-contracts.md` with one section per provider containing:

```text
runtime catalogue URL or bundled-catalogue source
runtime prediction URL form
direct iOS-use status
required attribution / derivative-product notice
datum behavior
request limits
fixture capture date
exact fixture capture URL(s)
```

Use only official references:

```text
CHS service: https://www.tides.gc.ca/en/web-services-offered-canadian-hydrographic-service
CHS licence: https://www.tides.gc.ca/en/licence-agreement?wbdisable=true
NOAA Data API: https://api.tidesandcurrents.noaa.gov/api/dev
NOAA Metadata API: https://api.tidesandcurrents.noaa.gov/mdapi/prod/
JMA annual files: https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/
JMA format: https://ds.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/readme.html
JMA terms: https://www.jma.go.jp/jma/kishou/info/coment.html
HKO HHOT: https://data.gov.hk/en-data/dataset/hk-hko-rss-hourly-heights-of-tides
HKO HLT: https://data.gov.hk/en-data/dataset/hk-hko-rss-times-and-heights-of-high-and-low-tides
DATA.GOV.HK terms: https://data.gov.hk/en/terms-and-conditions
```

For CHS, record the current documented `tide tables` endpoint for exact high/low events rather than inventing a `wlp-hilo` series if the Swagger contract does not expose one. The source-contract document is authoritative for the exact runtime request shape implemented later.

- [ ] **Step 2: Add the typed provider gate**

```swift
enum TideProvider: String, CaseIterable, Codable, Hashable {
    case canadaCHS
    case unitedStatesNOAA
    case japanJMA
    case hongKongHKO

    static let enabled: Set<Self> = [
        .canadaCHS,
        .unitedStatesNOAA,
        .japanJMA,
        .hongKongHKO
    ]

    var attribution: String {
        switch self {
        case .canadaCHS: "Canadian Hydrographic Service"
        case .unitedStatesNOAA: "NOAA CO-OPS"
        case .japanJMA: "Japan Meteorological Agency"
        case .hongKongHKO: "Hong Kong Observatory"
        }
    }
}
```

Only keep a case in `enabled` after Step 1 verifies direct use and complete hourly-plus-high/low prediction availability. Keep all four enum cases so an otherwise supported jurisdiction can distinguish `.providerUnavailable` from `.unsupportedRegion`.

Add tests:

```swift
@Test func enabledProvidersHaveAttribution() {
    #expect(TideProvider.enabled.allSatisfy { !$0.attribution.isEmpty })
}

@Test func expectedProvidersAreRepresented() {
    #expect(Set(TideProvider.allCases) == [
        .canadaCHS, .unitedStatesNOAA, .japanJMA, .hongKongHKO
    ])
}
```

- [ ] **Step 3: Capture live data, then check in only slim fixtures**

Capture full catalogues to a temporary directory, never directly into the repository:

```bash
set -euo pipefail
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p TriangulumTests/Fixtures/Almanac/{CHS,NOAA,JMA,HKO}

curl -fsSL 'https://api-iwls.dfo-mpo.gc.ca/api/v1/stations' > "$TMP_DIR/chs-stations.json"
jq '[.[] | select(.code == "07735")]' "$TMP_DIR/chs-stations.json" \
  > TriangulumTests/Fixtures/Almanac/CHS/stations-vancouver.json

test "$(jq 'length' TriangulumTests/Fixtures/Almanac/CHS/stations-vancouver.json)" -eq 1

curl -fsSL 'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions' \
  > "$TMP_DIR/noaa-stations.json"
python3 - "$TMP_DIR/noaa-stations.json" \
  TriangulumTests/Fixtures/Almanac/NOAA/stations-selection.json <<'PY'
import json, sys
src, dst = sys.argv[1:]
rows = json.load(open(src, encoding='utf-8'))['stations']
reference = next(row for row in rows if row['id'] == '9414290')
subordinate = next(row for row in rows if row.get('type') == 'S')
non_us = next(row for row in rows if len(row.get('state', '')) > 2)
json.dump({'stations': [reference, subordinate, non_us]}, open(dst, 'w', encoding='utf-8'), indent=2)
PY

test "$(jq '.stations | length' TriangulumTests/Fixtures/Almanac/NOAA/stations-selection.json)" -eq 3
```

Capture the prediction responses named above using the exact verified request forms from `docs/almanac-tide-source-contracts.md`.

For JMA, check in only the official fixed-width `TK` station record and the annual `TK.txt` prediction file used by parser tests. Do **not** check in or parse `stations-2026.html`.

For HKO, check in only Tai Po Kau annual hourly/high-low samples required by parser tests, trimmed to the header plus representative rows spanning the selected test dates.

Record the original full URLs and capture date in `docs/almanac-tide-source-contracts.md` so fixture provenance is auditable without committing multi-megabyte catalogues.

- [ ] **Step 4: Verify the source gate and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideProviderTests

test "$(wc -c < TriangulumTests/Fixtures/Almanac/NOAA/stations-selection.json)" -lt 50000
test "$(wc -c < TriangulumTests/Fixtures/Almanac/CHS/stations-vancouver.json)" -lt 50000
git diff --check

git add docs/almanac-tide-source-contracts.md \
  Triangulum/Features/Almanac/TideProvider.swift \
  TriangulumTests/TideProviderTests.swift \
  TriangulumTests/Fixtures/Almanac
git commit -m 'docs: lock Almanac tide source contracts and slim fixtures'
```

---

### Task 2: Add destination-local dates and persisted Almanac selection

**Files:**
- Create: `Triangulum/Features/Almanac/LocalDate.swift`
- Create: `Triangulum/Features/Almanac/AlmanacLocation.swift`
- Create: `TriangulumTests/AlmanacLocalDateTests.swift`
- Create: `TriangulumTests/AlmanacPreferencesStoreTests.swift`

**Interfaces:**
- Produces: `LocalDate`, `LocalDateRange`, `AlmanacLocation`, `TideStationOverride`, `AlmanacPreferences`, and `AlmanacPreferencesStore`.

- [ ] **Step 1: Write failing local-date and persistence tests**

```swift
@Test func sameInstantMapsToDestinationLocalDates() {
    let instant = ISO8601DateFormatter().date(from: "2026-09-01T06:30:00Z")!
    let vancouver = TimeZone(identifier: "America/Vancouver")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    #expect(LocalDate(instant, in: vancouver) == .init(year: 2026, month: 8, day: 31))
    #expect(LocalDate(instant, in: tokyo) == .init(year: 2026, month: 9, day: 1))
}

@Test func vancouverDSTDayCanHave23Hours() throws {
    let zone = TimeZone(identifier: "America/Vancouver")!
    let day = LocalDate(year: 2026, month: 3, day: 8)
    #expect(try day.endExclusive(in: zone).timeIntervalSince(day.start(in: zone)) == 23 * 3600)
}
```

Also test seven-day ranges crossing year boundaries, preference round-trip, corrupt JSON returning `.default`, and station override persistence.

Run and expect missing-type failures:

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacLocalDateTests \
  -only-testing:TriangulumTests/AlmanacPreferencesStoreTests
```

- [ ] **Step 2: Implement the exact date and preference boundary**

```swift
struct LocalDate: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int)
    init(_ instant: Date, in timeZone: TimeZone)
    func start(in timeZone: TimeZone) throws -> Date
    func endExclusive(in timeZone: TimeZone) throws -> Date
    func adding(days: Int, in timeZone: TimeZone) throws -> LocalDate
    func rollingSevenDays(in timeZone: TimeZone) throws -> LocalDateRange
}

struct LocalDateRange: Codable, Hashable {
    let start: LocalDate
    let endInclusive: LocalDate
    func dates(in timeZone: TimeZone) throws -> [LocalDate]
}

enum AlmanacLocationMode: String, Codable { case current, selected }

struct AlmanacLocation: Codable, Hashable {
    let mode: AlmanacLocationMode
    let latitude: Double
    let longitude: Double
    let displayName: String
    let timeZoneIdentifier: String
    let countryCode: String?
    let administrativeArea: String?
    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
}

struct TideStationOverride: Codable, Hashable {
    let stationID: String
    let anchorLatitude: Double
    let anchorLongitude: Double
}

struct AlmanacPreferences: Codable, Hashable {
    let mode: AlmanacLocationMode
    let selectedLocation: AlmanacLocation?
    let stationOverride: TideStationOverride?
    static let `default`: AlmanacPreferences
}

struct AlmanacPreferencesStore {
    static let key = "almanac.preferences.v1"
    init(defaults: UserDefaults = .standard)
    func load() -> AlmanacPreferences
    func save(_ value: AlmanacPreferences) throws
}
```

Use an explicit Gregorian calendar with the supplied `TimeZone`. Invalid calendar construction throws `LocalDateError.invalidDate`. Store one JSON value in `UserDefaults`; add no migration code.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacLocalDateTests \
  -only-testing:TriangulumTests/AlmanacPreferencesStoreTests

git add Triangulum/Features/Almanac/LocalDate.swift \
  Triangulum/Features/Almanac/AlmanacLocation.swift \
  TriangulumTests/AlmanacLocalDateTests.swift \
  TriangulumTests/AlmanacPreferencesStoreTests.swift
git commit -m 'feat: add Almanac local date and selection state'
```

---

### Task 3: Move solar calculations to destination time and reuse `Astronomer.altAz` for polar state

**Files:**
- Create: `Triangulum/Features/Almanac/SolarDay.swift`
- Modify: `Triangulum/Views/ConstellationMapView+Solar.swift`
- Modify: `Triangulum/Views/SolarEventsView.swift`
- Modify: `TriangulumTests/SolarEventsTests.swift`

**Interfaces:**
- Consumes: `LocalDate` from Task 2 and existing `ConstellationMapView.Astronomer.sunEquatorial`, `localSiderealTime`, and `altAz`.
- Produces: destination-aware `solarCrossing`, `SolarEventKind`, `SolarEvent`, `SolarState`, and `SolarDay`.

- [ ] **Step 1: Move tests to the new destination-aware API and add polar classification tests**

```swift
let tokyo = TimeZone(identifier: "Asia/Tokyo")!
let sunrise = ConstellationMapView.Astronomer.solarCrossing(
    altitudeDeg: -0.833,
    rising: true,
    localDate: .init(year: 2026, month: 9, day: 1),
    timeZone: tokyo,
    latDeg: 35.6762,
    lonDeg: 139.6503
)
#expect(sunrise != nil)
```

Add polar tests that construct `SolarDay` at 89°N in June and December and assert `.polarDay` / `.polarNight` respectively. Run `SolarEventsTests`; expect signature/initializer failures.

- [ ] **Step 2: Make `solarCrossing` use an explicit destination calendar**

```swift
static func solarCrossing(
    altitudeDeg: Double,
    rising: Bool,
    localDate: LocalDate,
    timeZone: TimeZone,
    latDeg: Double,
    lonDeg: Double
) -> Date?
```

Build destination-local noon from `LocalDate` using a Gregorian calendar configured with `timeZone`, then keep the current declination, sidereal-time, transit, and hour-angle math. Remove `Calendar.current` from this calculation path.

- [ ] **Step 3: Move `SolarDay` and replace string labels with a closed event kind**

```swift
enum SolarEventKind: String, CaseIterable, Codable, Hashable {
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

struct SolarEvent: Equatable {
    let kind: SolarEventKind
    let instant: Date
}

struct SolarDay {
    let localDate: LocalDate
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone
    let state: SolarState
    let events: [SolarEvent]

    var sunrise: Date? { events.first { $0.kind == .sunrise }?.instant }
    var sunset: Date? { events.first { $0.kind == .sunset }?.instant }
    var daylightDuration: TimeInterval? { get }
    func nextEvent(after instant: Date) -> SolarEvent?
}
```

When the `-0.833°` sunrise/sunset crossings are both absent, classify polar state using the existing astronomy path, not a second altitude formula:

```swift
let noon = try localDate.start(in: timeZone).addingTimeInterval(12 * 3600)
let sun = ConstellationMapView.Astronomer.sunEquatorial(date: noon)
let lst = ConstellationMapView.Astronomer.localSiderealTime(date: noon, longitude: longitude)
let noonAltitude = ConstellationMapView.Astronomer.altAz(
    eq: sun,
    lstHours: lst,
    latDeg: latitude
).altDeg
state = noonAltitude > -0.833 ? .polarDay : .polarNight
```

Use the same `-0.833°` horizon threshold as sunrise/sunset rather than geometric zero so polar copy cannot disagree with the event definition near the terminator.

- [ ] **Step 4: Keep the old Solar screen compiling until final removal, verify, and commit**

Adapt `SolarEventsView` temporarily to construct a device-local `LocalDate` and `SolarDay`; Task 9 removes the screen after Almanac UI reaches parity.

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests

git add Triangulum/Features/Almanac/SolarDay.swift \
  Triangulum/Views/ConstellationMapView+Solar.swift \
  Triangulum/Views/SolarEventsView.swift \
  TriangulumTests/SolarEventsTests.swift
git commit -m 'feat: make solar events destination aware'
```

---

### Task 4: Add tide domain, coverage, station selection, source kinds, and actor disk cache

**Files:**
- Create: `Triangulum/Features/Almanac/TideModels.swift`
- Create: `Triangulum/Features/Almanac/TideCoverageResolver.swift`
- Create: `Triangulum/Features/Almanac/TideStationSelector.swift`
- Create: `Triangulum/Features/Almanac/TideDiskCache.swift`
- Create: `TriangulumTests/TideCoverageResolverTests.swift`
- Create: `TriangulumTests/TideStationSelectorTests.swift`
- Create: `TriangulumTests/TideDiskCacheTests.swift`

**Interfaces:**
- Consumes: `TideProvider` from Task 1 and `LocalDateRange` from Task 2.
- Produces: the normalized tide types, typed source-cache key, jurisdiction routing, nearest-station selection, and atomic cache APIs used by all clients/service/UI.

- [ ] **Step 1: Write failing domain, coverage, selector, and cache tests**

Cover:

```text
Canada -> CHS when CHS is enabled
United States -> NOAA when NOAA is enabled
Japan -> JMA when JMA is enabled
Hong Kong geographic fallback -> HKO before broader China routing
disabled supported provider -> providerUnavailable
outside supported regions -> unsupportedRegion
nearest eligible station within 250 km selected
station beyond 250 km rejected
at most eight alternatives returned
fresh cache hit
stale complete cache hit marked stale
schema mismatch -> miss
atomic replacement leaves old week after failed write
TideSourceKind produces distinct source paths for annual/hourly/hilo
```

Run focused tests and expect missing-type failures.

- [ ] **Step 2: Implement normalized models with typed event/source boundaries**

```swift
enum TideEventKind: String, Codable, Hashable { case high, low }
enum TideSourceKind: String, Codable, Hashable { case annual, hourly, hilo }

enum TideCoverage: Equatable {
    case provider(TideProvider)
    case providerUnavailable(TideProvider)
    case unsupportedRegion
}

enum TideLoadError: Error, Equatable {
    case unsupportedRegion
    case providerUnavailable
    case noStationNearby
    case networkUnavailable
    case providerUnavailableAtSource
    case invalidProviderResponse
    case noPredictions
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

    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }
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
```

- [ ] **Step 3: Implement coverage and nearest-station selection**

```swift
struct TideCoverageResolver {
    let enabledProviders: Set<TideProvider>

    func coverage(for location: AlmanacLocation) -> TideCoverage
}

struct TideStationSelector {
    static let maximumAutomaticDistanceMetres = 250_000.0
    static let maximumAlternatives = 8

    func select(
        from stations: [TideStation],
        latitude: Double,
        longitude: Double
    ) -> (selected: TideStation?, alternatives: [TideStation])
}
```

Filter `supportsHourlyCurve == true`, calculate geodesic distance with `CLLocation`, reject automatic selection beyond 250 km, and return at most eight sorted alternatives.

- [ ] **Step 4: Implement the actor-backed cache with typed source kinds**

```swift
actor TideDiskCache {
    static let schemaVersion = 1

    struct CachedWeek: Sendable {
        let week: TideWeek
        let isStale: Bool
    }

    init(rootURL: URL, now: @escaping @Sendable () -> Date = Date.init)

    func loadWeek(
        provider: TideProvider,
        stationID: String,
        range: LocalDateRange
    ) throws -> CachedWeek?

    func saveWeek(_ week: TideWeek) throws

    func loadSource(
        provider: TideProvider,
        stationID: String,
        year: Int,
        kind: TideSourceKind
    ) throws -> Data?

    func saveSource(
        _ data: Data,
        provider: TideProvider,
        stationID: String,
        year: Int,
        kind: TideSourceKind
    ) throws
}
```

Store under `Application Support/Almanac/Tides/`. Use temp-file write plus `FileManager.replaceItemAt` for complete week replacement. A schema mismatch is a miss. Freshness is 24 hours for weeks and 30 days for remote station catalogues; source annual files are immutable by station/year/kind once validated.

- [ ] **Step 5: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideCoverageResolverTests \
  -only-testing:TriangulumTests/TideStationSelectorTests \
  -only-testing:TriangulumTests/TideDiskCacheTests

git add Triangulum/Features/Almanac/TideModels.swift \
  Triangulum/Features/Almanac/TideCoverageResolver.swift \
  Triangulum/Features/Almanac/TideStationSelector.swift \
  Triangulum/Features/Almanac/TideDiskCache.swift \
  TriangulumTests/TideCoverageResolverTests.swift \
  TriangulumTests/TideStationSelectorTests.swift \
  TriangulumTests/TideDiskCacheTests.swift
git commit -m 'feat: add Almanac tide domain and cache'
```

---

### Task 5: Reuse one test transport and implement the four official tide clients

**Files:**
- Create: `TriangulumTests/TestURLSessionHelper.swift`
- Modify: `TriangulumTests/WeatherManagerTestHelpers.swift`
- Create: `Triangulum/Features/Almanac/TideProviderClient.swift`
- Create: `Triangulum/Features/Almanac/CanadaTideClient.swift`
- Create: `Triangulum/Features/Almanac/UnitedStatesTideClient.swift`
- Create: `Triangulum/Features/Almanac/JapanTideClient.swift`
- Create: `Triangulum/Features/Almanac/HongKongTideClient.swift`
- Create: `Triangulum/Features/Almanac/JapanTideStations.json`
- Create: `Triangulum/Features/Almanac/HongKongTideStations.json`
- Create: `TriangulumTests/CanadaTideClientTests.swift`
- Create: `TriangulumTests/UnitedStatesTideClientTests.swift`
- Create: `TriangulumTests/JapanTideClientTests.swift`
- Create: `TriangulumTests/HongKongTideClientTests.swift`

**Interfaces:**
- Consumes: slim Task 1 fixtures and Task 4 domain types.
- Produces: one shared token-isolated test session helper plus four `TideProviderClient` implementations.

- [ ] **Step 1: Extract the existing weather URLProtocol into a shared test helper**

Move the current token-isolated transport semantics out of `WeatherManagerTestHelpers.swift` without changing behavior:

```swift
final class TestURLProtocol: URLProtocol {
    static let tokenHeader = "X-Test-URLProtocol-Token"
    // Preserve the existing serial queue, per-token response providers,
    // register/unregister lifecycle, and .notAllowed cache policy.
}

enum TestURLSessionHelper {
    static func makeSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> (session: URLSession, cleanup: () -> Void)
}
```

Change `WeatherTestHelper.createMockSession` to delegate to `TestURLSessionHelper.makeSession`. Delete `MockWeatherURLProtocol`; do not create an Almanac-specific `URLProtocol`.

Run existing weather fetch tests before writing provider code:

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/WeatherManagerFetchTests
```

Expected: existing weather transport tests remain green after the extraction.

- [ ] **Step 2: Define the small provider-client seam and fixture loader**

```swift
protocol TideProviderClient: Sendable {
    var provider: TideProvider { get }
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}
```

Every network client receives its `URLSession` in `init`. Tests inject `TestURLSessionHelper.makeSession`; production uses `.shared` from `AlmanacDependencies.live()`.

- [ ] **Step 3: Implement CHS and NOAA from slim fixtures**

`CanadaTideClient`:

- Fetch the live CHS station catalogue and filter to prediction-capable stations.
- Fetch hourly `wlp` prediction data using the source-contract request shape.
- Fetch exact high/low events using the verified CHS `tide tables` endpoint recorded in Task 1.
- Preserve CHS chart-datum metadata and normalize values to metres.
- Reject incomplete hourly/high-low pairs.

`UnitedStatesTideClient`:

- Parse `stations.json?type=tidepredictions`.
- Keep only U.S. reference/harmonic rows with `type == "R"`, empty `reference_id`, valid coordinates, and hourly prediction support.
- Explicitly reject subordinate rows (`type == "S"`) and non-U.S. rows captured in `stations-selection.json`.
- Request `product=predictions`, `datum=MLLW`, `units=metric`, `time_zone=gmt`, once with `interval=h` and once with `interval=hilo`.
- Commit a `TideWeek` only when both responses validate.

Tests assert station filtering, metres, exact event kinds/times, datum, request parameters, and partial-response rejection.

- [ ] **Step 4: Implement JMA without an HTML parser**

Treat `Triangulum/Features/Almanac/JapanTideStations.json` as the production catalogue source of truth. Populate it from the official JMA station table during implementation review, but do not ship or write an HTML parser.

Add a fixture test pinning the representative `TK` record against `tokyo-station.txt`:

```swift
@Test func bundledTokyoStationMatchesOfficialRecord() throws {
    let tokyo = try #require(client.bundledStations.first { $0.providerStationCode == "TK" })
    #expect(tokyo.name == "Tokyo")
    #expect(abs(tokyo.latitude - expectedTokyoLatitude) < 0.0001)
    #expect(abs(tokyo.longitude - expectedTokyoLongitude) < 0.0001)
}
```

Set `expectedTokyoLatitude` and `expectedTokyoLongitude` to the numeric values read from the captured official `TK` record in Task 1. Keep the test values literal so accidental catalogue edits fail visibly.

`JapanTideClient` downloads the annual fixed-width station file `.../<year>/TK.txt`, validates 136-byte records per the official format, slices the requested seven local JST dates, converts centimetres to metres, and emits hourly samples plus exact highs/lows. A New Year range loads both years.

- [ ] **Step 5: Implement HKO annual CSV parsing**

Treat `HongKongTideStations.json` as the small production station catalogue. Fetch station/year `HHOT` and `HLT` CSV, cache source bytes later through `TideService`, slice requested HKT dates, and reject a week if either source is missing or malformed. A New Year range loads both years.

- [ ] **Step 6: Verify all shared transport and provider fixtures, then commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/WeatherManagerFetchTests \
  -only-testing:TriangulumTests/CanadaTideClientTests \
  -only-testing:TriangulumTests/UnitedStatesTideClientTests \
  -only-testing:TriangulumTests/JapanTideClientTests \
  -only-testing:TriangulumTests/HongKongTideClientTests

git add TriangulumTests/TestURLSessionHelper.swift \
  TriangulumTests/WeatherManagerTestHelpers.swift \
  Triangulum/Features/Almanac/TideProviderClient.swift \
  Triangulum/Features/Almanac/CanadaTideClient.swift \
  Triangulum/Features/Almanac/UnitedStatesTideClient.swift \
  Triangulum/Features/Almanac/JapanTideClient.swift \
  Triangulum/Features/Almanac/HongKongTideClient.swift \
  Triangulum/Features/Almanac/JapanTideStations.json \
  Triangulum/Features/Almanac/HongKongTideStations.json \
  TriangulumTests/*TideClientTests.swift
git commit -m 'feat: add official Almanac tide clients'
```

---

### Task 6: Add the closed TideService switch, selected-station time zone, and cache-first load

**Files:**
- Create: `Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift`
- Create: `Triangulum/Features/Almanac/TideService.swift`
- Create: `TriangulumTests/TideStationTimeZoneResolverTests.swift`
- Create: `TriangulumTests/TideServiceTests.swift`

**Interfaces:**
- Consumes: provider clients, coverage/selector/cache, and `TideProvider.enabled`.
- Produces: station context, cached-week read, and explicit refresh APIs consumed by the view model.

- [ ] **Step 1: Write failing service tests for the closed switch and stale-cache flow**

Cover:

```text
coverage dispatches only through TideProvider.enabled
unsupported region != disabled supported provider
nearest station is selected and up to eight alternatives returned
manual station override wins when still valid
selected station missing IANA zone is reverse-geocoded once and then cached
fresh cache returns immediately without network
stale cache returns immediately as stale
forced refresh updates stale cache on success
forced refresh failure preserves stale cache
partial NOAA/HKO provider result never replaces complete cache
JMA/HKO New Year source requests cover both years
```

- [ ] **Step 2: Implement selected-station time-zone resolution**

```swift
protocol TideStationTimeZoneResolving: Sendable {
    func resolveTimeZone(for station: TideStation) async throws -> TimeZone
}

final class TideStationTimeZoneResolver: TideStationTimeZoneResolving {
    func resolveTimeZone(for station: TideStation) async throws -> TimeZone
}
```

Return `station.timeZone` when present. Otherwise reverse geocode only the selected station coordinate with `CLGeocoder`; cache the resulting identifier keyed by `station.id` in `UserDefaults`. Never reverse geocode the whole provider catalogue.

- [ ] **Step 3: Implement one explicit service switch and separate cache/read refresh APIs**

```swift
struct TideStationContext: Sendable {
    let coverage: TideCoverage
    let selected: TideStation
    let nearbyStations: [TideStation]
    let distanceMetres: Double
    let timeZone: TimeZone
}

struct TideWeekSnapshot: Sendable {
    let week: TideWeek
    let isStale: Bool
}

protocol TideServing: Sendable {
    func resolveStation(
        for location: AlmanacLocation,
        override: TideStationOverride?
    ) async throws -> TideStationContext

    func cachedWeek(
        station: TideStation,
        range: LocalDateRange
    ) async throws -> TideWeekSnapshot?

    func refreshWeek(
        station: TideStation,
        range: LocalDateRange
    ) async throws -> TideWeek
}
```

Production dispatch remains an explicit switch:

```swift
private func client(for provider: TideProvider) throws -> any TideProviderClient {
    guard TideProvider.enabled.contains(provider) else {
        throw TideLoadError.providerUnavailable
    }
    switch provider {
    case .canadaCHS: canadaClient
    case .unitedStatesNOAA: noaaClient
    case .japanJMA: japanClient
    case .hongKongHKO: hongKongClient
    }
}
```

`cachedWeek` never fetches. `refreshWeek` always performs the network/source refresh and atomically saves only a complete `TideWeek`. Do not add `AsyncStream`, reachability, launch preload, or retry scheduler.

- [ ] **Step 4: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideStationTimeZoneResolverTests \
  -only-testing:TriangulumTests/TideServiceTests

git add Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift \
  Triangulum/Features/Almanac/TideService.swift \
  TriangulumTests/TideStationTimeZoneResolverTests.swift \
  TriangulumTests/TideServiceTests.swift
git commit -m 'feat: add Almanac tide service orchestration'
```

---

### Task 7: Add AlmanacViewModel, MapKit search, and live/UI-test dependencies

**Files:**
- Create: `Triangulum/Features/Almanac/AlmanacLocationResolver.swift`
- Create: `Triangulum/Features/Almanac/AlmanacDependencies.swift`
- Create: `Triangulum/Features/Almanac/AlmanacViewModel.swift`
- Create: `Triangulum/Features/Almanac/AlmanacFixtureTideService.swift`
- Create: `TriangulumTests/AlmanacLocationResolverTests.swift`
- Create: `TriangulumTests/AlmanacViewModelTests.swift`

**Interfaces:**
- Consumes: `LocationManager`, `AppleSearchCompleter`, solar model, preferences, and `TideServing`.
- Produces: all observable state/actions required by the Almanac views plus deterministic UI-test fixture mode.

- [ ] **Step 1: Write failing view-model tests**

Inject `now = { fixedDate }` and fake location/tide dependencies. Cover:

```text
launch restores location mode but resets selected date to destination-local today
current GPS and fixed Almanac location never mutate Live LocationManager coordinates
switching Sun/Tides preserves selected day and location
changing fixed location clears station override
current-location movement under 5 km reuses resolved placemark
movement over 5 km re-resolves placemark
manual station override survives current-location movement up to 25 km
movement over 25 km clears override
selected location without time zone is rejected after fallback reverse geocode fails
unsupported tide region still computes SolarDay
stale TideWeek is published before forced refresh
refresh failure keeps stale week visible with warning
older async selection response cannot overwrite a newer selection
```

- [ ] **Step 2: Implement the MapKit location resolver without OSM**

```swift
protocol AlmanacLocationResolving: Sendable {
    func resolveSearchCompletion(_ completion: MKLocalSearchCompletion) async throws -> AlmanacLocation
    func resolveCurrentCoordinate(_ coordinate: CLLocationCoordinate2D) async throws -> AlmanacLocation
}
```

Use `MKLocalSearch.Request(completion:)` for search selection. Read coordinate, display name, country/administrative area, and placemark time zone. If the first placemark has no zone, perform one reverse-geocode lookup for that coordinate; if still absent, return a stable Almanac location error. Do not use `OSMGeocoder` and do not substitute `TimeZone.current` for remote places.

- [ ] **Step 3: Implement feature-specific dependencies, not a general DI container**

```swift
struct AlmanacDependencies {
    let tideService: any TideServing
    let locationResolver: any AlmanacLocationResolving
    let preferencesStore: AlmanacPreferencesStore
    let now: @Sendable () -> Date

    static func live() -> AlmanacDependencies
    static func uiTestFixture() -> AlmanacDependencies
}
```

`live()` creates the four enabled provider clients with injected `.shared` `URLSession`, `TideDiskCache`, and resolvers. `uiTestFixture()` uses `AlmanacFixtureTideService` and fixed Vancouver data. Fixture mode is selected only when **both** `-ui-testing` and `-almanac-fixture` launch arguments are present.

- [ ] **Step 4: Implement the main-actor view model with cancellable Tasks**

```swift
@MainActor
final class AlmanacViewModel: ObservableObject {
    enum Section: String, CaseIterable { case sun, tides }

    @Published private(set) var location: AlmanacLocation?
    @Published private(set) var selectedDate: LocalDate?
    @Published private(set) var visibleDates: [LocalDate] = []
    @Published var section: Section = .sun
    @Published private(set) var solarDay: SolarDay?
    @Published private(set) var stationContext: TideStationContext?
    @Published private(set) var tideWeek: TideWeek?
    @Published private(set) var tideIsStale = false
    @Published private(set) var tideWarning: TideLoadError?

    func selectDate(_ date: LocalDate)
    func moveWindow(byDays days: Int)
    func selectToday()
    func selectLocation(_ location: AlmanacLocation)
    func useCurrentLocation()
    func selectStation(_ station: TideStation)
    func useNearestStation()
    func loadTides(forceRefresh: Bool = false) async
}
```

The visible strip starts at destination-local today and always contains seven consecutive dates. Previous/next moves the strip by seven days. A date change inside the loaded tide range performs no network call.

On first tide load: resolve station, publish cached week immediately when present, then call `refreshWeek` only when cache is stale or absent. Pull-to-refresh uses `forceRefresh: true`. Cancel prior location/tide Tasks before starting newer ones.

- [ ] **Step 5: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacLocationResolverTests \
  -only-testing:TriangulumTests/AlmanacViewModelTests

git add Triangulum/Features/Almanac/AlmanacLocationResolver.swift \
  Triangulum/Features/Almanac/AlmanacDependencies.swift \
  Triangulum/Features/Almanac/AlmanacViewModel.swift \
  Triangulum/Features/Almanac/AlmanacFixtureTideService.swift \
  TriangulumTests/AlmanacLocationResolverTests.swift \
  TriangulumTests/AlmanacViewModelTests.swift
git commit -m 'feat: add Almanac state and location flow'
```

---

### Task 8: Build Sun/Tides UI with linear Swift Charts and one shared render host

**Files:**
- Create: `TriangulumTests/SwiftUIRenderTestHelper.swift`
- Modify: `TriangulumTests/CelComponentRenderingTests.swift`
- Create: `Triangulum/Features/Almanac/AlmanacView.swift`
- Create: `Triangulum/Features/Almanac/AlmanacLocationSheet.swift`
- Create: `Triangulum/Features/Almanac/AlmanacSunView.swift`
- Create: `Triangulum/Features/Almanac/AlmanacTidesView.swift`
- Create: `Triangulum/Features/Almanac/TideChartView.swift`
- Create: `Triangulum/Features/Almanac/TideStationSheet.swift`
- Create: `TriangulumTests/AlmanacRenderingTests.swift`
- Create: `TriangulumTests/AlmanacPresentationTests.swift`

**Interfaces:**
- Consumes: `AlmanacViewModel`, Cel design tokens/components, `SolarEventKind`, normalized tide events/samples.
- Produces: complete Almanac screen ready for tab wiring.

- [ ] **Step 1: Extract `renderHost` once and keep its current smoke-test semantics**

Move the existing private helper from `CelComponentRenderingTests.swift` into `SwiftUIRenderTestHelper.swift`:

```swift
@MainActor
func renderHost<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 320, height: 568)
) -> (host: UIHostingController<V>, window: UIWindow)
```

Keep the strong `UIWindow` lifetime behavior and update `CelComponentRenderingTests` to call the shared helper. Do not create a third window-retention implementation for Almanac.

SwiftUI's UIKit accessibility tree is not reliably materialized synchronously in these unit tests, so keep `renderHost` as a crash/layout smoke seam. Test exact accessibility strings through pure formatting functions/properties and verify the actual accessible elements in Task 9's XCUITest.

Run the existing Cel rendering suite after the extraction.

- [ ] **Step 2: Build the shared Almanac shell, location sheet, and Sun section**

`AlmanacView` shows:

```text
location + mode + explicit destination time zone
rolling seven-day strip + previous/next + Today
Sun | Tides segmented picker
section content
```

`AlmanacLocationSheet` reuses `AppleSearchCompleter`, offers Current Location, one search field, suggestions, and the last selected fixed place. Add no favourites or saved-location manager.

`AlmanacSunView` leads with sunrise/daylight/sunset, then the explanatory daylight track and typed `SolarEventKind` morning/evening rows. Today shows next-event countdown; another day does not. Polar copy comes from `SolarState`.

- [ ] **Step 3: Build the tide summary, linear chart, event list, and station sheet**

Add pure helpers that the presentation tests can assert directly:

```swift
extension TideWeek {
    func samples(on date: LocalDate, in timeZone: TimeZone) -> [TideSample]
    func events(on date: LocalDate, in timeZone: TimeZone) -> [TideEvent]
    func nextEvent(after instant: Date) -> TideEvent?
}

extension TideChartView {
    static func accessibilitySummary(
        samples: [TideSample],
        events: [TideEvent],
        timeZone: TimeZone
    ) -> String
}
```

The chart must use only official source points:

```swift
Chart {
    ForEach(samples, id: \.instant) { sample in
        LineMark(
            x: .value("Time", sample.instant),
            y: .value("Height", sample.heightMetres)
        )
        // default/linear interpolation only
    }

    ForEach(events, id: \.instant) { event in
        PointMark(
            x: .value("Time", event.instant),
            y: .value("Height", event.heightMetres)
        )
    }
}
```

Do **not** copy `BarometerDetailView`'s `.interpolationMethod(.catmullRom)` or `AreaMark`. Exact high/low markers may sit between hourly line points by design.

`AlmanacTidesView` shows next/first tide, countdown only for today, chart, chronological high/low rows, station distance/datum/provider/update state, cached/offline warning, and `Predictions are for planning only, not navigation.` Pull-to-refresh calls `loadTides(forceRefresh: true)`.

`TideStationSheet` lists at most eight `nearbyStations` plus `Use Nearest Station`.

- [ ] **Step 4: Add rendering smoke tests and exact presentation/accessibility-copy tests**

`AlmanacRenderingTests` uses the shared `renderHost` at narrow iPhone and iPad sizes and asserts only successful window attachment/layout.

`AlmanacPresentationTests` directly asserts:

```text
Sunrise / Sunset / polar copy
next vs first tide labels
high/low event names
chart accessibility summary includes daily range and ordered events
station distance formatting
datum and attribution text
fresh/cached/offline update labels
planning-only warning
```

The final UI test in Task 9 proves those labels are exposed through the actual app accessibility hierarchy.

- [ ] **Step 5: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/CelComponentRenderingTests \
  -only-testing:TriangulumTests/AlmanacRenderingTests \
  -only-testing:TriangulumTests/AlmanacPresentationTests

git add TriangulumTests/SwiftUIRenderTestHelper.swift \
  TriangulumTests/CelComponentRenderingTests.swift \
  Triangulum/Features/Almanac/AlmanacView.swift \
  Triangulum/Features/Almanac/AlmanacLocationSheet.swift \
  Triangulum/Features/Almanac/AlmanacSunView.swift \
  Triangulum/Features/Almanac/AlmanacTidesView.swift \
  Triangulum/Features/Almanac/TideChartView.swift \
  Triangulum/Features/Almanac/TideStationSheet.swift \
  TriangulumTests/AlmanacRenderingTests.swift \
  TriangulumTests/AlmanacPresentationTests.swift
git commit -m 'feat: add Almanac sun and tide views'
```

---

### Task 9: Wire the fifth tab, remove duplicate Solar UI, add deterministic UI smoke, and run all gates

**Files:**
- Modify: `Triangulum/Views/ContentView.swift`
- Modify: `Triangulum/Views/FieldHubView.swift`
- Modify: `Triangulum/Utilities/Log.swift`
- Delete: `Triangulum/Views/SolarEventsView.swift`
- Modify: `TriangulumUITests/BaseUITest.swift`
- Modify: `TriangulumUITests/TriangulumUITests.swift`

**Interfaces:**
- Consumes: complete Almanac feature and `AlmanacDependencies.uiTestFixture()`.
- Produces: five-tab shipping shell, removal of duplicate Solar navigation, and deterministic end-to-end smoke coverage.

- [ ] **Step 1: Make the shell and Almanac UI tests fail first**

Update the existing shell assertion to exactly:

```swift
["Live", "Field", "Almanac", "Footprint", "Settings"]
```

Extend the shared UI-test helper without changing existing callers:

```swift
func makeApp(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing")
    app.launchArguments.append(contentsOf: additionalArguments)
    return app
}
```

Add one Almanac smoke test launched with:

```swift
let app = makeApp(additionalArguments: ["-almanac-fixture"])
```

The test opens Almanac, verifies the fixed fixture location/date context, sees Sunrise/Sunset, switches to Tides, then verifies next tide, chart accessibility label, station, datum, provider attribution, and planning-only warning. Run only these UI tests and confirm they fail before tab wiring.

- [ ] **Step 2: Add `ProductTab.almanac` and the fifth TabView item**

Keep `ProductTab` in `FieldHubView.swift` and add:

```swift
case almanac

case .almanac: "Almanac"
case .almanac: "calendar"
```

In `ContentView`, insert Almanac between Field and Footprint:

```swift
NavigationStack {
    AlmanacView(
        locationManager: locationManager,
        dependencies: isRunningUITests && ProcessInfo.processInfo.arguments.contains("-almanac-fixture")
            ? .uiTestFixture()
            : .live()
    )
}
.tabItem { Label(ProductTab.almanac.title, systemImage: ProductTab.almanac.symbolName) }
.tag(ProductTab.almanac)
```

Remove the Live dashboard Solar `ConsoleTile`. Keep Level unchanged.

- [ ] **Step 3: Remove the superseded Solar screen and add Almanac logging**

Delete `Triangulum/Views/SolarEventsView.swift` after confirming `SolarDay` and all user-facing solar behavior now live under Almanac. Add one `.almanac` `Logger` category; do not add telemetry infrastructure.

- [ ] **Step 4: Run focused UI tests**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumUITests/TriangulumUITests/testMobileShellDisplaysFivePrimaryTabs \
  -only-testing:TriangulumUITests/TriangulumUITests/testAlmanacFixtureShowsSunAndTides
```

Expected: both pass without location permission prompts or public network requests.

- [ ] **Step 5: Run all unit, UI, build, and lint gates**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests

xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumUITests

xcodebuild build -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug -destination "$TRIANGULUM_IPHONE_DESTINATION"

xcodebuild build -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug -destination "$TRIANGULUM_IPAD_DESTINATION"

xcodebuild -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

swiftlint
git diff --check
git diff --stat main...HEAD
```

Expected: unit/UI tests report zero failures (launch performance may skip), both simulator builds and the generic iOS build succeed, SwiftLint reports no errors, and `git diff --check` prints nothing.

- [ ] **Step 6: Commit final wiring and complete the single-PR review checklist**

```bash
git add Triangulum/Views/ContentView.swift \
  Triangulum/Views/FieldHubView.swift \
  Triangulum/Utilities/Log.swift \
  TriangulumUITests/BaseUITest.swift \
  TriangulumUITests/TriangulumUITests.swift
git rm Triangulum/Views/SolarEventsView.swift
git commit -m 'feat: ship Almanac sun and tide tab'
```

Confirm before marking this PR ready:

```text
[ ] Four source contracts are recorded and TideProvider.enabled matches the verified contracts.
[ ] Checked-in fixtures are slim and provenance URLs/dates are recorded.
[ ] Weather and Almanac provider tests share one token-isolated URLProtocol helper.
[ ] Sun uses destination-local LocalDate and existing Astronomer.altAz for polar classification.
[ ] Solar events use SolarEventKind rather than string labels.
[ ] Tides use TideSourceKind for annual/hourly/hilo source caching.
[ ] Sun remains available when tide coverage/provider is unavailable.
[ ] Station selection enforces 250 km / eight-result limits and override reset rules.
[ ] Fresh/stale cache, forced refresh, and partial-response protection pass.
[ ] NOAA subordinate/non-U.S. catalogue rows are excluded.
[ ] JMA uses bundled JapanTideStations.json; there is no HTML parser.
[ ] JMA/HKO New Year ranges combine the correct two annual sources.
[ ] Tide chart uses default/linear LineMark interpolation, PointMark highs/lows, and no AreaMark.
[ ] Cel and Almanac render tests share one UIWindow-retaining renderHost helper.
[ ] The duplicate Solar tile and SolarEventsView are gone.
[ ] The tab bar contains exactly Live, Field, Almanac, Footprint, Settings.
[ ] UI fixture mode requires both -ui-testing and -almanac-fixture.
[ ] No package, backend, SwiftData migration, reachability monitor, AsyncStream, or background scheduler was added.
```

## Execution Notes

- Execute tasks in order; later tasks depend on earlier exact types.
- Keep every task commit buildable or focused-test green; do not split this ticket across PRs.
- When an official source format changes, update its source contract, slim canonical fixture, and parser test together before changing production parsing.
- A provider that fails Task 1 remains represented by its `TideProvider` case but is removed from `TideProvider.enabled`; routing returns `.providerUnavailable` and no runtime client for that provider is wired into `AlmanacDependencies.live()`.
- Do not broaden this task with performance work, persistence migration, marine safety data, or extra provider infrastructure.