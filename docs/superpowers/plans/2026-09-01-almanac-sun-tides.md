# Almanac Sun and Tide Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fifth Almanac tab that shows destination-local solar events worldwide and official predicted tides for Canada, the United States, Japan, and Hong Kong, with nearest-station selection and offline caching.

**Architecture:** Keep the feature under `Triangulum/Features/Almanac/`. `AlmanacViewModel` owns Almanac-only location, rolling seven-day range, selected day, and Sun/Tides state. `TideService` uses one explicit four-provider switch, a selected-station time-zone resolver, and one actor-backed disk cache. There is no backend, package dependency, runtime provider registry, or SwiftData migration.

**Tech Stack:** Swift 5, SwiftUI, Swift Charts, MapKit, CoreLocation, Foundation `URLSession`/`FileManager`/`UserDefaults`, Swift Testing, XCTest UI tests, SwiftLint, latest stable Xcode, iOS 18.5+.

**Spec:** `docs/superpowers/specs/2026-09-01-almanac-sun-tides-design.md`

## Global Constraints

- Deliver all implementation in one PR; incremental task commits remain in that PR.
- Do not edit `Triangulum.xcodeproj/project.pbxproj`; the project uses file-system-synchronised groups.
- Add no package, backend, reachability monitor, background refresh, favourites system, or SwiftData model.
- Use `LocalDate` for destination/station civil days and `Date` for event instants.
- Use selected-location time for Sun and selected-station time for Tides.
- Keep Sun available worldwide; Tides is limited to Canada, the United States, Japan, and Hong Kong.
- Plot official hourly tide points and exact official high/low events separately. Do not synthesize finer precision.
- Auto-select only an eligible station within 250 km and show at most eight manual alternatives.
- Preserve complete stale cache after refresh failure; never replace it with a partial provider response.
- Provider tests use checked-in fixtures and injected `URLSession`; automated tests make no public requests.
- Run tests with `-parallel-testing-enabled NO`.
- Display provider attribution, datum, update state, and `Predictions are for planning only, not navigation.`

## Local Command Setup

```bash
xcodebuild -showdestinations -project Triangulum.xcodeproj -scheme Triangulum
export TRIANGULUM_DESTINATION='platform=iOS Simulator,name=iPhone 17'
```

Use an exact available simulator name when `iPhone 17` is unavailable.

---

### Task 1: Lock source contracts and canonical fixtures

**Files:**
- Create: `docs/almanac-tide-source-contracts.md`
- Create: `TriangulumTests/Fixtures/Almanac/CHS/stations.json`
- Create: `TriangulumTests/Fixtures/Almanac/CHS/vancouver-hourly.json`
- Create: `TriangulumTests/Fixtures/Almanac/CHS/vancouver-hilo.json`
- Create: `TriangulumTests/Fixtures/Almanac/NOAA/stations.json`
- Create: `TriangulumTests/Fixtures/Almanac/NOAA/san-francisco-hourly.json`
- Create: `TriangulumTests/Fixtures/Almanac/NOAA/san-francisco-hilo.json`
- Create: `TriangulumTests/Fixtures/Almanac/JMA/stations-2026.html`
- Create: `TriangulumTests/Fixtures/Almanac/JMA/tokyo-2026.txt`
- Create: `TriangulumTests/Fixtures/Almanac/HKO/tai-po-kau-2026-hourly.csv`
- Create: `TriangulumTests/Fixtures/Almanac/HKO/tai-po-kau-2026-hilo.csv`

**Interfaces:**
- Consumes: official CHS, NOAA, JMA, and HKO source contracts.
- Produces: immutable parser fixtures and the attribution/licensing contract used by Tasks 6–9 and 13.

- [ ] **Step 1: Record the verified source contract**

Create `docs/almanac-tide-source-contracts.md` with one row per provider containing runtime URL, prediction forms, direct-use status, attribution, datum behavior, request limits, and fixture date. Include the full required CHS derivative-product notice and these official references:

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

A provider remains enabled only when direct iOS use and complete hourly-plus-high/low predictions are verified on the implementation date.

- [ ] **Step 2: Capture live fixtures**

Run from the repository root:

