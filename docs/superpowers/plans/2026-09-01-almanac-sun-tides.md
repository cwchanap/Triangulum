# Almanac Sun and Tide Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fifth Almanac tab that shows destination-local solar events worldwide and official predicted tides for Canada, the United States, Japan, and Hong Kong, with nearest-station selection and offline reuse.

**Architecture:** Keep the feature under `Triangulum/Features/Almanac/`. `AlmanacViewModel` owns Almanac-only location, the rolling seven-day strip, selected day, and Sun/Tides state. `TideService` uses one closed `TideProvider` switch, the same injected enabled-provider set as coverage routing, selected-station time-zone resolution, and one actor-backed file cache. Provider tests reuse the existing token-isolated weather `URLProtocol` after extracting it to a shared helper; SwiftUI smoke tests reuse the existing UIWindow-retaining render host. There is no backend, package dependency, runtime registry, SwiftData migration, or bundled runtime data-resource layer.

**Tech Stack:** Swift 5 language mode (`SWIFT_VERSION = 5.0`) on the repository's current latest-stable Xcode/Swift toolchain, SwiftUI, Swift Charts, MapKit, CoreLocation, Foundation `URLSession`/`FileManager`/`UserDefaults`, Swift Testing, XCTest UI tests, SwiftLint, iOS 18.5+. Match existing concurrency seams: `@MainActor` for published feature state, an `actor` for disk-cache serialization, injected `URLSession` for networking, cancellable tasks plus generation-token checks for async result application, and no whole-app isolation migration.

**Spec:** `docs/superpowers/specs/2026-09-01-almanac-sun-tides-design.md`

## Global Constraints

- Deliver the approved Sun + Canada + United States + Japan + Hong Kong scope in this **single PR**. Incremental task commits remain in this PR.
- Do not edit `Triangulum.xcodeproj/project.pbxproj`; test fixtures are source-relative test files and JMA/HKO production station catalogues are compiled Swift data, so no new resource membership is required.
- Add no package, backend, reachability monitor, background refresh, favourites system, SwiftData model, AsyncStream, runtime registry, or generic DI container.
- Use `LocalDate` for destination/station civil dates and `Date` for event instants.
- Use selected-location time for Sun and selected-station time for Tides.
- Keep Sun available worldwide; Tides is limited to Canada, the United States, Japan, and Hong Kong.
- Plot official hourly tide points with default/linear `LineMark` interpolation and exact official high/low `PointMark`s. Do not use Catmull-Rom interpolation, `AreaMark`, or synthetic finer precision.
- Auto-select only an eligible station within 250 km and show at most eight manual alternatives.
- Normalize fetched tide ranges only after both hourly and exact high/low inputs are complete. A partial provider response writes nothing.
- Store normalized prediction cache entries by **provider + station + local day**, so tomorrow can reuse the six overlapping days already cached.
- Treat normalized prediction days and remotely fetched station catalogues as fresh for 30 days; explicit pull-to-refresh remains available. Complete stale data remains usable if refresh fails.
- Provider tests use checked-in slim fixtures and injected `URLSession`; automated tests make no public requests.
- Test-only source fixtures load through one `#filePath`-anchored helper. Do not add test-bundle resource plumbing.
- Reuse one shared test `URLProtocol` transport and one shared SwiftUI render host; do not create Almanac-only copies.
- Run tests with `-parallel-testing-enabled NO`.
- Display provider attribution, datum, update state, and `Predictions are for planning only, not navigation.`
- `TideProvider.enabled` is only the production default. `TideCoverageResolver`, `TideService`, and `AlmanacDependencies.live()` must all consume the same injected enabled-provider set so disabled-provider behavior is directly testable.

## Local Command Setup

```bash
xcodebuild -showdestinations -project Triangulum.xcodeproj -scheme Triangulum
export TRIANGULUM_IPHONE_DESTINATION='platform=iOS Simulator,name=iPhone 17'
export TRIANGULUM_IPAD_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

Replace either destination with an exact available simulator from `-showdestinations` when that model is unavailable.

---

### Task 1: Lock four source contracts, slim fixtures, and the typed provider gate

**Files:**
- Create: `docs/almanac-tide-source-contracts.md`
- Create: `Triangulum/Features/Almanac/TideProvider.swift`
- Create: `TriangulumTests/AlmanacFixtureLoader.swift`
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
- Produces: `TideProvider`, the production default `TideProvider.enabled`, provider attribution, one source-relative fixture loader, and canonical slim source fixtures used by Tasks 5–6.

- [ ] **Step 1: Verify and record all four official source contracts**

Create `docs/almanac-tide-source-contracts.md` with one section per provider containing:

```text
runtime catalogue URL or static-catalogue source
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

For CHS, use the documented IWLS **tide tables** endpoint for exact high/low predictions and the `wlp` data series for hourly predictions. Task 1 does not pass until the exact request forms have produced a non-empty Vancouver hourly fixture and a non-empty Vancouver high/low fixture.

For every intended provider, Task 1 passes only when both source forms needed by the common model have been captured and validated:

```text
CHS: hourly + high/low
NOAA: interval=h + interval=hilo
JMA: one fixed-width annual file containing hourly + exact highs/lows
HKO: HHOT + HLT
```

