# Almanac tide source contracts

Verified live on **2026-09-01** by executing every recorded capture URL and
checking in only the named slim fixtures under
`TriangulumTests/Fixtures/Almanac/`. All four providers satisfy the
source-contract gate (both prediction forms captured, non-empty, direct iOS
use permitted) and all four are listed in `TideProvider.enabled`.

---

## Canada — Canadian Hydrographic Service (CHS) IWLS

**Runtime catalogue URL**

`GET https://api-iwls.dfo-mpo.gc.ca/api/v1/stations`
Returns a JSON array of station objects. Vancouver is `code == "07735"`,
`id == "5cebf1de3d0f4a073c4bb943"`. Each station's `timeSeries` array declares
which series it supports (`wlp` = water level predictions, `wlp-hilo` = high
and low tide predictions).

The same API is documented (Swagger UI) at
`https://api-sine.dfo-mpo.gc.ca/swagger-ui/index.html`; the machine-readable
OpenAPI spec is `https://api-sine.dfo-mpo.gc.ca/v3/api-docs/v1`. The official
service page listing both hosts is
`https://www.tides.gc.ca/en/web-services-offered-canadian-hydrographic-service`.

**Runtime prediction URL form**

Hourly (data series `wlp`, 60-minute resolution):

```
GET https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/{stationId}/data
    ?time-series-code=wlp&from={ISO8601Z}&to={ISO8601Z}&resolution=SIXTY_MINUTES
```

Exact highs/lows (data series `wlp-hilo`, no resolution parameter):

```
GET https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/{stationId}/data
    ?time-series-code=wlp-hilo&from={ISO8601Z}&to={ISO8601Z}
```

Both return a JSON array of `{eventDate, qcFlagCode, reviewed, timeSeriesId, value}`
objects; `value` is a height in metres at `eventDate` (ISO 8601 UTC). Note the
IWLS `/tide-tables` endpoints only expose the tide-table **hierarchy**
(VOLUME → AREA → SUB_AREA metadata, e.g. Burrard Inlet id
`5da0907154c1370c6037fd58`); the actual high/low prediction rows are the
`wlp-hilo` data series above.

**Direct iOS-use status:** Yes. Free of charge under the CHS website licence
agreement (`https://www.tides.gc.ca/en/licence-agreement?wbdisable=true`),
which the user accepts by using the data. No key or registration is required
for these GET endpoints; plain `URLSession` requests verified working.

**Required attribution / derivative-product notice:** Data is CHS copyright
(His Majesty the King in Right of Canada). The licence forbids use for
navigation and forbids derivative products made for sale or profit. Any
derivative product (this app) must carry, in a prominent location:

> This product is not to be used for navigation. This product was made by or
> for Triangulum and contains intellectual property (Data) of the Canadian
> Hydrographic Service of the Department of Fisheries and Oceans. The
> copyrights in the Data are and remain the property of His Majesty the King
> in Right of Canada and shall not be sold, licensed, leased, assigned or
> given to a third party. The incorporation of the Data in this product does
> not constitute an endorsement or an approval of this product by the Canadian
> Hydrographic Service, the Department of Fisheries and Oceans or His Majesty
> the King in Right of Canada.

**Datum behavior:** Predictions are returned relative to the station's
official chart datum. Station metadata
(`/api/v1/stations/{stationId}/metadata`) exposes conversions to CGVD28
(offset −3.0 m for Vancouver) and CGVD2013 (offset −2.88 m). The app displays
values as-is (chart datum) and never converts datums.

**Request limits:** The `time-series-definitions` endpoint reports
`allowedPeriodInDays: 7` for `wlp` (up to 31 days when combined with
`resolution=SIXTY_MINUTES`) and `allowedPeriodInDays: 366` for `wlp-hilo`.
Data windows must not exceed the allowed period per request. No published
per-client rate quota; poll politely, cache aggressively (30-day catalogue
freshness per plan).

**Fixture capture date:** 2026-09-01

**Exact fixture capture URLs**

- `CHS/stations-vancouver.json` (Vancouver row, slimmed with
  `jq '[.[] | select(.code == "07735")]'`, 1026 bytes):
  `https://api-iwls.dfo-mpo.gc.ca/api/v1/stations`
- `CHS/vancouver-hourly.json` (2026-03-01 00:00Z – 2026-03-02 00:00Z, 24 rows):
  `https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/5cebf1de3d0f4a073c4bb943/data?time-series-code=wlp&from=2026-03-01T00:00:00Z&to=2026-03-02T00:00:00Z&resolution=SIXTY_MINUTES`