```bash
set -euo pipefail
mkdir -p TriangulumTests/Fixtures/Almanac/{CHS,NOAA,JMA,HKO}

curl -fsSL 'https://api-iwls.dfo-mpo.gc.ca/api/v1/stations' \
  > TriangulumTests/Fixtures/Almanac/CHS/stations.json
CHS_ID=$(jq -r '.[] | select(.code == "07735") | .id' \
  TriangulumTests/Fixtures/Almanac/CHS/stations.json | head -n 1)
test -n "$CHS_ID"
curl -fsSL --get "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/${CHS_ID}/data" \
  --data-urlencode 'time-series-code=wlp' \
  --data-urlencode 'resolution=SIXTY_MINUTES' \
  --data-urlencode 'from=2026-09-01T07:00:00Z' \
  --data-urlencode 'to=2026-09-08T07:00:00Z' \
  > TriangulumTests/Fixtures/Almanac/CHS/vancouver-hourly.json
curl -fsSL --get "https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/${CHS_ID}/data" \
  --data-urlencode 'time-series-code=wlp-hilo' \
  --data-urlencode 'from=2026-09-01T07:00:00Z' \
  --data-urlencode 'to=2026-09-08T07:00:00Z' \
  > TriangulumTests/Fixtures/Almanac/CHS/vancouver-hilo.json

curl -fsSL 'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions' \
  > TriangulumTests/Fixtures/Almanac/NOAA/stations.json
curl -fsSL 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&application=Triangulum&begin_date=20260901&end_date=20260907&datum=MLLW&station=9414290&time_zone=gmt&units=metric&interval=h&format=json' \
  > TriangulumTests/Fixtures/Almanac/NOAA/san-francisco-hourly.json
curl -fsSL 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&application=Triangulum&begin_date=20260901&end_date=20260907&datum=MLLW&station=9414290&time_zone=gmt&units=metric&interval=hilo&format=json' \
  > TriangulumTests/Fixtures/Almanac/NOAA/san-francisco-hilo.json

curl -fsSL 'https://www.data.jma.go.jp/kaiyou/db/tide/suisan/station2026.php' \
  > TriangulumTests/Fixtures/Almanac/JMA/stations-2026.html
curl -fsSL 'https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/2026/TK.txt' \
  > TriangulumTests/Fixtures/Almanac/JMA/tokyo-2026.txt

curl -fsSL 'https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=HHOT&station=TPK&year=2026&rformat=csv' \
  > TriangulumTests/Fixtures/Almanac/HKO/tai-po-kau-2026-hourly.csv
curl -fsSL 'https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=HLT&station=TPK&year=2026&rformat=csv' \
  > TriangulumTests/Fixtures/Almanac/HKO/tai-po-kau-2026-hilo.csv
```

Validate non-empty JSON arrays, NOAA `.predictions`, JMA lines of exactly 136 bytes, and HKO headers plus data. When an official parameter changed, update the contract and fixture command to the documented replacement; do not invent a fallback.

- [ ] **Step 3: Commit the source gate**

```bash
git add docs/almanac-tide-source-contracts.md TriangulumTests/Fixtures/Almanac
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

- [ ] **Step 1: Write failing tests**

Test that one instant maps to different Vancouver/Tokyo dates, rolling seven-day ranges cross year boundaries, Vancouver daylight-saving days are 23/25 hours, preferences round-trip, and corrupt preferences return `.default`.

```swift
#expect(LocalDate(instant, in: vancouver) == .init(year: 2026, month: 8, day: 31))
#expect(LocalDate(instant, in: tokyo) == .init(year: 2026, month: 9, day: 1))
#expect(try LocalDate(year: 2026, month: 3, day: 8)
    .endExclusive(in: vancouver)
    .timeIntervalSince(LocalDate(year: 2026, month: 3, day: 8).start(in: vancouver)) == 23 * 3600)
```

Run and expect missing types:

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacLocalDateTests \
  -only-testing:TriangulumTests/AlmanacPreferencesStoreTests
```

- [ ] **Step 2: Implement the exact model boundary**

```swift
struct LocalDate: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int
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

Use an explicit Gregorian calendar and time zone. Invalid date construction throws `LocalDateError.invalidDate`. Store one JSON value in `UserDefaults`; add no migration code.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacLocalDateTests \
  -only-testing:TriangulumTests/AlmanacPreferencesStoreTests
git add Triangulum/Features/Almanac/LocalDate.swift \
  Triangulum/Features/Almanac/AlmanacLocation.swift \
  TriangulumTests/AlmanacLocalDateTests.swift \
  TriangulumTests/AlmanacPreferencesStoreTests.swift
git commit -m 'feat: add Almanac local date and selection state'
```

---

### Task 3: Move solar calculations to an explicit destination time zone

**Files:**
- Create: `Triangulum/Features/Almanac/SolarDay.swift`
- Modify: `Triangulum/Views/ConstellationMapView+Solar.swift`
- Modify: `Triangulum/Views/SolarEventsView.swift`
- Modify: `TriangulumTests/SolarEventsTests.swift`

**Interfaces:**
- Consumes: `LocalDate` from Task 2.
- Produces: destination-aware `solarCrossing`, `SolarDay`, `SolarEvent`, and `SolarState` used by the view model and Sun UI.

- [ ] **Step 1: Make solar tests fail on the new API**

Add explicit Tokyo-date and polar day/night tests. Change direct crossing calls to:

```swift
ConstellationMapView.Astronomer.solarCrossing(
    altitudeDeg: -0.833,
    rising: true,
    localDate: .init(year: 2026, month: 9, day: 1),
    timeZone: TimeZone(identifier: "Asia/Tokyo")!,
    latDeg: 35.6762,
    lonDeg: 139.6503
)
```

Run `SolarEventsTests`; expect signature/initializer failures.

- [ ] **Step 2: Change the crossing boundary and move `SolarDay`**

```swift
static func solarCrossing(
    altitudeDeg: Double,
    rising: Bool,
    localDate: LocalDate,
    timeZone: TimeZone,
    latDeg: Double,
    lonDeg: Double
) -> Date?

enum SolarState: Equatable { case normal, polarDay, polarNight }
struct SolarEvent: Equatable { let label: String; let instant: Date }

struct SolarDay {
    let localDate: LocalDate
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone
    let state: SolarState
    var allEvents: [SolarEvent] { get }
    var daylightDuration: TimeInterval? { get }
    func nextEvent(after instant: Date) -> SolarEvent?
}
```