If a provider cannot satisfy direct-use terms or both prediction forms on the implementation date, keep its enum case but omit it from `TideProvider.enabled`; later coverage reports `.providerUnavailable` and Sun remains functional. Do not invent another endpoint or add a proxy.

- [ ] **Step 2: Add the closed provider enum and production default**

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

Edit the `enabled` set in this task if Step 1 disables a source. Do not remove enum cases; supported-but-disabled must remain distinguishable from unsupported geography.

- [ ] **Step 3: Capture full source data temporarily, then commit only named slim fixtures**

```bash
set -euo pipefail
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p TriangulumTests/Fixtures/Almanac/{CHS,NOAA,JMA,HKO}

curl -fsSL 'https://api-iwls.dfo-mpo.gc.ca/api/v1/stations' > "$TMP_DIR/chs-stations.json"
jq '[.[] | select(.code == "07735")]' "$TMP_DIR/chs-stations.json" \
  > TriangulumTests/Fixtures/Almanac/CHS/stations-vancouver.json

curl -fsSL 'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions' \
  > "$TMP_DIR/noaa-stations.json"
python3 - "$TMP_DIR/noaa-stations.json" \
  TriangulumTests/Fixtures/Almanac/NOAA/stations-selection.json <<'PY'
import json, sys
src, dst = sys.argv[1:]
rows = json.load(open(src, encoding='utf-8'))['stations']
reference = next(row for row in rows if row['id'] == '9414290')
subordinate = next(row for row in rows if row.get('type') == 'S')
json.dump({'stations': [reference, subordinate]}, open(dst, 'w', encoding='utf-8'), indent=2)
PY
```

Capture the provider prediction fixtures using the exact URLs recorded in `docs/almanac-tide-source-contracts.md`.

For JMA, retain only the official `TK` station audit row and the `TK.txt` annual file used by the parser. Do not check in or parse the station HTML page.

For HKO, retain only the CSV header plus representative Tai Po Kau rows needed by parser tests; the fixture need not contain the full annual download.

Record full capture URLs and the capture date in the source-contract document. Do not commit full CHS/NOAA catalogues.

- [ ] **Step 4: Add a source-relative fixture loader and prove every enabled provider has readable non-empty fixtures**

```swift
enum AlmanacFixtureLoader {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Almanac", isDirectory: true)

    static func data(_ relativePath: String) throws -> Data {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        guard !data.isEmpty else { throw FixtureError.empty(relativePath) }
        return data
    }
}
```

`TideProviderTests` must open the checked-in files, not merely assert attribution strings:

```swift
@Test func canonicalFixturesAreReadableAndNonEmpty() throws {
    let required = [
        "CHS/stations-vancouver.json",
        "CHS/vancouver-hourly.json",
        "CHS/vancouver-hilo.json",
        "NOAA/stations-selection.json",
        "NOAA/san-francisco-hourly.json",
        "NOAA/san-francisco-hilo.json",
        "JMA/tokyo-station.txt",
        "JMA/tokyo-2026.txt",
        "HKO/tai-po-kau-2026-hourly.csv",
        "HKO/tai-po-kau-2026-hilo.csv"
    ]
    for path in required {
        #expect(try !AlmanacFixtureLoader.data(path).isEmpty)
    }
}
```

Also assert the basic source shape: JSON decodes where expected, NOAA has `.predictions`, JMA data records have the documented 136-byte width, and HKO fixtures contain the captured headers.

This deliberately avoids `Bundle(for:)`: the fixture files are test-only source artifacts and do not need runtime resource membership.

- [ ] **Step 5: Verify the source gate and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideProviderTests

test "$(wc -c < TriangulumTests/Fixtures/Almanac/NOAA/stations-selection.json)" -lt 50000
test "$(wc -c < TriangulumTests/Fixtures/Almanac/CHS/stations-vancouver.json)" -lt 50000
git diff --check

git add docs/almanac-tide-source-contracts.md \
  Triangulum/Features/Almanac/TideProvider.swift \
  TriangulumTests/AlmanacFixtureLoader.swift \
  TriangulumTests/TideProviderTests.swift \
  TriangulumTests/Fixtures/Almanac