- `CHS/vancouver-hilo.json` (same window, 4 high/low events):
  `https://api-iwls.dfo-mpo.gc.ca/api/v1/stations/5cebf1de3d0f4a073c4bb943/data?time-series-code=wlp-hilo&from=2026-03-01T00:00:00Z&to=2026-03-02T00:00:00Z`

---

## United States — NOAA CO-OPS

**Runtime catalogue URL**

`GET https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions`
Returns `{count, stations:[…]}` with 3499 tide-prediction stations
(verified 2026-09-01). Reference/harmonic stations have `type == "R"`
(San Francisco is `id == "9414290"`, `"SAN FRANCISCO (Golden Gate)"`);
subordinate stations have `type == "S"` and carry `reference_id` +
`tidepredoffsets`. Metadata API home:
`https://api.tidesandcurrents.noaa.gov/mdapi/prod/`.

**Runtime prediction URL form**

Hourly:

```
GET https://api.tidesandcurrents.noaa.gov/api/prod/datagetter
    ?product=predictions&application=Triangulum&station={id}
    &begin_date={YYYYMMDD}&end_date={YYYYMMDD}&datum=MLLW
    &time_zone=gmt&units=metric&format=json&interval=h
```

Exact highs/lows: identical with `interval=hilo`.

Both return `{ "predictions": [ {"t": "YYYY-MM-DD HH:MM", "v": "…"} … ] }`;
`interval=hilo` rows additionally carry `"type": "H" | "L"`. Times are GMT per
`time_zone=gmt` (unambiguous across DST); heights are metres. Data API
documentation: `https://api.tidesandcurrents.noaa.gov/api/dev`.

**Direct iOS-use status:** Yes. U.S. federal government data, public domain,
free, no key required (the `application=` parameter identifies the app).
Plain `URLSession` requests verified working.

**Required attribution / derivative-product notice:** Acknowledge
"NOAA CO-OPS" as the source. NOAA asks applications to identify themselves via
`application=` on every request. Display the planning-only warning
("Predictions are for planning only, not navigation.") per plan.

**Datum behavior:** Requested with `datum=MLLW`; values are metres above mean
lower low water. The app preserves MLLW as-is and never converts datums.