Construct destination-local noon with an explicit Gregorian calendar, then retain the existing declination, hour-angle, and transit math. Keep all ten current crossings. When sunrise and sunset are both absent, classify polar day/night from the Sun altitude at destination-local noon. Remove the old model declaration from `SolarEventsView`, but keep that view compiling until Task 14.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/SolarEventsTests
git add Triangulum/Features/Almanac/SolarDay.swift \
  Triangulum/Views/ConstellationMapView+Solar.swift \
  Triangulum/Views/SolarEventsView.swift TriangulumTests/SolarEventsTests.swift
git commit -m 'refactor: make solar events destination-time-zone aware'
```

---

### Task 4: Add tide domain, coverage, station selection, and test factories

**Files:**
- Create: `Triangulum/Features/Almanac/TideModels.swift`
- Create: `Triangulum/Features/Almanac/TideCoverageResolver.swift`
- Create: `Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift`
- Create: `TriangulumTests/AlmanacTestFixtures.swift`
- Create: `TriangulumTests/TideCoverageResolverTests.swift`
- Create: `TriangulumTests/TideStationSelectorTests.swift`

**Interfaces:**
- Produces: the normalized tide types and closed provider protocol used by cache, adapters, service, view model, and UI.

- [ ] **Step 1: Write failing routing and selection tests**

Cover CA→CHS, US→NOAA, JP→JMA, HK→HKO, Hong Kong coordinates with broad `CN` metadata, unsupported UK, exclusion of non-hourly stations, 250 km rejection, ascending distance ordering, and maximum eight results.

- [ ] **Step 2: Implement the normalized boundary**

```swift
enum TideProvider: String, Codable, CaseIterable {
    case canadaCHS, unitedStatesNOAA, japanJMA, hongKongHKO
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
    var timeZone: TimeZone? { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) }
    func resolvingTimeZone(_ identifier: String) -> TideStation
}

struct TideStationDistance: Codable, Hashable {
    let station: TideStation
    let distanceMetres: Double
}

struct TideSample: Codable, Hashable { let instant: Date; let heightMetres: Double }
struct TideEvent: Codable, Hashable {
    enum Kind: String, Codable { case high, low }
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

enum TideLoadError: Error, Equatable {
    case unsupportedRegion, noStationNearby, networkUnavailable
    case providerUnavailable, invalidProviderResponse, noPredictions
}

protocol TideProviderClient: Sendable {
    var provider: TideProvider { get }
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}
```

`TideCoverageResolver` applies the narrow Hong Kong fallback before country routing. `TideStationSelector` filters `supportsHourlyCurve`, calculates `CLLocation` distance, rejects beyond `250_000`, sorts ascending, and returns `prefix(8)`. Define `overrideResetDistanceMetres = 25_000`. Declare `TideStationTimeZoneResolving`; implement it in Task 10.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideCoverageResolverTests \
  -only-testing:TriangulumTests/TideStationSelectorTests
git add Triangulum/Features/Almanac/TideModels.swift \
  Triangulum/Features/Almanac/TideCoverageResolver.swift \
  Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift \
  TriangulumTests/AlmanacTestFixtures.swift \
  TriangulumTests/TideCoverageResolverTests.swift \
  TriangulumTests/TideStationSelectorTests.swift
git commit -m 'feat: add Almanac tide domain and station selection'
```

---

### Task 5: Add actor-backed tide caching

**Files:**
- Create: `Triangulum/Features/Almanac/TideDiskCache.swift`
- Create: `TriangulumTests/TideDiskCacheTests.swift`

**Interfaces:**
- Produces: complete normalized week, station-catalogue, and annual raw-source storage used by all providers and `TideService`.

- [ ] **Step 1: Write failing cache tests**

Cover fresh at 23 hours, stale at 25 hours, 30-day catalogue freshness, corrupt JSON, schema mismatch, distinct station/range keys, raw annual source round-trip, and preservation of unrelated valid entries.

- [ ] **Step 2: Implement one cache actor**

```swift
enum CacheFreshness: Equatable { case fresh, stale }
struct CachedValue<Value> { let value: Value; let freshness: CacheFreshness }

actor TideDiskCache {
    static let schemaVersion = 1
    static let weekFreshness: TimeInterval = 24 * 3600
    static let catalogFreshness: TimeInterval = 30 * 24 * 3600

    init(rootURL: URL? = nil, fileManager: FileManager = .default,
         now: @escaping @Sendable () -> Date = Date.init)
    func loadWeek(provider: TideProvider, stationID: String,
                  range: LocalDateRange) throws -> CachedValue<TideWeek>?
    func saveWeek(_ week: TideWeek) throws
    func loadCatalog(provider: TideProvider) throws -> CachedValue<[TideStation]>?
    func saveCatalog(_ stations: [TideStation], provider: TideProvider,
                     fetchedAt: Date) throws
    func loadSource(provider: TideProvider, stationCode: String,
                    year: Int, kind: String) throws -> Data?
    func saveSource(_ data: Data, provider: TideProvider, stationCode: String,
                    year: Int, kind: String) throws
}
```

Default root is `Application Support/Almanac/Tides`. Encode `{schemaVersion,savedAt,value}` envelopes, sanitize path components to `[A-Za-z0-9._-]`, create parent directories, and use `Data.write(options: .atomic)`. Decode/version failure is a clean miss; do not delete other entries.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideDiskCacheTests
git add Triangulum/Features/Almanac/TideDiskCache.swift TriangulumTests/TideDiskCacheTests.swift
git commit -m 'feat: cache Almanac tide data atomically'
```

---

### Task 6: Implement the CHS adapter and reusable URL fixture transport

**Files:**
- Create: `Triangulum/Features/Almanac/CanadaTideClient.swift`
- Create: `TriangulumTests/AlmanacURLProtocol.swift`
- Create: `TriangulumTests/CanadaTideClientTests.swift`

**Interfaces:**
- Consumes: tide domain from Task 4 and canonical CHS fixtures from Task 1.
- Produces: `.canadaCHS` catalogue and complete normalized weeks.

- [ ] **Step 1: Add a token-isolated test `URLProtocol`**

```swift
final class AlmanacURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    static func register(_ handler: @escaping Handler) -> String
    static func unregister(_ token: String)
    static func session(token: String) -> URLSession
}
```

Store handlers behind a serial queue, pass the token through `X-Almanac-Test-Token`, return responses through `URLProtocolClient`, and unregister with `defer`. Do not modify `MockWeatherURLProtocol`.

- [ ] **Step 2: Write failing request and parser tests**

Assert `wlp`, `resolution=SIXTY_MINUTES`, `wlp-hilo`, UTC range bounds, Vancouver `07735`, finite metre values, official high and low event types, datum, attribution, and rejection when either companion response is non-2xx or malformed. Never infer alternating high/low rows.

- [ ] **Step 3: Implement, verify, and commit**

```swift
struct CanadaTideClient: TideProviderClient {
    let provider: TideProvider = .canadaCHS
    let session: URLSession
    let now: @Sendable () -> Date
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation,
                         range: LocalDateRange) async throws -> TideWeek
}
```

Build requests with `URLComponents`. Fetch hourly and high/low responses concurrently, then construct a week only after both validate.

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/CanadaTideClientTests
git add Triangulum/Features/Almanac/CanadaTideClient.swift \
  TriangulumTests/AlmanacURLProtocol.swift TriangulumTests/CanadaTideClientTests.swift
git commit -m 'feat: add Canadian tide prediction adapter'
```