git commit -m 'docs: lock Almanac tide source contracts and fixtures'
```

---

### Task 2: Add destination-local dates and persisted Almanac selection

**Files:**
- Create: `Triangulum/Features/Almanac/LocalDate.swift`
- Create: `Triangulum/Features/Almanac/AlmanacLocation.swift`
- Create: `TriangulumTests/AlmanacLocalDateTests.swift`
- Create: `TriangulumTests/AlmanacPreferencesStoreTests.swift`

**Interfaces:**
- Produces: `LocalDate`, `LocalDateRange`, `AlmanacLocation`, `TideStationOverride`, `AlmanacPreferences`, and `AlmanacPreferencesStore` used by every later task.

- [ ] **Step 1: Write failing date and preference tests**

```swift
@Test func sameInstantMapsToDifferentDestinationDates() {
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

Also cover a 25-hour fall day, seven-day ranges across year boundaries, destination-local noon construction, preference round-trip, corrupt JSON returning `.default`, and station-override persistence.

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
    func noon(in timeZone: TimeZone) throws -> Date
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

Use an explicit Gregorian calendar with the supplied `TimeZone`. `noon(in:)` constructs hour 12 from calendar components; do not use `start + 12h` across DST changes. Invalid construction throws `LocalDateError.invalidDate`. Store one JSON preference value; add no migration machinery.

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

### Task 3: Move solar calculations to destination time and typed event kinds

**Files:**
- Create: `Triangulum/Features/Almanac/SolarDay.swift`
- Modify: `Triangulum/Views/ConstellationMapView+Solar.swift`
- Modify: `Triangulum/Views/SolarEventsView.swift`
- Modify: `TriangulumTests/SolarEventsTests.swift`

**Interfaces:**
- Consumes: `LocalDate` and existing `Astronomer.sunEquatorial`, `localSiderealTime`, and `altAz`.
- Produces: destination-aware `solarCrossing`, `SolarEventKind`, `SolarEvent`, `SolarState`, and `SolarDay`.

- [ ] **Step 1: Move solar tests to the new API and add destination/polar coverage**

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

Add `SolarDay` tests at 89°N in June and December for `.polarDay` / `.polarNight`. Run `SolarEventsTests` first and expect signature/initializer failures.

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

Build destination-local noon with `try localDate.noon(in: timeZone)` and retain the existing declination, sidereal-time, transit, and hour-angle math. Remove `Calendar.current` from this calculation path.

- [ ] **Step 3: Move `SolarDay`, use `SolarEventKind`, and reuse `Astronomer.altAz` for polar state**

```swift
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
```

The dawn/dusk wording is an intentional approved Almanac copy change from the old `Astronomical twilight` / `Blue hour begins` labels; test the exact `displayName` mapping so it cannot drift as a side effect of the model move.

When the `-0.833°` sunrise/sunset crossings are both absent, classify with the existing altitude path:

```swift
let noon = try localDate.noon(in: timeZone)
let sun = ConstellationMapView.Astronomer.sunEquatorial(date: noon)
let lst = ConstellationMapView.Astronomer.localSiderealTime(date: noon, longitude: longitude)
let noonAltitude = ConstellationMapView.Astronomer.altAz(eq: sun, lstHours: lst, latDeg: latitude).altDeg
state = noonAltitude > -0.833 ? .polarDay : .polarNight
```

Use the same `-0.833°` threshold as sunrise/sunset rather than introducing another solar-altitude formula.

- [ ] **Step 4: Keep the old Solar screen compiling until final removal, verify, and commit**

Adapt `SolarEventsView` temporarily to construct a device-local `LocalDate` and `SolarDay`; Task 9 removes that screen after Almanac UI reaches parity.

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

### Task 4: Add tide domain, coverage, station selection, and day-keyed file cache

**Files:**
- Create: `Triangulum/Features/Almanac/TideModels.swift`
- Create: `Triangulum/Features/Almanac/TideCoverageResolver.swift`
- Create: `Triangulum/Features/Almanac/TideStationSelector.swift`
- Create: `Triangulum/Features/Almanac/TideDiskCache.swift`
- Create: `TriangulumTests/TideCoverageResolverTests.swift`
- Create: `TriangulumTests/TideStationSelectorTests.swift`
- Create: `TriangulumTests/TideDiskCacheTests.swift`

**Interfaces:**
- Consumes: `TideProvider` and `LocalDateRange`.
- Produces: normalized tide types, injected jurisdiction routing, nearest-station selection, station-catalog persistence, overlapping day-cache reuse, typed annual-source cache keys, and cache APIs used by clients/service/UI.

- [ ] **Step 1: Write failing domain, selector, and cache tests**

Cover:

```text
Canada -> CHS when injected enabled set contains CHS
supported provider absent from injected set -> providerUnavailable
outside supported regions -> unsupportedRegion
Hong Kong fallback routes before broader China
nearest eligible station <= 250 km selected
station beyond 250 km rejected
at most eight alternatives
prediction day fresh for 30 days
stale day still loads with isStale=true
seven-day fetch saved on Sep 1 yields Sep 2 cache hit without a new range key
schema mismatch -> miss
catalogue fresh for 30 days; stale catalogue still readable
catalogue timezone enrichment survives reload
partial provider result never reaches saveCompleteRange
TideSourceKind produces distinct annual/hourly/hilo source paths
```

The Sep 1/Sep 2 overlap test is the regression for the old rolling-range cache-key defect.

- [ ] **Step 2: Implement typed tide models**

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
    var timeZoneIdentifier: String?
    let datumLabel: String
    let supportsHourlyCurve: Bool
    var timeZone: TimeZone? { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) }
}

struct TideSample: Codable, Hashable { let instant: Date; let heightMetres: Double }
struct TideEvent: Codable, Hashable { let kind: TideEventKind; let instant: Date; let heightMetres: Double }

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

`TideWeek` is the provider fetch result. `TideDay` is the selected-day/display and normalized disk-cache unit.

- [ ] **Step 3: Implement injected coverage and station selection**

```swift
struct TideCoverageResolver {
    let enabledProviders: Set<TideProvider>
    func coverage(for location: AlmanacLocation) -> TideCoverage
}

struct TideStationSelector {
    static let maximumAutomaticDistanceMetres = 250_000.0
    static let maximumAlternatives = 8
    func select(from stations: [TideStation], latitude: Double, longitude: Double)
        -> (selected: TideStation?, alternatives: [TideStation])
}
```

