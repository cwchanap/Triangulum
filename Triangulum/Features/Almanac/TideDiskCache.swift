//
//  TideDiskCache.swift
//  Triangulum
//

import Foundation

enum TideDiskCacheError: Error {
    case samplesOutsideLocalDateRange
    case eventsOutsideLocalDateRange
    case catalogNotFound
    case stationNotFoundInCatalog
}

/// On-disk payload for one cached tide day. A `schemaVersion` mismatch is a
/// clean miss — there is deliberately no migration code.
struct StoredTideDay: Codable {
    let schemaVersion: Int
    let day: TideDay
}

/// On-disk payload for one provider's station catalogue.
struct StoredTideCatalog: Codable {
    let schemaVersion: Int
    var stations: [TideStation]
    let fetchedAt: Date
}

/// Day-keyed file cache for tide predictions, catalogues, and raw annual
/// source files, following the TLE fresh→stale→refresh behavior (stale data
/// still loads, flagged with `isStale`) — but not the TLE storage class.
///
/// Layout under `rootURL` (production root is
/// `Application Support/Almanac/Tides/`):
///
///     catalogs/v1/<provider>.json
///     days/v1/<provider>/<station>/<yyyy-mm-dd>.json
///     sources/jma/<station>/<year>.txt
///     sources/hko/<station>/<year>-hourly.csv
///     sources/hko/<station>/<year>-hilo.csv
///
/// Days are keyed by local date alone, so a seven-day fetch overlaps with the
/// previous fetch's window instead of duplicating it under a range key.
actor TideDiskCache {
    static let schemaVersion = 1
    static let predictionFreshness: TimeInterval = 30 * 24 * 60 * 60
    static let catalogueFreshness: TimeInterval = 30 * 24 * 60 * 60

    struct CachedDay { let day: TideDay; let isStale: Bool }
    struct CachedCatalog { let stations: [TideStation]; let isStale: Bool }

    private let rootURL: URL
    private let now: () -> Date

    init(rootURL: URL, now: @escaping () -> Date = Date.init) {
        self.rootURL = rootURL
        self.now = now
    }

    // MARK: - Days

    func loadDay(provider: TideProvider, stationID: String, date: LocalDate) throws -> CachedDay? {
        guard let data = try? Data(contentsOf: dayURL(provider: provider, stationID: stationID, date: date)),
              let stored = try? JSONDecoder().decode(StoredTideDay.self, from: data),
              stored.schemaVersion == Self.schemaVersion else {
            return nil // missing, corrupt, or schema-mismatched: a clean miss
        }
        let isStale = now().timeIntervalSince(stored.day.fetchedAt) > Self.predictionFreshness
        return CachedDay(day: stored.day, isStale: isStale)
    }

    /// Partitions a **complete** `TideWeek` into destination-local days and
    /// replaces each day file. The week is validated and every day encoded in
    /// memory before the first write, so a bad or incomplete response never
    /// leaves a half-written cache. The caller (service layer) must never
    /// invoke this with a partial hourly/high-low response.
    func saveCompleteRange(_ week: TideWeek, in timeZone: TimeZone) throws {
        let dates = try week.localDateRange.dates(in: timeZone)
        let rangeStart = try week.localDateRange.start.start(in: timeZone)
        let rangeEnd = try week.localDateRange.endInclusive.endExclusive(in: timeZone)
        guard week.hourlySamples.allSatisfy({ $0.instant >= rangeStart && $0.instant < rangeEnd }) else {
            throw TideDiskCacheError.samplesOutsideLocalDateRange
        }
        guard week.events.allSatisfy({ $0.instant >= rangeStart && $0.instant < rangeEnd }) else {
            throw TideDiskCacheError.eventsOutsideLocalDateRange
        }

        var encoded: [(url: URL, data: Data)] = []
        for date in dates {
            let dayStart = try date.start(in: timeZone)
            let dayEnd = try date.endExclusive(in: timeZone)
            let day = TideDay(
                station: week.station,
                localDate: date,
                hourlySamples: week.hourlySamples.filter { $0.instant >= dayStart && $0.instant < dayEnd },
                events: week.events.filter { $0.instant >= dayStart && $0.instant < dayEnd },
                fetchedAt: week.fetchedAt,
                sourceAttribution: week.sourceAttribution
            )
            let data = try JSONEncoder().encode(StoredTideDay(schemaVersion: Self.schemaVersion, day: day))
            encoded.append((dayURL(provider: week.station.provider, stationID: week.station.id, date: date), data))
        }
        for entry in encoded {
            try writeAtomically(entry.data, to: entry.url)
        }
    }

    // MARK: - Catalogue

    func loadCatalog(provider: TideProvider) throws -> CachedCatalog? {
        guard let data = try? Data(contentsOf: catalogURL(provider: provider)),
              let stored = try? JSONDecoder().decode(StoredTideCatalog.self, from: data),
              stored.schemaVersion == Self.schemaVersion else {
            return nil
        }
        let isStale = now().timeIntervalSince(stored.fetchedAt) > Self.catalogueFreshness
        return CachedCatalog(stations: stored.stations, isStale: isStale)
    }

    func saveCatalog(provider: TideProvider, stations: [TideStation], fetchedAt: Date) throws {
        let stored = StoredTideCatalog(schemaVersion: Self.schemaVersion, stations: stations, fetchedAt: fetchedAt)
        try writeAtomically(try JSONEncoder().encode(stored), to: catalogURL(provider: provider))
    }

    /// Writes a station's resolved time zone back into the cached catalogue
    /// (some catalogues omit it) and returns the enriched station. The
    /// original `fetchedAt` is preserved so enrichment never refreshes
    /// freshness.
    func updateCatalogTimeZone(provider: TideProvider, stationID: String, identifier: String) throws -> TideStation {
        let url = catalogURL(provider: provider)
        guard let data = try? Data(contentsOf: url),
              var stored = try? JSONDecoder().decode(StoredTideCatalog.self, from: data),
              stored.schemaVersion == Self.schemaVersion else {
            throw TideDiskCacheError.catalogNotFound
        }
        guard let index = stored.stations.firstIndex(where: { $0.id == stationID }) else {
            throw TideDiskCacheError.stationNotFoundInCatalog
        }
        stored.stations[index].timeZoneIdentifier = identifier
        try writeAtomically(try JSONEncoder().encode(stored), to: url)
        return stored.stations[index]
    }

    // MARK: - Annual source files

    /// Raw annual source bytes for one station/year/kind. These files are
    /// immutable once saved, so a miss is simply "not fetched this year yet".
    func loadSource(provider: TideProvider, stationID: String, year: Int, kind: TideSourceKind) throws -> Data? {
        try? Data(contentsOf: sourceURL(provider: provider, stationID: stationID, year: year, kind: kind))
    }

    func saveSource(_ data: Data, provider: TideProvider, stationID: String, year: Int, kind: TideSourceKind) throws {
        try writeAtomically(data, to: sourceURL(provider: provider, stationID: stationID, year: year, kind: kind))
    }

    // MARK: - Paths

    private func dayURL(provider: TideProvider, stationID: String, date: LocalDate) -> URL {
        rootURL
            .appendingPathComponent("days/v1/\(provider.rawValue)/\(stationID)", isDirectory: true)
            .appendingPathComponent("\(dateKey(date)).json")
    }

    private func dateKey(_ date: LocalDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    private func catalogURL(provider: TideProvider) -> URL {
        rootURL.appendingPathComponent("catalogs/v1/\(provider.rawValue).json", isDirectory: false)
    }

    private func sourceURL(provider: TideProvider, stationID: String, year: Int, kind: TideSourceKind) -> URL {
        let directory: String
        switch provider {
        case .japanJMA: directory = "jma"
        case .hongKongHKO: directory = "hko"
        case .canadaCHS: directory = "chs"
        case .unitedStatesNOAA: directory = "noaa"
        }
        let fileName: String
        switch kind {
        case .annual: fileName = "\(year).txt"
        case .hourly: fileName = "\(year)-hourly.csv"
        case .hilo: fileName = "\(year)-hilo.csv"
        }
        return rootURL.appendingPathComponent("sources/\(directory)/\(stationID)/\(fileName)", isDirectory: false)
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