---

### Task 7: Implement the NOAA reference-station adapter

**Files:**
- Create: `Triangulum/Features/Almanac/UnitedStatesTideClient.swift`
- Create: `TriangulumTests/UnitedStatesTideClientTests.swift`

**Interfaces:**
- Consumes: tide domain and `AlmanacURLProtocol`.
- Produces: `.unitedStatesNOAA` reference-station catalogue and complete normalized weeks.

- [ ] **Step 1: Write failing NOAA tests**

Assert metadata uses `type=tidepredictions`; retain only `type == "R"` with a non-empty U.S. state/territory code; exclude `type == "S"` and international `TEC`/`TWC` entries. Station `9414290` remains eligible with `timeZoneIdentifier == nil` until Task 10 resolves it.

Assert prediction requests include:

```text
product=predictions
application=Triangulum
station=9414290
datum=MLLW
time_zone=gmt
units=metric
format=json
interval=h / interval=hilo
```

Verify `H`→high, `L`→low, metres, GMT parsing, and all-or-nothing companion responses.

- [ ] **Step 2: Implement, verify, and commit**

```swift
struct UnitedStatesTideClient: TideProviderClient {
    let provider: TideProvider = .unitedStatesNOAA
    let session: URLSession
    let now: @Sendable () -> Date
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation,
                         range: LocalDateRange) async throws -> TideWeek
}
```

Guard that predictions receive a station with a valid IANA zone. Fetch `h` and `hilo` concurrently in GMT, parse `yyyy-MM-dd HH:mm` with a fixed GMT formatter, and preserve `MLLW`.

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/UnitedStatesTideClientTests
git add Triangulum/Features/Almanac/UnitedStatesTideClient.swift \
  TriangulumTests/UnitedStatesTideClientTests.swift
git commit -m 'feat: add NOAA tide prediction adapter'
```

---

### Task 8: Implement the JMA annual fixed-width adapter

**Files:**
- Create: `Triangulum/Features/Almanac/JapanTideClient.swift`
- Create: `Triangulum/Features/Almanac/Resources/JapanTideStations.json`
- Create: `TriangulumTests/JapanTideClientTests.swift`

**Interfaces:**
- Consumes: tide domain, disk cache, JMA fixtures.
- Produces: `.japanJMA` stations and locally sliced seven-day weeks.

- [ ] **Step 1: Build and validate the bundled station catalogue**

Convert every current row in `stations-2026.html` with a two-character code, name, and valid coordinate. Exclude only rows explicitly marked closed/discontinued, sort by code, reject duplicates, and store:

```json
{
  "sourceYear": 2026,
  "stations": [{
    "code": "TK",
    "name": "Tokyo",
    "latitude": 35.6547,
    "longitude": 139.7704,
    "timeZoneIdentifier": "Asia/Tokyo",
    "datumLabel": "JMA Tide Table Datum"
  }]
}
```

Add a resource test for unique codes, valid coordinates/time zone, and `TK` presence.

- [ ] **Step 2: Write failing fixed-width tests**

Test the exact 136-byte layout: `0..<72` hourly values, `72..<78` date, `78..<80` station code, `80..<108` highs, and `108..<136` lows. Cover 24 hourly samples, exact highs/lows, negative three-byte heights, `9999`/`999` sentinels, centimetres→metres, wrong width, wrong year, and a New Year range requiring two files.

- [ ] **Step 3: Implement, verify, and commit**

```swift
enum JapanTideLineParser {
    static let lineLength = 136
    static func parse(_ line: String, fullYear: Int,
                      timeZone: TimeZone) throws -> JapanTideDay
}