Filter to stations that explicitly support **both** prediction inputs — hourly
samples and exact high/low events. This is enforced as a catalogue-admission
invariant so stations lacking either input are excluded before distance-based
matching: CHS rows are admitted only when their `timeSeries` contains both
`wlp` and `wlp-hilo`, and JMA/HKO/NOAA sources supply both forms for every
station by construction (the `supportsHourlyCurve` filter is the selector-side
guard of that invariant). Then calculate distance with `CLLocation`, reject
automatic matches beyond 250 km, and return at most eight sorted alternatives.

- [ ] **Step 4: Implement an actor-backed file cache following the existing TLE fresh→stale→refresh behavior, not the TLE storage class**

`TLECache` is useful precedent for `fresh hit -> stale fallback -> refresh`, and `SatelliteManager` is precedent for retaining stale data while a refresh is attempted. Do **not** reuse `TLECache` itself: it is TLE-specific, UserDefaults-backed, and fixed to 24-hour expiry.

```swift
actor TideDiskCache {
    static let schemaVersion = 1
    static let predictionFreshness: TimeInterval = 30 * 24 * 60 * 60
    static let catalogueFreshness: TimeInterval = 30 * 24 * 60 * 60

    struct CachedDay { let day: TideDay; let isStale: Bool }
    struct CachedCatalog { let stations: [TideStation]; let isStale: Bool }

    init(rootURL: URL, now: @escaping () -> Date = Date.init)

    func loadDay(provider: TideProvider, stationID: String, date: LocalDate) throws -> CachedDay?
    func saveCompleteRange(_ week: TideWeek, in timeZone: TimeZone) throws

    func loadCatalog(provider: TideProvider) throws -> CachedCatalog?
    func saveCatalog(provider: TideProvider, stations: [TideStation], fetchedAt: Date) throws
    func updateCatalogTimeZone(provider: TideProvider, stationID: String, identifier: String) throws -> TideStation

    func loadSource(provider: TideProvider, stationID: String, year: Int, kind: TideSourceKind) throws -> Data?
    func saveSource(_ data: Data, provider: TideProvider, stationID: String, year: Int, kind: TideSourceKind) throws
}
```

Use this layout:

```text
Application Support/Almanac/Tides/
  catalogs/v1/<provider>.json
  days/v1/<provider>/<station>/<yyyy-mm-dd>.json
  sources/jma/<station>/<year>.txt
  sources/hko/<station>/<year>-hourly.csv
  sources/hko/<station>/<year>-hilo.csv
```

`saveCompleteRange` first validates and partitions the **complete** `TideWeek` in memory, encodes every day successfully, then atomically replaces each day file. The service/client layer must never call it for an incomplete hourly/high-low response. This preserves the important completeness invariant without requiring a cross-file transaction.

Annual JMA/HKO source files are immutable by station/year/kind after validation. A cache schema mismatch is a miss; there is no migration code.

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
git commit -m 'feat: add Almanac tide domain and day cache'
```

---

### Task 5: Reuse one test transport and implement all four official tide clients

**Files:**
- Create: `TriangulumTests/TestURLSessionHelper.swift`
- Modify: `TriangulumTests/WeatherManagerTestHelpers.swift`
- Create: `Triangulum/Features/Almanac/TideProviderClient.swift`
- Create: `Triangulum/Features/Almanac/CanadaTideClient.swift`
- Create: `Triangulum/Features/Almanac/UnitedStatesTideClient.swift`
- Create: `Triangulum/Features/Almanac/JapanTideClient.swift`
- Create: `Triangulum/Features/Almanac/HongKongTideClient.swift`
- Create: `Triangulum/Features/Almanac/JapanTideStations.swift`
- Create: `Triangulum/Features/Almanac/HongKongTideStations.swift`
- Create: `TriangulumTests/CanadaTideClientTests.swift`
- Create: `TriangulumTests/UnitedStatesTideClientTests.swift`
- Create: `TriangulumTests/JapanTideClientTests.swift`
- Create: `TriangulumTests/HongKongTideClientTests.swift`

**Interfaces:**
- Consumes: Task 1 contracts/fixtures and Task 4 domain/cache source kinds.
- Produces: shared token-isolated test transport, four `TideProviderClient` implementations, and two compiled static station catalogues.

- [ ] **Step 1: Extract the existing weather URLProtocol into a shared test helper**

Move the current token-isolated behavior from `WeatherManagerTestHelpers.swift` without changing semantics:

```swift
final class TestURLProtocol: URLProtocol {
    static let tokenHeader = "X-Test-URLProtocol-Token"
    // Preserve existing serial queue, per-token response providers,
    // register/unregister lifecycle, and .notAllowed cache policy.
}

enum TestURLSessionHelper {
    static func makeSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> (session: URLSession, cleanup: () -> Void)
}
```

Change `WeatherTestHelper.createMockSession` to delegate to `TestURLSessionHelper.makeSession` and delete `MockWeatherURLProtocol`. Do not create an Almanac-specific transport.

Run existing weather fetch tests before writing provider code:

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/WeatherManagerFetchTests
```

- [ ] **Step 2: Define the small provider-client seam**

```swift
protocol TideProviderClient {
    var provider: TideProvider { get }
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}
```

Every network client receives `URLSession` in `init`, matching `WeatherManager`. Tests use the shared test session; production uses `.shared` from `AlmanacDependencies.live()`.