**Request limits:** Predictions with `interval=h` or `interval=hilo` are
limited to 1 year of data per request (documented under "Data Length
Limitations" at `https://api.tidesandcurrents.noaa.gov/api/dev`). No published
rate quota; poll politely, cache aggressively (30-day catalogue freshness).

**Fixture capture date:** 2026-09-01

**Exact fixture capture URLs**

- `NOAA/stations-selection.json` (full catalogue → San Francisco reference row
  + first subordinate row via the plan's `python3` filter, 1201 bytes):
  `https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions`
- `NOAA/san-francisco-hourly.json` (2026-03-01 → 2026-03-02, 25 rows):
  `https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&application=Triangulum&station=9414290&begin_date=20260301&end_date=20260302&datum=MLLW&time_zone=gmt&units=metric&format=json&interval=h`
- `NOAA/san-francisco-hilo.json` (2026-03-01 → 2026-03-02, 7 events):
  `https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&application=Triangulum&station=9414290&begin_date=20260301&end_date=20260302&datum=MLLW&time_zone=gmt&units=metric&format=json&interval=hilo`

---

## Japan — Japan Meteorological Agency (JMA)

**Runtime catalogue URL or static-catalogue source**

Static (compiled Swift) catalogue, per plan — no runtime catalogue fetch.
Station metadata comes from the official annual station audit table page
「潮位表掲載地点一覧表」: `https://ds.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/station2026.php`
(Tokyo row: station number 59, symbol `TK`, 東京, 35°39′N 139°46′E, tide-table
datum zero point 120.0 cm below mean sea level). Format documentation:
`https://ds.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/readme.html`.

**Runtime prediction URL form**

Annual fixed-width text file per station and year:

```
GET https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/{YEAR}/{STATION}.txt
```

One line per day, exactly **136 bytes**, LF line endings:

- columns 1–72: hourly predicted heights, 3 digits × 24 hours (cm)
- columns 73–78: year, month, day — 2 digits × 3
- columns 79–80: station symbol (`TK`)
- columns 81–108: (high time 4 digits, height 3 digits) × 4
- columns 109–136: (low time 4 digits, height 3 digits) × 4
- a missing high/low is encoded as time `9999`, height `999`

So one annual file supplies **both** the hourly series and the exact high/low
events. Times are Japan Standard Time (Asia/Tokyo, no DST); heights are cm
relative to the tide-table datum (JMA "潮位表基準面").

**Direct iOS-use status:** Yes. JMA site content is governed by the Government
of Japan Standard Public Data Utilization Terms (公共データ利用規約 1.0)
(`https://www.jma.go.jp/jma/kishou/info/coment.html`): free use including
commercial use, subject to the terms' conditions.

**Required attribution / derivative-product notice:** Must cite the source,
e.g. 「出典：気象庁ホームページ（当該ページのURL）」 ("Source: JMA website,
URL"), and when editing/processing content, additionally state that it was
edited/processed and must not be presented as if created by the government.
Tide-table predictions are for planning reference; display the planning-only
warning per plan.

**Datum behavior:** Values are relative to the JMA tide-table datum (the
「潮位表基準面」 zero point, cm below mean sea level, 120.0 cm for Tokyo).
Preserved as-is; never converted.

**Request limits:** One file per station per year (a range crossing New Year
reads two files). No documented rate quota; cache validated files locally
(immutable per station/year).

**Fixture capture date:** 2026-09-01

**Exact fixture capture URLs**

- `JMA/tokyo-station.txt` (official `TK` audit row, tab-separated cells):
  `https://ds.data.jma.go.jp/gmd/kaiyou/db/tide/suisan/station2026.php`
- `JMA/tokyo-2026.txt` (complete 2026 Tokyo annual file, 365 records × 136 bytes):
  `https://www.data.jma.go.jp/kaiyou/data/db/tide/suisan/txt/2026/TK.txt`

---

## Hong Kong — Hong Kong Observatory (HKO)

**Runtime catalogue URL or static-catalogue source**

Static (compiled Swift) catalogue, per plan — no runtime catalogue fetch.
Station list comes from the intersection of the two dataset pages (both list
station codes; Tai Po Kau is `TPK`):

- HHOT dataset: `https://data.gov.hk/en-data/dataset/hk-hko-rss-hourly-heights-of-tides`
- HLT dataset: `https://data.gov.hk/en-data/dataset/hk-hko-rss-times-and-heights-of-high-and-low-tides`

**Runtime prediction URL form**

Annual CSV per station, year, and data type:

```
GET https://data.weather.gov.hk/weatherAPI/opendata/opendata.php
    ?dataType=HHOT&station={CODE}&year={YEAR}&rformat=csv   (hourly)
GET https://data.weather.gov.hk/weatherAPI/opendata/opendata.php
    ?dataType=HLT&station={CODE}&year={YEAR}&rformat=csv    (high/low)
```

HHOT header: `MM,DD,01,02,…,24` (UTF-8 BOM), one row per day with 24 hourly
heights in metres. HLT header:
`Month,Date,Time,Height(m),Time,Height(m),Time,Height(m),Time,Height(m)`
(UTF-8 BOM), one row per day with up to four high/low `Time,Height(m)` pairs;
fewer events leave trailing fields empty. Times are Hong Kong Time
(Asia/Hong_Kong, no DST); heights are metres above chart datum. Both files
must be parsed tolerating the BOM, CRLF, and quoted fields per plan.

**Direct iOS-use status:** Yes. DATA.GOV.HK Terms of Use
(`https://data.gov.hk/en/terms-and-conditions`) allow free browsing,
downloading, distribution, reproduction of the Data for commercial and
non-commercial purposes, subject to the conditions below.

**Required attribution / derivative-product notice:** Must clearly identify
the source, acknowledge the Government of the HKSAR and the Hong Kong
Observatory's ownership of the IP rights in the Data and all copies, and give
proper attribution to the Government, the Relevant Organisations, and
DATA.GOV.HK. Display the planning-only warning per plan.

**Datum behavior:** Heights are metres above chart datum. Preserved as-is;
never converted.

**Request limits:** One pair of files per station per year (a range crossing
New Year may read two years). No documented rate quota; cache validated files
locally (immutable per station/year/source-kind).

**Fixture capture date:** 2026-09-01

**Exact fixture capture URLs**

- `HKO/tai-po-kau-2026-hourly.csv` (header + first 10 January rows):
  `https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=HHOT&station=TPK&year=2026&rformat=csv`
- `HKO/tai-po-kau-2026-hilo.csv` (header + first 16 January rows, includes
  4-, 3-, and 2-event days):
  `https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=HLT&station=TPK&year=2026&rformat=csv`
