//
//  TideService.swift
//

import CoreLocation
import Foundation

/// Everything the Tides view needs about one resolved station: where it sits
/// in the coverage model, which station won (automatic or overridden), the
/// offered alternatives, and the station's local zone.
struct TideStationContext {
    let coverage: TideCoverage
    let selected: TideStation
    let nearbyStations: [TideStation]
    let distanceMetres: Double
    let timeZone: TimeZone
}

/// One cached day plus its freshness flag, so the view model can keep stale
/// predictions on screen while refreshing.
struct TideDaySnapshot {
    let day: TideDay
    let isStale: Bool
}

/// The tide surface consumed by the Almanac view model.
protocol TideServing {
    func resolveStation(for location: AlmanacLocation, override: TideStationOverride?) async throws -> TideStationContext
    func cachedDay(station: TideStation, date: LocalDate) async throws -> TideDaySnapshot?
    func refreshRange(station: TideStation, range: LocalDateRange) async throws -> TideWeek
}

/// Orchestrates coverage, station selection, catalogue caching, time-zone
/// enrichment, and cache-first day loading across the enabled providers.
///
/// `enabledProviders` is one injected value driving both coverage resolution
/// and client dispatch — `TideProvider.enabled` is only the production
/// default, never consulted directly. There is deliberately no reachability
/// check or retry scheduler: `cachedDay` never fetches, `refreshRange` always
/// does, and the view model decides when to call each.
struct TideService: TideServing {

    private let enabledProviders: Set<TideProvider>
    private let clients: [TideProvider: any TideProviderClient]
    private let cache: TideDiskCache
    private let timeZoneResolver: any TideStationTimeZoneResolving
    private let coverageResolver: TideCoverageResolver
    private let selector = TideStationSelector()

    init(
        enabledProviders: Set<TideProvider> = TideProvider.enabled,
        clients: [TideProvider: any TideProviderClient],
        cache: TideDiskCache,
        timeZoneResolver: any TideStationTimeZoneResolving
    ) {
        self.enabledProviders = enabledProviders
        self.clients = clients
        self.cache = cache
        self.timeZoneResolver = timeZoneResolver
        self.coverageResolver = TideCoverageResolver(enabledProviders: enabledProviders)
    }

    private func client(for provider: TideProvider) throws -> any TideProviderClient {
        guard enabledProviders.contains(provider), let client = clients[provider] else {
            throw TideLoadError.providerUnavailable
        }
        return client
    }

    // MARK: - Station resolution

    func resolveStation(for location: AlmanacLocation, override: TideStationOverride?) async throws -> TideStationContext {
        let coverage = coverageResolver.coverage(for: location)
        let provider: TideProvider
        switch coverage {
        case .provider(let enabled): provider = enabled
        case .unsupportedRegion: throw TideLoadError.unsupportedRegion
        case .providerUnavailable: throw TideLoadError.providerUnavailable
        }

        let client = try self.client(for: provider)
        let stations = try await currentCatalog(provider: provider, client: client)
        let selection = selector.select(
            from: stations,
            latitude: location.latitude,
            longitude: location.longitude
        )
        guard let nearest = selection.selected else { throw TideLoadError.noStationNearby }

        // A manual override wins whenever its station is present in the
        // provider's catalogue; anchor-distance retention is the view model's
        // concern (clearing rules), not resolution's.
        let chosen: TideStation
        let nearby: [TideStation]
        if let override,
           let overridden = stations.first(where: { $0.id == override.stationID }) {
            chosen = overridden
            nearby = Array(
                ([nearest] + selection.alternatives)
                    .filter { $0.id != chosen.id }
                    .prefix(TideStationSelector.maximumAlternatives)
            )
        } else {
            chosen = nearest
            nearby = selection.alternatives
        }

        let distanceMetres = CLLocation(latitude: location.latitude, longitude: location.longitude)
            .distance(from: CLLocation(latitude: chosen.latitude, longitude: chosen.longitude))
        // Enrichment must reach everything downstream: `selected` is the
        // persisted, zone-carrying row (not the pre-enrichment copy), so
        // cached days, refreshes, and the view-model-published context all
        // agree on the station's zone.
        let (enrichedStation, timeZone) = try await stationTimeZone(for: chosen, provider: provider)

        return TideStationContext(
            coverage: coverage,
            selected: enrichedStation,
            nearbyStations: nearby,
            distanceMetres: distanceMetres,
            timeZone: timeZone
        )
    }