- [ ] **Step 3: Implement CHS and NOAA against canonical fixtures**

`CanadaTideClient`:

- Fetch the live CHS station catalogue and filter to prediction-capable stations.
- Fetch hourly `wlp` data using the Task 1 contract.
- Fetch exact high/low events through the verified IWLS tide-tables request.
- Preserve datum and normalize metres.
- Reject an incomplete hourly/high-low pair before returning `TideWeek`.

`UnitedStatesTideClient`:

- Parse the `tidepredictions` catalogue.
- Keep only U.S. reference/harmonic rows with `type == "R"`, empty `reference_id`, valid coordinates, and hourly support.
- Exclude subordinate `type == "S"` rows.
- Add one schema-faithful in-memory non-U.S. row in its test rather than bloating the canonical fixture.
- Request predictions in GMT/metric/MLLW once with `interval=h` and once with `interval=hilo`.
- Return `TideWeek` only when both responses validate.

Tests assert filtering, request parameters, metres, event kinds/times, datum, and incomplete-pair rejection.

- [ ] **Step 4: Implement JMA with compiled station data and no runtime resource loader**

Create `JapanTideStations.swift` as a static `[TideStation]` generated from the verified official station table. Do not add JSON/HTML resource loading.

Pin Tokyo against the captured official audit row:

```swift
@Test func tokyoStationMatchesCapturedOfficialRecord() throws {
    let tokyo = try #require(JapanTideStations.all.first { $0.providerStationCode == "TK" })
    #expect(tokyo.name == "Tokyo")
    #expect(abs(tokyo.latitude - 35.65) < 0.0001)
    #expect(abs(tokyo.longitude - 139.7666667) < 0.0001)
}
```

`JapanTideClient` downloads the annual fixed-width `<year>/<station>.txt`, validates documented 136-byte records, slices the requested JST dates, converts centimetres to metres, and emits hourly samples plus exact highs/lows. A New Year range reads two annual source files. Use `TideSourceKind.annual` for source caching.

- [ ] **Step 5: Implement HKO with compiled station data and typed annual source cache kinds**

Create `HongKongTideStations.swift` as the small static intersection of active HHOT/HLT stations. Fetch station/year `HHOT` and `HLT`, parse CSV correctly (quoted commas, CRLF, BOM), slice HKT dates, and reject the range if either source is missing/malformed. A New Year range may require both years. Use `TideSourceKind.hourly` / `.hilo`.

- [ ] **Step 6: Verify all clients plus the shared transport and commit**

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
  Triangulum/Features/Almanac/JapanTideStations.swift \
  Triangulum/Features/Almanac/HongKongTideStations.swift \
  TriangulumTests/CanadaTideClientTests.swift \
  TriangulumTests/UnitedStatesTideClientTests.swift \
  TriangulumTests/JapanTideClientTests.swift \
  TriangulumTests/HongKongTideClientTests.swift
git commit -m 'feat: add official Almanac tide clients'
```

---

### Task 6: Add TideService, one enabled-provider source, station-time-zone enrichment, and cache-first loading

**Files:**
- Create: `Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift`
- Create: `Triangulum/Features/Almanac/TideService.swift`
- Create: `TriangulumTests/TideStationTimeZoneResolverTests.swift`
- Create: `TriangulumTests/TideServiceTests.swift`

**Interfaces:**
- Consumes: provider clients, coverage/selector/cache, and an injected enabled-provider set.
- Produces: selected station context, cached-day read, range refresh, and catalogue enrichment APIs consumed by the view model.

- [ ] **Step 1: Write failing service tests**

Cover:

```text
same injected enabledProviders drives coverage and client dispatch
disabled supported provider -> providerUnavailable without editing static enum
unsupported region remains distinct
nearest station and up to eight alternatives
manual override wins while valid
selected station missing IANA zone is geocoded once, written into cached catalogue, then reused
fresh selected day returns without network
stale selected day returns before refresh
Sep 2 uses day cached by Sep 1 range fetch
forced refresh updates cache on success
forced refresh failure preserves cached day
partial NOAA/HKO result never calls saveCompleteRange
JMA/HKO New Year requests cover both years
```

- [ ] **Step 2: Make time-zone resolution stateless; persist enrichment only in the station catalogue cache**

```swift
protocol TideStationTimeZoneResolving {
    func resolveIdentifier(for station: TideStation) async throws -> String
}

final class TideStationTimeZoneResolver: TideStationTimeZoneResolving {
    func resolveIdentifier(for station: TideStation) async throws -> String
}
```

Return an existing `station.timeZoneIdentifier` immediately. Otherwise reverse geocode only the selected coordinate with `CLGeocoder` and return its IANA identifier. The resolver itself stores nothing in `UserDefaults`.

`TideService` immediately writes a resolved identifier back through `TideDiskCache.updateCatalogTimeZone(...)`; the cached catalogue is the single persistence source of truth. A 30-day catalogue refresh can merge a previous non-nil cached zone into a matching fresh provider row rather than discarding the enrichment.

JMA and HKO static station data should already contain their known fixed zones and bypass geocoding.

- [ ] **Step 3: Implement the closed service switch with injected enablement**

```swift
struct TideStationContext {
    let coverage: TideCoverage
    let selected: TideStation
    let nearbyStations: [TideStation]
    let distanceMetres: Double
    let timeZone: TimeZone
}

