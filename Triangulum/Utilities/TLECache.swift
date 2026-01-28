//
//  TLECache.swift
//  Triangulum
//
//  UserDefaults-based TLE cache with 24-hour expiration
//

import Foundation

/// Cached TLE data structure for persistence
struct CachedTLEData: Codable {
    let tles: [TLE]
    let timestamp: Date

    /// Check if cache has expired (24 hours)
    var isExpired: Bool {
        let expirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
        return Date().timeIntervalSince(timestamp) > expirationInterval
    }

    /// Age of cache in hours
    var ageInHours: Double {
        Date().timeIntervalSince(timestamp) / 3600
    }
}

/// Manages TLE data caching with 24-hour expiration
class TLECache {
    private let userDefaults: UserDefaults
    private let cacheKey: String

    /// Shared instance using standard UserDefaults
    static let shared = TLECache()

    init(userDefaults: UserDefaults = .standard, cacheKey: String = "satellite_tle_cache") {
        self.userDefaults = userDefaults
        self.cacheKey = cacheKey
    }

    // MARK: - Public API

    /// Save TLE data to cache
    /// - Parameter tles: Array of TLE data to cache
    func save(_ tles: [TLE]) -> Bool {
        let cachedData = CachedTLEData(tles: tles, timestamp: Date())

        do {
            let data = try JSONEncoder().encode(cachedData)
            userDefaults.set(data, forKey: cacheKey)
            print("TLECache: Saved \(tles.count) TLEs to cache")
            return true
        } catch {
            print("TLECache: Failed to save TLEs: \(error.localizedDescription)")
            return false
        }
    }

    /// Load TLE data from cache
    /// - Returns: Cached TLE data if available and not expired, nil otherwise
    func load() -> [TLE]? {
        guard let cachedData = loadCachedData() else {
            print("TLECache: No cached data found")
            return nil
        }

        if cachedData.isExpired {
            print("TLECache: Cache expired (age: \(String(format: "%.1f", cachedData.ageInHours)) hours)")
            return nil
        }

        print("TLECache: Loaded \(cachedData.tles.count) TLEs from cache (age: \(String(format: "%.1f", cachedData.ageInHours)) hours)")
        return cachedData.tles
    }

    /// Load cached data even if expired (for offline fallback)
    /// - Returns: Cached TLE data with age info, nil if no cache exists
    func loadWithAge() -> CachedTLEData? {
        return loadCachedData()
    }

    /// Check if cache exists and is fresh
    var hasFreshCache: Bool {
        guard let cachedData = loadCachedData() else { return false }
        return !cachedData.isExpired
    }

    /// Check if cache exists (even if expired)
    var hasCache: Bool {
        loadCachedData() != nil
    }

    /// Get cache age in hours, or nil if no cache
    var cacheAgeHours: Double? {
        loadCachedData()?.ageInHours
    }

    /// Clear the cache
    func clear() {
        userDefaults.removeObject(forKey: cacheKey)
        print("TLECache: Cache cleared")
    }

    // MARK: - Private

    private func loadCachedData() -> CachedTLEData? {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(CachedTLEData.self, from: data)
        } catch {
            print("TLECache: Failed to decode cached data: \(error.localizedDescription)")
            return nil
        }
    }
}