struct JapanTideClient: TideProviderClient {
    let provider: TideProvider = .japanJMA
    let session: URLSession
    let cache: TideDiskCache
    let now: @Sendable () -> Date
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation,
                         range: LocalDateRange) async throws -> TideWeek
}
```

Use byte-safe ASCII slicing. Load each required year from raw cache or `https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/{YEAR}/{STATION}.txt`, cache unmodified bytes, parse in `Asia/Tokyo`, and slice the requested range.

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/JapanTideClientTests
git add Triangulum/Features/Almanac/JapanTideClient.swift \
  Triangulum/Features/Almanac/Resources/JapanTideStations.json \
  TriangulumTests/JapanTideClientTests.swift
git commit -m 'feat: add JMA tide prediction adapter'
```

---

### Task 9: Implement the HKO annual CSV adapter

**Files:**
- Create: `Triangulum/Features/Almanac/HongKongTideClient.swift`
- Create: `Triangulum/Features/Almanac/Resources/HongKongTideStations.json`
- Create: `TriangulumTests/HongKongTideClientTests.swift`

**Interfaces:**
- Consumes: tide domain, disk cache, HKO fixtures.
- Produces: `.hongKongHKO` stations and locally sliced seven-day weeks.

- [ ] **Step 1: Build and validate the bundled station catalogue**

Use the intersection of active station codes in the 2026 HHOT and HLT listings. Include all intersecting active stations, exclude entries explicitly marked closed, sort by code, reject duplicates, and store the same `{sourceYear,stations}` shape with `Asia/Hong_Kong` and official coordinates. Test `TPK` presence and Hong Kong coordinate bounds.

- [ ] **Step 2: Write failing CSV tests**

Assert HHOT/HLT URLs contain station, year, and `rformat=csv`; hourly and event rows parse in Hong Kong time; quoted fields, embedded commas, CRLF, and BOM work; malformed headers fail; New Year uses two years; and one failed companion source cannot create a week.

- [ ] **Step 3: Implement, verify, and commit**

```swift
struct HongKongTideClient: TideProviderClient {
    let provider: TideProvider = .hongKongHKO
    let session: URLSession
    let cache: TideDiskCache
    let now: @Sendable () -> Date
    func loadStationCatalog() async throws -> [TideStation]
    func loadPredictions(station: TideStation,
                         range: LocalDateRange) async throws -> TideWeek
}
```

Build URLs with `dataType=HHOT|HLT`, `station`, `year`, and `rformat=csv`. Implement one feature-local CSV reader; add no package. Cache unmodified annual sources, combine all required years, validate both source types, then slice.

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/HongKongTideClientTests
git add Triangulum/Features/Almanac/HongKongTideClient.swift \
  Triangulum/Features/Almanac/Resources/HongKongTideStations.json \
  TriangulumTests/HongKongTideClientTests.swift
git commit -m 'feat: add HKO tide prediction adapter'
```

---

### Task 10: Implement station time-zone resolution and cache-first `TideService`

**Files:**
- Modify: `Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift`
- Create: `Triangulum/Features/Almanac/TideService.swift`
- Create: `TriangulumTests/TideServiceTests.swift`

**Interfaces:**
- Consumes: all provider clients, cache, coverage resolver, station selector, preferences override.
- Produces: one stable service snapshot consumed by `AlmanacViewModel`.

- [ ] **Step 1: Write failing service tests**

Use counting/suspending fake clients and a fake time-zone resolver. Cover fresh cache without provider fetch; stale cache returned immediately; forced refresh replacing stale cache; forced refresh failure preserving stale content; nearest/override selection; override anchor beyond 25 km ignored; missing station zone resolved once and persisted; unsupported region invoking no client; complete response replacing cache; partial response not replacing cache; and same station/range reusing the same key.

- [ ] **Step 2: Define the exact service contract**

```swift
enum TideDataSource: Equatable { case live, freshCache, staleCache }

protocol TideStationTimeZoneResolving: Sendable {
    func timeZoneIdentifier(latitude: Double,
                            longitude: Double) async throws -> String
}

struct CoreLocationStationTimeZoneResolver: TideStationTimeZoneResolving {
    func timeZoneIdentifier(latitude: Double,
                            longitude: Double) async throws -> String
}

struct TideLoadSnapshot: Equatable {
    let station: TideStationDistance
    let nearbyStations: [TideStationDistance]
    let week: TideWeek
    let source: TideDataSource
    let warning: TideLoadError?
}