struct TideDaySnapshot {
    let day: TideDay
    let isStale: Bool
}

protocol TideServing {
    func resolveStation(for location: AlmanacLocation, override: TideStationOverride?) async throws -> TideStationContext
    func cachedDay(station: TideStation, date: LocalDate) async throws -> TideDaySnapshot?
    func refreshRange(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}
```

`TideService` initializer receives:

```swift
init(
    enabledProviders: Set<TideProvider> = TideProvider.enabled,
    clients: [TideProvider: any TideProviderClient],
    cache: TideDiskCache,
    timeZoneResolver: any TideStationTimeZoneResolving
)
```

Construct `TideCoverageResolver(enabledProviders: enabledProviders)` from the same value. Client dispatch uses typed client parameters with an exhaustive switch over `TideProvider` — each provider maps directly to its client, so a newly added provider requires compiler-enforced handling — and the injected set gates the selected case, never `TideProvider.enabled` directly:

```swift
private func client(for provider: TideProvider) throws -> any TideProviderClient {
    guard enabledProviders.contains(provider) else {
        throw TideLoadError.providerUnavailable
    }
    switch provider {
    case .canadaCHS: return chsClient
    case .unitedStatesNOAA: return noaaClient
    case .japanJMA: return jmaClient
    case .hongKongHKO: return hkoClient
    }
}
```

`resolveStation` uses a fresh cached catalogue first; a stale catalogue is still usable offline while a direct refresh is attempted when needed. Remote CHS/NOAA catalogue fetches save to `TideDiskCache`. JMA/HKO return compiled static catalogues.

`cachedDay` never fetches. `refreshRange` always performs the provider refresh, validates a complete `TideWeek`, then calls `saveCompleteRange`. No reachability check or retry scheduler is introduced.

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

### Task 7: Add AlmanacViewModel, MapKit search, and deterministic dependencies

**Files:**
- Create: `Triangulum/Features/Almanac/AlmanacLocationResolver.swift`
- Create: `Triangulum/Features/Almanac/AlmanacDependencies.swift`
- Create: `Triangulum/Features/Almanac/AlmanacViewModel.swift`
- Create: `Triangulum/Features/Almanac/AlmanacFixtureTideService.swift`
- Create: `TriangulumTests/AlmanacLocationResolverTests.swift`
- Create: `TriangulumTests/AlmanacViewModelTests.swift`

**Interfaces:**
- Consumes: `LocationManager`, `AppleSearchCompleter`, solar model, preferences, and `TideServing`.
- Produces: all observable state/actions required by Almanac plus deterministic `-ui-testing` dependencies.

- [ ] **Step 1: Write failing view-model tests**

Inject a fixed `now` and fake location/tide dependencies. Cover:

```text
launch restores location mode but selected date becomes destination-local today
Almanac fixed location never mutates Live LocationManager coordinates
switching Sun/Tides preserves selected day/location
changing fixed location clears manual station override
current-location movement < 5 km reuses placemark; > 5 km resolves again
manual override survives movement <= 25 km and clears beyond 25 km
remote place without a resolvable time zone is rejected
unsupported tide region still computes SolarDay
fresh cached TideDay publishes without refresh
stale TideDay publishes before one refresh attempt
refresh failure preserves cached TideDay with warning
missing selected day triggers refresh of current rolling seven-day range
older async response cannot overwrite a newer selection
```

- [ ] **Step 2: Implement MapKit resolution by reusing existing Apple search behavior**

```swift
protocol AlmanacLocationResolving {
    func resolveSearchCompletion(_ completion: MKLocalSearchCompletion) async throws -> AlmanacLocation
    func resolveCurrentCoordinate(_ coordinate: CLLocationCoordinate2D) async throws -> AlmanacLocation
}
```

Use `MKLocalSearch.Request(completion:)`. Read coordinate, display name, country/administrative area, and placemark time zone. If absent, perform one reverse-geocode lookup; if still absent, return a stable Almanac location error. Do not use `OSMGeocoder` and do not substitute `TimeZone.current` for a remote place.

- [ ] **Step 3: Implement feature-local dependencies; `-ui-testing` alone selects deterministic Almanac fixtures**

```swift
struct AlmanacDependencies {
    let tideService: any TideServing
    let locationResolver: any AlmanacLocationResolving
    let preferencesStore: AlmanacPreferencesStore
    let now: () -> Date

