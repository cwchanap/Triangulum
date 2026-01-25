//
//  SatelliteManager.swift
//  Triangulum
//
//  Manages satellite tracking: TLE fetching, position computation, and pass predictions
//

import Foundation
import Combine

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
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CelesTrak API

    private let celestrakBaseURL = "https://celestrak.org/NORAD/elements/gp.php"

    // MARK: - Initialization

    init(locationManager: LocationManager, tleCache: TLECache = .shared) {
        self.locationManager = locationManager
        self.tleCache = tleCache

        // Initialize with tracked satellites
        self.satellites = Satellite.tracked

        // Observe location changes
        locationManager.objectWillChange
            .sink { [weak self] _ in
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
        print("SatelliteManager: Starting updates")

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
        print("SatelliteManager: Stopping updates")
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
        tleRefreshTimer?.invalidate()
        tleRefreshTimer = nil
    }

    /// Force refresh TLE data from CelesTrak
    func forceRefreshTLEs() {
        Task {
            await fetchTLEsFromCelestrak()
        }
    }

    /// Get snapshot data for sensor capture
    func snapshotData() -> SatelliteSnapshotData {
        SatelliteSnapshotData(
            capturedAt: Date(),
            satellites: satellites.map { SatellitePositionSnapshot(from: $0) },
            nextISSPass: nextISSPass
        )
    }

    // MARK: - TLE Management

    private func loadOrFetchTLEs() {
        // Try loading from cache first
        if let cachedTLEs = tleCache.load() {
            applyTLEs(cachedTLEs)
            tleAge = tleCache.cacheAgeHours
            isAvailable = true
            print("SatelliteManager: Loaded \(cachedTLEs.count) TLEs from cache")
        } else if let staleTLEs = tleCache.loadWithAge() {
            // Use stale cache as fallback
            applyTLEs(staleTLEs.tles)
            tleAge = staleTLEs.ageInHours
            isAvailable = true
            errorMessage = "TLE data is \(Int(staleTLEs.ageInHours)) hours old"
            print("SatelliteManager: Using stale TLEs (age: \(staleTLEs.ageInHours) hours)")

            // Try to refresh in background
            Task {
                await fetchTLEsFromCelestrak()
            }
        } else {
            // No cache, must fetch
            print("SatelliteManager: No cached TLEs, fetching from CelesTrak")
            Task {
                await fetchTLEsFromCelestrak()
            }
        }
    }

    private func refreshTLEsIfNeeded() {
        if !tleCache.hasFreshCache {
            print("SatelliteManager: TLE cache expired, refreshing")
            Task {
                await fetchTLEsFromCelestrak()
            }
        }
    }

    private func fetchTLEsFromCelestrak() async {
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }

        // Fetch TLE for each tracked satellite
        var fetchedTLEs: [TLE] = []

        for satellite in Satellite.tracked {
            if let tle = await fetchSingleTLE(noradId: satellite.noradId, name: satellite.name) {
                fetchedTLEs.append(tle)
            }
        }

        await MainActor.run {
            isLoading = false

            if fetchedTLEs.isEmpty {
                errorMessage = "Failed to fetch TLE data"
                isAvailable = false
            } else {
                tleCache.save(fetchedTLEs)
                applyTLEs(fetchedTLEs)
                tleAge = 0
                isAvailable = true
                errorMessage = ""
                print("SatelliteManager: Fetched \(fetchedTLEs.count) TLEs from CelesTrak")
            }
        }
    }

    private func fetchSingleTLE(noradId: Int, name: String) async -> TLE? {
        // CelesTrak GP API endpoint for single satellite
        let urlString = "\(celestrakBaseURL)?CATNR=\(noradId)&FORMAT=TLE"

        guard let url = URL(string: urlString) else {
            print("SatelliteManager: Invalid URL for NORAD \(noradId)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("SatelliteManager: HTTP error for NORAD \(noradId)")
                return nil
            }

            guard let content = String(data: data, encoding: .utf8) else {
                print("SatelliteManager: Failed to decode response for NORAD \(noradId)")
                return nil
            }

            // Parse TLE from response (3 lines: name, line1, line2)
            let lines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard lines.count >= 3 else {
                print("SatelliteManager: Invalid TLE format for NORAD \(noradId)")
                return nil
            }

            let tleName = lines[0]
            let line1 = lines[1]
            let line2 = lines[2]

            guard let tle = TLE(name: tleName, line1: line1, line2: line2) else {
                print("SatelliteManager: Failed to parse TLE for NORAD \(noradId)")
                return nil
            }

            return tle

        } catch {
            print("SatelliteManager: Network error for NORAD \(noradId): \(error.localizedDescription)")
            return nil
        }
    }

    private func applyTLEs(_ tles: [TLE]) {
        for tle in tles {
            // Find matching satellite and update its TLE
            if let index = satellites.firstIndex(where: {
                tle.name.uppercased().contains($0.id) ||
                $0.name.uppercased().contains(tle.name.prefix(3).uppercased())
            }) {
                satellites[index].tle = tle
            }
        }

        // Update positions immediately after applying TLEs
        updatePositions()
    }

    // MARK: - Position Updates

    private func updatePositions() {
        guard locationManager.isAvailable else {
            // Can still compute positions without observer location
            updatePositionsWithoutObserver()
            return
        }

        let observerLat = locationManager.latitude
        let observerLon = locationManager.longitude
        let now = Date()

        for i in 0..<satellites.count {
            guard let tle = satellites[i].tle else { continue }

            let position = SGP4Propagator.propagate(
                tle: tle,
                to: now,
                observerLat: observerLat,
                observerLon: observerLon
            )

            satellites[i].currentPosition = position
        }

        // Update next ISS pass
        updateNextPass()
    }

    private func updatePositionsWithoutObserver() {
        let now = Date()

        for i in 0..<satellites.count {
            guard let tle = satellites[i].tle else { continue }

            let position = SGP4Propagator.propagate(tle: tle, to: now)
            satellites[i].currentPosition = position
        }
    }

    private func updateNextPass() {
        guard locationManager.isAvailable,
              locationManager.latitude != 0 || locationManager.longitude != 0 else {
            nextISSPass = nil
            return
        }

        // Find ISS TLE
        guard let issTLE = satellites.first(where: { $0.id == "ISS" })?.tle else {
            nextISSPass = nil
            return
        }

        // Calculate next pass (this is somewhat expensive, so we do it less frequently)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let pass = SGP4Propagator.findNextPass(
                tle: issTLE,
                observerLat: self.locationManager.latitude,
                observerLon: self.locationManager.longitude,
                minElevation: 10.0,
                maxHours: 48.0
            )

            DispatchQueue.main.async {
                self.nextISSPass = pass
                // Update ISS satellite with pass info
                if let index = self.satellites.firstIndex(where: { $0.id == "ISS" }) {
                    self.satellites[index].nextPass = pass
                }
            }
        }
    }
}