    /// Cached catalogue first; a stale catalogue remains usable offline while
    /// one direct refresh is attempted. A miss always refreshes (for JMA/HKO
    /// that is the compiled static list, saved so enrichment has somewhere to
    /// live). Refreshes merge previously resolved non-nil zones into matching
    /// fresh provider rows that still lack one.
    private func currentCatalog(provider: TideProvider, client: any TideProviderClient) async throws -> [TideStation] {
        if let cached = try await cache.loadCatalog(provider: provider) {
            guard cached.isStale else { return cached.stations }
            if let refreshed = try? await refreshedCatalog(provider: provider, client: client, previous: cached) {
                return refreshed
            }
            return cached.stations
        }
        return try await refreshedCatalog(provider: provider, client: client, previous: nil)
    }

    private func refreshedCatalog(
        provider: TideProvider,
        client: any TideProviderClient,
        previous: TideDiskCache.CachedCatalog?
    ) async throws -> [TideStation] {
        var stations = try await client.loadStationCatalog()
        if let previous {
            var knownZones: [String: String] = [:]
            for station in previous.stations {
                if let zone = station.timeZoneIdentifier { knownZones[station.id] = zone }
            }
            stations = stations.map { station in
                guard station.timeZoneIdentifier == nil, let zone = knownZones[station.id] else { return station }
                var merged = station
                merged.timeZoneIdentifier = zone
                return merged
            }
        }
        try await cache.saveCatalog(provider: provider, stations: stations, fetchedAt: Date())
        return stations
    }

    /// The station's zone plus the station row carrying it, resolving and
    /// persisting enrichment only when the catalogue row lacks a valid
    /// identifier. `updateCatalogTimeZone` returns the enriched row; callers
    /// dispatch downstream work with that row so a resolved zone is never
    /// lost between resolution and use.
    private func stationTimeZone(for station: TideStation, provider: TideProvider) async throws -> (station: TideStation, timeZone: TimeZone) {
        if let zone = station.timeZone {
            return (station, zone)
        }
        let identifier = try await timeZoneResolver.resolveIdentifier(for: station)
        let enriched = try await cache.updateCatalogTimeZone(provider: provider, stationID: station.id, identifier: identifier)
        guard let zone = enriched.timeZone else {
            throw TideLoadError.invalidProviderResponse
        }
        return (enriched, zone)
    }

    // MARK: - Day reads

    /// Cache-only: never fetches. Fresh or stale, a stored day is returned
    /// with its `isStale` flag; refreshing is the caller's explicit move.
    func cachedDay(station: TideStation, date: LocalDate) async throws -> TideDaySnapshot? {
        try await cache.loadDay(provider: station.provider, stationID: station.id, date: date)
            .map { TideDaySnapshot(day: $0.day, isStale: $0.isStale) }
    }

    /// Always performs the provider refresh, validates the complete-response
    /// gate (clients already return a `TideWeek` only when every source
    /// validates; this re-checks station identity, finite heights, in-range
    /// instants, and non-empty samples/events), then partitions the week into
    /// local day files in the station's zone.
    func refreshRange(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let client = try client(for: station.provider)
        // Enrich a zone-less station before dispatch: GMT-bound clients
        // (CHS/NOAA) derive their request window from the station's zone and
        // would otherwise fall back to UTC and miss the local-day range that
        // the day partition validates against.
        let (resolvedStation, timeZone) = try await stationTimeZone(for: station, provider: station.provider)
        let week = try await client.loadPredictions(station: resolvedStation, range: range)
        try Self.validateCompleteWeek(week, station: resolvedStation, range: range, in: timeZone)
        try await cache.saveCompleteRange(week, in: timeZone)
        return week
    }

    /// Complete-response gate, before any cache write: the week must belong
    /// to the requested station, its samples and events must carry finite
    /// heights and fall inside the requested local-day range, and both
    /// arrays must be non-empty. Malformed responses map to
    /// `.invalidProviderResponse`; a cleanly empty result is
    /// `.noPredictions`.
    private static func validateCompleteWeek(
        _ week: TideWeek, station: TideStation, range: LocalDateRange, in timeZone: TimeZone
    ) throws {
        guard !week.hourlySamples.isEmpty, !week.events.isEmpty else {
            throw TideLoadError.noPredictions
        }
        guard week.station.id == station.id, week.station.provider == station.provider else {
            throw TideLoadError.invalidProviderResponse
        }
        let rangeStart = try range.start.start(in: timeZone)
        let rangeEnd = try range.endInclusive.endExclusive(in: timeZone)
        let inRange: (TideSample) -> Bool = { $0.instant >= rangeStart && $0.instant < rangeEnd && $0.heightMetres.isFinite }
        let eventsInRange: (TideEvent) -> Bool = { $0.instant >= rangeStart && $0.instant < rangeEnd && $0.heightMetres.isFinite }
        guard week.hourlySamples.allSatisfy(inRange), week.events.allSatisfy(eventsInRange) else {
            throw TideLoadError.invalidProviderResponse
        }
    }
}
