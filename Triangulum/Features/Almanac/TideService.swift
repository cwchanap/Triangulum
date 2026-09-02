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
        let timeZone = try await stationTimeZone(for: chosen, provider: provider)

        return TideStationContext(
            coverage: coverage,
            selected: chosen,
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

    /// The station's zone, resolving and persisting enrichment only when the
    /// catalogue row lacks a valid identifier.
    private func stationTimeZone(for station: TideStation, provider: TideProvider) async throws -> TimeZone {
        if let zone = station.timeZone {
            return zone
        }
        let identifier = try await timeZoneResolver.resolveIdentifier(for: station)
        let enriched = try await cache.updateCatalogTimeZone(provider: provider, stationID: station.id, identifier: identifier)
        guard let zone = enriched.timeZone else {
            throw TideLoadError.invalidProviderResponse
        }
        return zone
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
    /// validates; this re-checks non-empty samples and events), then
    /// partitions the week into local day files in the station's zone.
    func refreshRange(station: TideStation, range: LocalDateRange) async throws -> TideWeek {
        let client = try client(for: station.provider)
        let timeZone = try await stationTimeZone(for: station, provider: station.provider)
        let week = try await client.loadPredictions(station: station, range: range)
        guard !week.hourlySamples.isEmpty, !week.events.isEmpty else {
            throw TideLoadError.noPredictions
        }
        try await cache.saveCompleteRange(week, in: timeZone)
        return week
    }
}