protocol TideServicing: Sendable {
    func load(location: AlmanacLocation, range: LocalDateRange,
              stationOverride: TideStationOverride?,
              forceRefresh: Bool) async throws -> TideLoadSnapshot
}
```

- [ ] **Step 3: Implement the closed-provider service**

Use an explicit provider switch. Resolve provider; use cached catalogue including stale; fetch when missing or forced; select nearest/manual station and validate the 25 km override anchor; resolve and persist a missing IANA time zone; return any complete fresh/stale week immediately when not forced; otherwise fetch, validate, atomically save, and return `.live`. Map time-zone geocode transport failure to `.networkUnavailable` and missing zone to `.invalidProviderResponse`.

Do not add an `AsyncStream`; the view model performs a second forced call after displaying stale cache.

- [ ] **Step 4: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/TideServiceTests
git add Triangulum/Features/Almanac/TideStationTimeZoneResolver.swift \
  Triangulum/Features/Almanac/TideService.swift TriangulumTests/TideServiceTests.swift
git commit -m 'feat: orchestrate Almanac tide loading and cache fallback'
```

---

### Task 11: Add location resolution, view-model state, and live composition

**Files:**
- Create: `Triangulum/Features/Almanac/AlmanacLocationResolver.swift`
- Create: `Triangulum/Features/Almanac/AlmanacViewModel.swift`
- Create: `Triangulum/Features/Almanac/AlmanacDependencies.swift`
- Create: `TriangulumTests/AlmanacLocationResolverTests.swift`
- Create: `TriangulumTests/AlmanacViewModelTests.swift`

**Interfaces:**
- Consumes: solar model, tide service, preferences store, shared `LocationManager` readings.
- Produces: one `@MainActor` state owner and one feature-local production factory used by the views.

- [ ] **Step 1: Write failing resolver and view-model tests**

Cover search success, reverse-geocode fallback when search lacks a time zone, rejection when no zone resolves, Current Location geocoding only after first fix/5 km, startup restoring mode but resetting to destination-local today, default `.sun`, shared day across sections, fixed-location override reset, Current Location override retention below 25 km/reset above, unsupported Tides preserving Sun, forced refresh, stale-cache-first behavior, and old asynchronous response suppression.

- [ ] **Step 2: Implement the location seam**

```swift
@MainActor
protocol AlmanacLocationSearching {
    func resolve(completion: MKLocalSearchCompletion) async throws -> AlmanacResolvedPlacemark
    func reverseGeocode(latitude: Double,
                        longitude: Double) async throws -> AlmanacResolvedPlacemark
}

struct AlmanacResolvedPlacemark: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let displayName: String
    let timeZoneIdentifier: String?
    let countryCode: String?
    let administrativeArea: String?
}

@MainActor
struct AlmanacLocationResolver: AlmanacLocationSearching { }
```

Use `MKLocalSearch.Request(completion:)`. Never use `TimeZone.current` as a remote fallback.

- [ ] **Step 3: Implement the `@MainActor` view model**

```swift
@MainActor
final class AlmanacViewModel: ObservableObject {
    enum Section: String, CaseIterable { case sun = "Sun", tides = "Tides" }
    enum TidePhase: Equatable {
        case idle, resolvingStation
        case loading(stationName: String?)
        case loaded(TideLoadSnapshot)
        case failed(TideLoadError)
    }

    @Published private(set) var location: AlmanacLocation?
    @Published var selectedDate: LocalDate
    @Published var visibleRange: LocalDateRange
    @Published var selectedSection: Section = .sun
    @Published private(set) var solarDay: SolarDay?
    @Published private(set) var tidePhase: TidePhase = .idle
    @Published var isLocationSheetPresented = false

    init(tideService: any TideServicing,
         locationResolver: any AlmanacLocationSearching,
         preferencesStore: AlmanacPreferencesStore,
         now: @escaping @Sendable () -> Date = Date.init)

    func useCurrentLocation(latitude: Double, longitude: Double,
                            permissionGranted: Bool) async
    func selectSearchCompletion(_ completion: MKLocalSearchCompletion) async
    func selectLocation(_ placemark: AlmanacResolvedPlacemark) throws
    func selectDate(_ date: LocalDate)
    func moveWindow(byDays: Int)
    func returnToToday()
    func chooseStation(_ station: TideStationDistance)
    func useNearestStation()
    func loadTides(forceRefresh: Bool = false) async
}
```

Use separate cancellable location/tide tasks plus a request-key or generation check. A normal load applies stale cache, then starts one forced refresh. Refresh failure keeps `.loaded` and adds a warning.

- [ ] **Step 4: Add one feature-local production factory**

```swift
@MainActor
struct AlmanacDependencies {
    let tideService: any TideServicing
    let locationResolver: any AlmanacLocationSearching
    let preferencesStore: AlmanacPreferencesStore
    let now: @Sendable () -> Date
    static func live() -> AlmanacDependencies
}
```

`live()` creates one cache, `URLSession.shared`, four clients, `CoreLocationStationTimeZoneResolver`, `AlmanacLocationResolver`, and preferences store. This is not a general application container.

- [ ] **Step 5: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacLocationResolverTests \
  -only-testing:TriangulumTests/AlmanacViewModelTests
