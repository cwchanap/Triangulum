//
//  SatelliteManager.swift
//  Triangulum
//
//  Manages satellite tracking: TLE fetching, position computation, and pass predictions
//

import Foundation
import Combine
import CoreLocation
import os

class SatelliteManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var satellites: [Satellite] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String = ""
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var nextISSPass: SatellitePass?
    @Published private(set) var tleAge: Double?  // Hours since last TLE update

    // MARK: - Dependencies

    private let locationManager: LocationManager
    private let tleCache: TLECache

    // MARK: - Timers

    private var positionUpdateTimer: Timer?
    private var tleRefreshTimer: Timer?
    private(set) var nextPassWorkItem: DispatchWorkItem?
    private var nextPassToken = UUID()
    private var tleRefreshTask: Task<Void, Never>?
    private var tleRefreshToken = UUID()
    private var updatesEnabled = true
    private var cancellables = Set<AnyCancellable>()
    private var lastNextPassUpdate: Date?
    private var lastNextPassLocation: CLLocationCoordinate2D?
    private let nextPassRefreshInterval: TimeInterval = 15 * 60
    private let nextPassLocationThresholdMeters: CLLocationDistance = 1000

    // MARK: - CelesTrak API

    private let celestrakBaseURL = "https://celestrak.org/NORAD/elements/gp.php"

    // MARK: - Initialization

    init(locationManager: LocationManager, tleCache: TLECache = .shared) {
        self.locationManager = locationManager
        self.tleCache = tleCache

        // Initialize with tracked satellites
        self.satellites = Satellite.tracked

        // Observe location changes
        locationManager.$latitude
            .combineLatest(locationManager.$longitude)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateNextPass()
            }
            .store(in: &cancellables)
    }

    deinit {
        stopUpdates()
    }

    // MARK: - Public API

    /// Start satellite tracking updates
    func startUpdates() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startUpdates()
            }
            return
        }

        Logger.satellite.info("Starting updates")

        stopUpdates()
        updatesEnabled = true

        // Load cached TLEs or fetch new ones
        loadOrFetchTLEs()

        // Update positions every 10 seconds
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updatePositions()
        }

        // Check for TLE refresh every hour
        tleRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
            self?.refreshTLEsIfNeeded()
        }

        // Immediate position update
        updatePositions()
    }

    /// Stop satellite tracking updates
    func stopUpdates() {
        Logger.satellite.info("Stopping updates")
        updatesEnabled = false
        nextPassToken = UUID()
        tleRefreshToken = UUID()
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
        tleRefreshTimer?.invalidate()
        tleRefreshTimer = nil
        tleRefreshTask?.cancel()
        tleRefreshTask = nil
        nextPassWorkItem?.cancel()
        nextPassWorkItem = nil
    }

    /// Force refresh TLE data from CelesTrak
    func forceRefreshTLEs() {
        startTLEFetch()
    }

    /// Get snapshot data for sensor capture
    func snapshotData() -> SatelliteSnapshotData {
        SatelliteSnapshotData(
            capturedAt: Date(),
            satellites: satellites.compactMap { SatellitePositionSnapshot(from: $0) },
            nextISSPass: nextISSPass
        )
    }

#if DEBUG
    func applyTLEsForTesting(_ tles: [TLE]) {
        applyTLEs(tles)
    }