    static func live(enabledProviders: Set<TideProvider> = TideProvider.enabled) -> AlmanacDependencies
    static func uiTestFixture() -> AlmanacDependencies
}
```

`live(enabledProviders:)` builds client dictionary entries only for that set, injects the same set into `TideService`, and uses `.shared` `URLSession`.

`uiTestFixture()` supplies fixed Vancouver location/time, fixed clock, and `AlmanacFixtureTideService`. In `ContentView`, the existing `-ui-testing` flag alone chooses `.uiTestFixture()` for Almanac. Do not add `-almanac-fixture`, and do not change `BaseUITest.makeApp()` merely to pass a second flag.

- [ ] **Step 4: Implement main-actor state with cancellation plus a generation guard**

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
    @Published private(set) var tideDay: TideDay?
    @Published private(set) var tideIsStale = false
    @Published private(set) var tideWarning: TideLoadError?

    private var requestGeneration = UUID()

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

On every location/station/range-changing action, cancel superseded tasks and replace `requestGeneration`. Capture the generation before each async operation and check it immediately before applying state, following the existing SatelliteManager token-checked result-application pattern.

For tide loading: resolve station, publish `cachedDay` immediately when available, stop on a fresh hit unless `forceRefresh`, otherwise call `refreshRange` for the current seven-day strip. If refresh succeeds, reload the selected day from cache. If it fails and a cached day exists, keep that day and publish a non-blocking warning.

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
- Consumes: `AlmanacViewModel`, Cel components/tokens, `SolarEventKind`, and `TideDay`.
- Produces: complete Almanac UI ready for top-level tab wiring.

- [ ] **Step 1: Extract the existing `renderHost` once and preserve smoke-test semantics**

Move the private helper from `CelComponentRenderingTests.swift` into `SwiftUIRenderTestHelper.swift`:

```swift
@MainActor
func renderHost<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 320, height: 568)
) -> (host: UIHostingController<V>, window: UIWindow)
```

Keep the strong UIWindow lifetime behavior. Update the existing Cel suite to use it. Do not create a third window-retention implementation.

SwiftUI accessibility elements are not reliably materialized synchronously through UIKit in this test seam. Keep render tests as crash/layout coverage; assert exact accessibility copy through pure presentation helpers and the final XCUITest.

- [ ] **Step 2: Build shared shell, location sheet, and Sun content**

`AlmanacView` shows location/mode/time zone, the rolling seven-day strip with previous/next/Today, `Sun | Tides`, and current section content.

`AlmanacLocationSheet` reuses `AppleSearchCompleter`, Current Location, one search field, suggestions, and last selected place. Add no favourites manager.

`AlmanacSunView` leads with sunrise/daylight/sunset, explanatory daylight track, typed morning/evening events, next-event countdown only for destination-local today, and explicit polar copy.

- [ ] **Step 3: Build the tide summary, linear chart, events, and station sheet**

Add pure projection helpers:

```swift
extension TideDay {
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

Chart only official points:

```swift
Chart {
    ForEach(day.hourlySamples, id: \.instant) { sample in
        LineMark(
            x: .value("Time", sample.instant),
            y: .value("Height", sample.heightMetres)
        )
    }
    ForEach(day.events, id: \.instant) { event in
        PointMark(
            x: .value("Time", event.instant),
            y: .value("Height", event.heightMetres)
        )
    }
}
```

Do not copy `BarometerDetailView`'s Catmull-Rom interpolation or `AreaMark` fill.

`AlmanacTidesView` shows next/first tide, countdown only for today, chart, chronological events, station distance/datum/provider/update state, cached/offline warning, and planning-only warning. Pull-to-refresh calls `loadTides(forceRefresh: true)`.

`TideStationSheet` lists at most eight alternatives plus **Use Nearest Station**.

- [ ] **Step 4: Add render smoke and presentation/accessibility-copy tests**

`AlmanacRenderingTests` uses shared `renderHost` at narrow iPhone and iPad sizes and asserts successful attachment/layout.

`AlmanacPresentationTests` directly asserts Sunrise/Sunset/polar copy, SolarEventKind display names, next vs first tide labels, high/low labels, chart summary, station/datum/attribution text, cache-state formatting, and planning-only warning. It also pins the provider-specific legal disclosure strings verbatim: the CHS derivative-product notice (`TideProvider.attributionNotice`), the JMA source and edited-processing notice, and the HKO DATA.GOV.HK source identification acknowledging the Government of the HKSAR, the relevant organisation (the Hong Kong Observatory), and DATA.GOV.HK.

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

### Task 9: Wire the fifth tab, remove duplicate Solar UI, document the new feature folder, and run all gates

**Files:**
- Modify: `Triangulum/Views/ContentView.swift`
- Modify: `Triangulum/Views/FieldHubView.swift`
- Modify: `Triangulum/Utilities/Log.swift`
- Delete: `Triangulum/Views/SolarEventsView.swift`
- Modify: `TriangulumUITests/TriangulumUITests.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: complete Almanac feature and `.uiTestFixture()` selected by existing `-ui-testing` mode.
- Produces: five-tab shipping shell, deterministic end-to-end smoke coverage, removal of duplicate Solar navigation, and documented `Features/Almanac` convention.

- [ ] **Step 1: Make shell and Almanac XCUITests fail first**

Update the existing shell assertion to exactly:

```swift
["Live", "Field", "Almanac", "Footprint", "Settings"]
```

Keep `BaseUITest.makeApp()` unchanged; it already supplies `-ui-testing`.

Add one Almanac smoke test using plain `makeApp()`. It opens Almanac, verifies fixed fixture location/date context, Sunrise/Sunset, switches to Tides, and verifies tide summary, chart accessibility label, station, datum, provider attribution, and planning-only warning. Run these tests before wiring and expect failure because Almanac is not yet in the tab bar.

- [ ] **Step 2: Add `ProductTab.almanac` and the fifth TabView item**

Keep `ProductTab` in `FieldHubView.swift` and add:

```swift
case almanac
case .almanac: "Almanac"
case .almanac: "calendar"
```

Insert Almanac between Field and Footprint. In the existing UI-test path, pass `.uiTestFixture()`; otherwise pass `.live()`. Build only this feature dependency value, not a global container.

Remove the Live Solar `ConsoleTile`; keep Level unchanged.

- [ ] **Step 3: Remove the superseded Solar screen, add logging, and document `Features/`**

Delete `Triangulum/Views/SolarEventsView.swift` after confirming all solar behavior exists under Almanac. Add `Logger.almanac` only.

Update `CLAUDE.md` project structure to document:

```text
Triangulum/Features/Almanac/  # location/date almanac, solar projection, tide providers/cache/UI
```

Explain that cohesive feature-local code may live under `Features/<FeatureName>` while existing sensor surfaces remain in `Views/Managers/Models/Utilities`. Do not reorganize existing files.

- [ ] **Step 4: Run focused UI tests**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_IPHONE_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumUITests/TriangulumUITests/testMobileShellDisplaysFivePrimaryTabs \
  -only-testing:TriangulumUITests/TriangulumUITests/testAlmanacFixtureShowsSunAndTides
```

Expected: both pass without location prompts or public network calls.

- [ ] **Step 5: Run all quality gates**

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

Expected: unit/UI tests report zero failures (launch performance may skip), iPhone/iPad/generic builds succeed, SwiftLint reports no errors, and `git diff --check` prints nothing.

- [ ] **Step 6: Commit final wiring and complete the single-PR review checklist**

```bash
git add Triangulum/Views/ContentView.swift \
  Triangulum/Views/FieldHubView.swift \
  Triangulum/Utilities/Log.swift \
  TriangulumUITests/TriangulumUITests.swift \
  CLAUDE.md
git rm Triangulum/Views/SolarEventsView.swift
git commit -m 'feat: ship Almanac sun and tide tab'
```

Confirm before marking this PR ready:

```text
[ ] Four official source contracts are recorded; every enabled provider has readable non-empty canonical prediction fixtures.
[ ] Checked-in fixtures are slim and loaded source-relative; no new bundle-resource plumbing exists.
[ ] Weather and Almanac network tests share one token-isolated URLProtocol helper.
[ ] Sun uses destination-local LocalDate and existing Astronomer.altAz for polar classification.
[ ] Intentional Almanac dawn/dusk copy is pinned by SolarEventKind tests.
[ ] Coverage and TideService share one injected enabledProviders value.
[ ] Day-keyed cache reuses overlapping dates across rolling windows and uses 30-day prediction freshness.
[ ] Complete stale TideDay remains visible when refresh fails.
[ ] Selected-station time-zone enrichment is stored only in the cached station catalogue.
[ ] TideSourceKind remains only for JMA/HKO annual-source cache files.
[ ] Sun remains available when a tide provider is unavailable.
[ ] Station selection enforces 250 km / eight-result limits and override reset rules.
[ ] Partial hourly/high-low provider responses never write normalized day cache entries.
[ ] NOAA subordinate/non-U.S. rows are excluded.
[ ] JMA/HKO station catalogues are compiled Swift data; there is no runtime HTML/JSON resource loader.
[ ] JMA/HKO New Year ranges combine both annual sources.
[ ] Tide chart uses default/linear LineMark + PointMark and no AreaMark.
[ ] Cel and Almanac render tests share one UIWindow-retaining renderHost helper.
[ ] Existing -ui-testing alone selects deterministic Almanac fixture dependencies.
[ ] Solar tile and SolarEventsView are gone; tab bar is exactly Live, Field, Almanac, Footprint, Settings.
[ ] CLAUDE.md documents the new Features/Almanac convention.
[ ] No package, backend, SwiftData migration, reachability monitor, AsyncStream, or background scheduler was added.
```

## Delivery Decisions and Risks

- **Provider scope remains one PR.** The four-region coverage was explicitly approved for this task, and the project workflow requires one PR per task unless split delivery is approved. The provider seam still makes later maintenance isolated, but this implementation does not create four follow-up PRs for already-approved scope. The formats are also not mechanically identical: JMA/HKO own annual-source parsing/caching and NOAA/CHS have distinct station/prediction contracts.
- **Source-contract feasibility is a hard gate.** Task 1 must capture both required prediction forms for every enabled provider. A missing CHS/HKO/etc. contract blocks that provider before parser work begins.
- **No new bundle-resource plumbing is assumed.** Test fixtures are loaded from the checked-out source tree via `#filePath`; production JMA/HKO station catalogues compile as Swift data.
- **Cache overlap is explicitly tested.** The day-keyed normalized cache exists so a rolling Sep 2 window can reuse Sep 2–7 data fetched on Sep 1 instead of becoming a total cache miss.
- Existing source-drift, station-coverage, datum, and provider-outage risks remain mitigated by strict fixture parsers, explicit station/datum copy, and stale-cache fallback.

## Execution Notes

- Execute tasks in order; later tasks depend on earlier exact types.
- Keep every task commit buildable or focused-test green; do not split this task across PRs.
- When an official source changes, update its contract, slim canonical fixture, and parser test together before changing production parsing.
- A provider that fails Task 1 remains represented by its enum case but is removed from the injected production enabled set; no runtime client is wired for it.
- Do not broaden this task with marine observations, performance work, migrations, or additional provider infrastructure.