git add Triangulum/Features/Almanac/AlmanacLocationResolver.swift \
  Triangulum/Features/Almanac/AlmanacViewModel.swift \
  Triangulum/Features/Almanac/AlmanacDependencies.swift \
  TriangulumTests/AlmanacLocationResolverTests.swift \
  TriangulumTests/AlmanacViewModelTests.swift
git commit -m 'feat: manage Almanac location date and loading state'
```

---

### Task 12: Build the Almanac shell and Sun section

**Files:**
- Create: `Triangulum/Features/Almanac/AlmanacView.swift`
- Create: `Triangulum/Features/Almanac/AlmanacLocationSheet.swift`
- Create: `Triangulum/Features/Almanac/AlmanacSunView.swift`
- Create: `TriangulumTests/AlmanacSunRenderingTests.swift`

**Interfaces:**
- Consumes: `AlmanacViewModel`, `AppleSearchCompleter`, Cel design system, `SolarDay`.
- Produces: shared Almanac header, search sheet, date navigation, and solar presentation.

- [ ] **Step 1: Write failing rendering and accessibility tests**

Render fixed Tokyo normal, polar-day, and polar-night states through the existing `UIHostingController` helper pattern. Assert location/time-zone context, Sunrise/Daylight/Sunset, morning/evening groups, and explicit polar copy.

- [ ] **Step 2: Implement the shell and location sheet**

```swift
struct AlmanacView: View {
    @ObservedObject var locationManager: LocationManager
    @StateObject private var viewModel: AlmanacViewModel

    @MainActor
    init(locationManager: LocationManager,
         dependencies: AlmanacDependencies)
}
```

The persistent header shows location mode, readable zone plus UTC offset, rolling seven dates, previous/next seven-day actions, Today, and Sun/Tides picker. Observe GPS only in Current Location mode. Loading Tides or moving the seven-day window starts a view-model task; changing a day inside the loaded range only reprojects data.

`AlmanacLocationSheet` owns one `AppleSearchCompleter`, calls `viewModel.selectSearchCompletion`, shows Current Location, up to six suggestions, last fixed location, search/time-zone errors, and existing app-Settings remediation. Add no favourites management.

- [ ] **Step 3: Implement the Sun summary and timeline**

Show primary sunrise/daylight/sunset metrics, a simple civil-dawn-to-civil-dusk track, next-event countdown only for destination-local today, all ten event rows, and explicit polar states. Use `TimelineView(.periodic(from: .now, by: 60))`; add no timer manager.

- [ ] **Step 4: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacSunRenderingTests
git add Triangulum/Features/Almanac/AlmanacView.swift \
  Triangulum/Features/Almanac/AlmanacLocationSheet.swift \
  Triangulum/Features/Almanac/AlmanacSunView.swift \
  TriangulumTests/AlmanacSunRenderingTests.swift
git commit -m 'feat: add Almanac shell and solar display'
```

---

### Task 13: Build Tides summary, chart, event list, and station picker

**Files:**
- Create: `Triangulum/Features/Almanac/AlmanacTidesView.swift`
- Create: `Triangulum/Features/Almanac/TideChartView.swift`
- Create: `Triangulum/Features/Almanac/TideStationSheet.swift`
- Create: `TriangulumTests/AlmanacTidesRenderingTests.swift`

**Interfaces:**
- Consumes: `TideLoadSnapshot`, `AlmanacViewModel`, Cel design system, Swift Charts.
- Produces: every supported Tides loading/error/content state and manual station override UI.

- [ ] **Step 1: Write failing rendering tests**

Cover loaded Vancouver, unsupported region, no station inside 250 km, stale cache with warning, provider failure without cache, and non-today first-event behavior. Assert exact accessible text for next/first tide, high/low, chart summary, station, distance, datum, attribution, update state, and planning-only warning.

- [ ] **Step 2: Add daily projection and stable state views**

```swift
extension TideWeek {
    func samples(on date: LocalDate) -> [TideSample]
    func events(on date: LocalDate) -> [TideEvent]
    func nextEvent(after instant: Date) -> TideEvent?
}
```

Filter with `LocalDate(instant, in: station.timeZone!)`. Map every `TidePhase` and `TideLoadError` to explicit copy and Retry. Today shows next event/countdown; another day shows the first event without countdown; after today's final event the summary may show tomorrow explicitly.

- [ ] **Step 3: Implement native Swift Charts**

Use one `Chart` with `LineMark` for hourly samples, labelled `PointMark` values for exact highs/lows, and a today-only `RuleMark`. Format the horizontal axis in station time. Add an accessibility summary containing daily range and event order, while repeating exact values in chronological rows. Add no scrubbing, zoom, interpolation, or chart package.

- [ ] **Step 4: Add station details, override, and refresh**

Show station name, distance, station zone when different, datum, provider, fetched time, source state/warning, and planning-only warning. `TideStationSheet` lists `nearbyStations` plus **Use Nearest Station**. Add `.refreshable { await viewModel.loadTides(forceRefresh: true) }` around Tides only.

- [ ] **Step 5: Verify and commit**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/AlmanacTidesRenderingTests
git add Triangulum/Features/Almanac/AlmanacTidesView.swift \
  Triangulum/Features/Almanac/TideChartView.swift \
  Triangulum/Features/Almanac/TideStationSheet.swift \
  TriangulumTests/AlmanacTidesRenderingTests.swift