#endif

    // MARK: - TLE Management

    private func loadOrFetchTLEs() {
        // Try loading from cache first
        if let cachedTLEs = tleCache.load() {
            applyTLEs(cachedTLEs)
            tleAge = tleCache.cacheAgeHours
            isAvailable = true
            isLoading = false
            errorMessage = ""
            Logger.satellite.info("Loaded \(cachedTLEs.count) TLEs from cache")
        } else if let staleTLEs = tleCache.loadWithAge() {
            // Use stale cache as fallback
            applyTLEs(staleTLEs.tles)
            tleAge = staleTLEs.ageInHours
            isAvailable = true
            errorMessage = "TLE data is \(Int(staleTLEs.ageInHours)) hours old"
            Logger.satellite.debug("Using stale TLEs (age: \(staleTLEs.ageInHours) hours)")

            // Try to refresh in background
            startTLEFetch()
        } else {
            // No cache, must fetch
            Logger.satellite.info("No cached TLEs, fetching from CelesTrak")
            startTLEFetch()
        }
    }

    private func refreshTLEsIfNeeded() {
        if !tleCache.hasFreshCache {
            Logger.satellite.debug("TLE cache expired, refreshing")
            startTLEFetch()
        }
    }

    private func startTLEFetch() {
        tleRefreshTask?.cancel()
        let token = UUID()
        tleRefreshToken = token
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.fetchTLEsFromCelestrak()
        }
        tleRefreshTask = task
        Task { [weak self] in
            _ = await task.result
            guard let self = self else { return }
            if self.tleRefreshToken == token {
                self.tleRefreshTask = nil
            }
        }
    }

    private func fetchTLEsFromCelestrak() async {
        let token = tleRefreshToken
        let shouldFetch = await MainActor.run { () -> Bool in
            guard self.tleRefreshToken == token else { return false }
            self.isLoading = true
            self.errorMessage = ""
            return true
        }
        guard shouldFetch else { return }

        // Fetch TLE for each tracked satellite
        var fetchedTLEs: [TLE] = []

        for satellite in Satellite.tracked {
            if let tle = await fetchSingleTLE(noradId: satellite.noradId, name: satellite.name) {
                fetchedTLEs.append(tle)
            }
        }

        let fetchedTLEsSnapshot = fetchedTLEs
        await MainActor.run {
            guard self.tleRefreshToken == token else { return }
            self.isLoading = false

            if fetchedTLEsSnapshot.isEmpty {
                self.errorMessage = "Failed to fetch TLE data"
                let hasExistingTLEs = self.satellites.contains { $0.tle != nil }
                self.isAvailable = hasExistingTLEs
            } else {
                let saved = self.tleCache.save(fetchedTLEsSnapshot)
                if !saved {
                    self.errorMessage = "Failed to cache TLE data"
                }
                self.applyTLEs(fetchedTLEsSnapshot)
                self.tleAge = 0
                self.isAvailable = true
                if saved {
                    self.errorMessage = ""
                }
                Logger.satellite.info("Fetched \(fetchedTLEsSnapshot.count) TLEs from CelesTrak")
            }
        }
    }

    private func fetchSingleTLE(noradId: Int, name: String) async -> TLE? {
        // CelesTrak GP API endpoint for single satellite
        let urlString = "\(celestrakBaseURL)?CATNR=\(noradId)&FORMAT=TLE"

        guard let url = URL(string: urlString) else {
            Logger.satellite.error("Invalid URL for NORAD \(noradId)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.satellite.error("Non-HTTP response fetching TLE for NORAD \(noradId)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                Logger.satellite.error("HTTP \(httpResponse.statusCode) fetching TLE for NORAD \(noradId)")
                return nil
            }

            guard let content = String(data: data, encoding: .utf8) else {
                Logger.satellite.error("Failed to decode response for NORAD \(noradId)")
                return nil
            }

            // Parse TLE from response (3 lines: name, line1, line2)
            let lines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard lines.count >= 3 else {
                Logger.satellite.error("Invalid TLE format for NORAD \(noradId)")
                return nil
            }

            let tleName = lines[0]
            let line1 = lines[1]
            let line2 = lines[2]

            guard let tle = TLE(name: tleName, line1: line1, line2: line2) else {
                Logger.satellite.error("Failed to parse TLE for NORAD \(noradId)")
                return nil
            }

            return tle

        } catch {
            Logger.satellite.error("Network error for NORAD \(noradId): \(error.localizedDescription)")
            return nil
        }
    }

    private func applyTLEs(_ tles: [TLE]) {
        var updatedSatellites = satellites
        for tle in tles {
            // Find matching satellite and update its TLE
            if let index = updatedSatellites.firstIndex(where: { satellite in
                if tle.noradId > 0 {
                    return satellite.noradId == tle.noradId
                }

                let tleName = tle.name.uppercased()
                let satelliteName = satellite.name.uppercased()
                return tleName == satelliteName ||
                    tleName.contains(satelliteName) ||
                    satelliteName.contains(tleName)
            }) {
                var updated = updatedSatellites[index]
                updated.tle = tle
                updatedSatellites[index] = updated
            }
        }

        satellites = updatedSatellites

        // Update positions immediately after applying TLEs
        updatePositions()
    }

    // MARK: - Position Updates

    private func updatePositions() {
        guard locationManager.hasValidLocation else {
            // Can still compute positions without observer location
            updatePositionsWithoutObserver()
            clearNextPassData()
            return
        }

        let observerLat = locationManager.latitude
        let observerLon = locationManager.longitude
        let now = Date()

        var updatedSatellites = satellites

        for i in 0..<updatedSatellites.count {
            guard let tle = updatedSatellites[i].tle else { continue }

            let position = SGP4Propagator.propagate(
                tle: tle,
                to: now,
                observerLat: observerLat,
                observerLon: observerLon
            )

            var updated = updatedSatellites[i]
            updated.currentPosition = position
            updatedSatellites[i] = updated
        }

        satellites = updatedSatellites

        // Update next ISS pass
        updateNextPass()
    }

    private func updatePositionsWithoutObserver() {
        let now = Date()

        var updatedSatellites = satellites

        for i in 0..<updatedSatellites.count {
            guard let tle = updatedSatellites[i].tle else { continue }

            let position = SGP4Propagator.propagate(tle: tle, to: now)
            var updated = updatedSatellites[i]
            updated.currentPosition = position
            updatedSatellites[i] = updated
        }

        satellites = updatedSatellites
    }

    private func clearNextPassData() {
        nextPassWorkItem?.cancel()
        nextPassWorkItem = nil
        nextPassToken = UUID()
        nextISSPass = nil
        lastNextPassUpdate = nil
        lastNextPassLocation = nil

        var updatedSatellites = satellites
        for index in updatedSatellites.indices {
            updatedSatellites[index].nextPass = nil
        }
        satellites = updatedSatellites
    }

    private func updateNextPass() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateNextPass()
            }
            return
        }

        guard updatesEnabled else {
            return
        }

        guard locationManager.hasValidLocation else {
            clearNextPassData()
            return
        }

        let observerLat = locationManager.latitude
        let observerLon = locationManager.longitude
        let now = Date()

        if let lastUpdate = lastNextPassUpdate,
           let lastLocation = lastNextPassLocation,
           let nextPass = nextISSPass,
           nextPass.setTime > now,
           now.timeIntervalSince(lastUpdate) < nextPassRefreshInterval {
            let currentLocation = CLLocation(latitude: observerLat, longitude: observerLon)
            let previousLocation = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
            let distance = currentLocation.distance(from: previousLocation)
            if distance < nextPassLocationThresholdMeters {
                return
            }
        }

        // Find ISS TLE
        guard let issTLE = satellites.first(where: { $0.id == "ISS" })?.tle else {
            nextISSPass = nil
            return
        }

        // Calculate next pass (this is somewhat expensive, so we do it less frequently)
        nextPassWorkItem?.cancel()

        let token = UUID()
        nextPassToken = token
        lastNextPassUpdate = now
        lastNextPassLocation = CLLocationCoordinate2D(latitude: observerLat, longitude: observerLon)

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let workItem = workItem else { return }
            guard self.nextPassToken == token else { return }

            let pass = SGP4Propagator.findNextPass(
                tle: issTLE,
                observerLat: observerLat,
                observerLon: observerLon,
                minElevation: 10.0,
                maxHours: 48.0,
                shouldCancel: { [weak self, weak workItem] in
                    workItem?.isCancelled == true || self?.nextPassToken != token
                }
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.nextPassToken == token else { return }
                self.nextISSPass = pass
                // Update ISS satellite with pass info
                if let index = self.satellites.firstIndex(where: { $0.id == "ISS" }) {
                    var updatedSatellites = self.satellites
                    var updated = updatedSatellites[index]
                    updated.nextPass = pass
                    updatedSatellites[index] = updated
                    self.satellites = updatedSatellites
                }
            }
        }

        nextPassWorkItem = workItem
        if let workItem = workItem {
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
    }
}