git commit -m 'feat: add Almanac tide prediction display'
```

---

### Task 14: Wire the tab, remove duplicate Solar UI, add deterministic UI fixtures, and run all gates

**Files:**
- Modify: `Triangulum/Views/ContentView.swift`
- Modify: `Triangulum/Views/FieldHubView.swift`
- Modify: `Triangulum/Utilities/Log.swift`
- Delete: `Triangulum/Views/SolarEventsView.swift`
- Modify: `Triangulum/Features/Almanac/AlmanacDependencies.swift`
- Create: `Triangulum/Features/Almanac/AlmanacFixtureTideService.swift`
- Modify: `TriangulumUITests/BaseUITest.swift`
- Modify: `TriangulumUITests/TriangulumUITests.swift`

**Interfaces:**
- Consumes: complete Almanac feature and test seams.
- Produces: five-tab shipping shell, deterministic UI smoke coverage, and removal of duplicate Solar navigation.

- [ ] **Step 1: Make the shell and smoke UI tests fail**

Rename the shell test to expect exactly:

```swift
["Live", "Field", "Almanac", "Footprint", "Settings"]
```

Update the helper:

```swift
func makeApp(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing")
    app.launchArguments.append(contentsOf: additionalArguments)
    return app
}
```

Add `testAlmanacDisplaysSunAndTideFixture`, launched with `-almanac-fixture`. It opens Almanac, verifies Vancouver/Sunrise/Sunset, switches to Tides, and verifies next tide, chart accessibility label, Station Vancouver, Chart Datum, and Canadian Hydrographic Service.

- [ ] **Step 2: Add `.almanac` and the fifth tab**

Keep `ProductTab` in `FieldHubView.swift` and add:

```swift
case almanac
// title: "Almanac"
// symbol: "calendar"
```

In `ContentView`, create `AlmanacDependencies` once in `init()`, selecting `.uiTestFixture()` only when both `-ui-testing` and `-almanac-fixture` are present; otherwise `.live()`. Add the Almanac `NavigationStack` between Field and Footprint. Remove the Solar `ConsoleTile`, delete `SolarEventsView.swift`, and add `Logger.almanac`.

- [ ] **Step 3: Add deterministic fixture dependencies**

`AlmanacFixtureTideService` returns a Vancouver week for 2026-09-01 through 2026-09-07 with at least 23 hourly samples, two highs, two lows, Chart Datum, and CHS attribution. Add a fixture location resolver that never calls MapKit or Core Location.

`AlmanacDependencies.uiTestFixture()` uses fixed `2026-09-01T19:00:00Z`, clears and seeds a dedicated `UserDefaults` suite with selected Vancouver, and never constructs `URLSession.shared`.

- [ ] **Step 4: Run focused UI tests**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumUITests/TriangulumUITests/testMobileShellDisplaysFivePrimaryTabs \
  -only-testing:TriangulumUITests/TriangulumUITests/testAlmanacDisplaysSunAndTideFixture
```

Expected: both pass without permission prompts or public network requests.

- [ ] **Step 5: Run all quality gates**

```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumTests

xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination "$TRIANGULUM_DESTINATION" -parallel-testing-enabled NO \
  -only-testing:TriangulumUITests

xcodebuild -project Triangulum.xcodeproj -scheme Triangulum \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

swiftlint
git diff --check
git diff --stat main...HEAD
```

Expected: all unit/UI tests pass (launch performance may skip), the generic iOS build succeeds, SwiftLint reports no errors, and `git diff --check` prints nothing.

- [ ] **Step 6: Commit final wiring and complete the review checklist**

```bash
git add Triangulum/Views/ContentView.swift \
  Triangulum/Views/FieldHubView.swift \
  Triangulum/Utilities/Log.swift \
  Triangulum/Features/Almanac/AlmanacDependencies.swift \
  Triangulum/Features/Almanac/AlmanacFixtureTideService.swift \
  TriangulumUITests/BaseUITest.swift \
  TriangulumUITests/TriangulumUITests.swift
git rm Triangulum/Views/SolarEventsView.swift
git commit -m 'feat: ship Almanac sun and tide tab'
```

Confirm before marking the implementation PR ready:

```text
[ ] Four source contracts and canonical fixtures are recorded.
[ ] Automated provider tests perform no live network requests.
[ ] Sun uses destination-local dates and works outside tide coverage.
[ ] Tides use station-local instants, metres, datum, attribution, and warning copy.
[ ] Station selection enforces 250 km / eight-result limits and override reset rules.
[ ] Fresh/stale cache, forced refresh, and partial-response protection pass.
[ ] NOAA subordinate and non-U.S. catalogue records are excluded.
[ ] JMA/HKO New Year ranges combine two annual sources.
[ ] The duplicate Solar tile and screen are gone.
[ ] The tab bar contains exactly Live, Field, Almanac, Footprint, Settings.
[ ] No package, backend, SwiftData migration, reachability monitor, or background scheduler was added.
```

## Execution Notes

- Execute tasks in order; later tasks depend on earlier exact types.
- Keep every task commit buildable or focused-test green; do not split this ticket across PRs.
- When an official source format changes, update its contract, canonical fixture, and parser test together before changing production parsing.
- A provider that fails Task 1 is visibly disabled in this same implementation PR; do not add substitute infrastructure.
