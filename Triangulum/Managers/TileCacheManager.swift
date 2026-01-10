//
//  TileCacheManager.swift
//  Triangulum
//
//  Created by Rovo Dev on 5/8/2025.
//

import Foundation
import SwiftData
import UIKit
import MapKit

@MainActor
class TileCacheManager: ObservableObject {
    static let shared = TileCacheManager()

    private var modelContainer: ModelContainer?
    private let urlSession: URLSession
    private let maxCacheSize: Int = 100 * 1024 * 1024 // 100MB

    @Published var cacheSize: Int = 0
    @Published var tilesCount: Int = 0
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var initializationError: String?
    @Published var lastOperationError: String?

    /// Indicates whether the cache is available for use
    var isCacheAvailable: Bool {
        modelContainer != nil
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: configuration)

        setupModelContainer()
        updateCacheStats()
    }

    private func setupModelContainer() {
        let schema = Schema([MapTile.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            let errorMessage = "Failed to create TileCacheManager ModelContainer: \(error.localizedDescription)"
            print("❌ \(errorMessage)")
            initializationError = errorMessage
        }
    }

    // MARK: - Tile Retrieval

    func getTile(tileX: Int, tileY: Int, tileZ: Int) async -> Data? {
        guard let modelContainer = modelContainer else {
            print("⚠️ TileCacheManager: Cannot get tile - cache not initialized")
            return nil
        }

        let context = ModelContext(modelContainer)
        // let tileKey = "\(tileZ)/\(tileX)/\(tileY)"

        // Try to fetch from cache first
        let fetchDescriptor = FetchDescriptor<MapTile>(
            predicate: #Predicate<MapTile> { tile in
                tile.tileX == tileX && tile.tileY == tileY && tile.tileZ == tileZ
            }
        )

        do {
            let tiles = try context.fetch(fetchDescriptor)
            if let cachedTile = tiles.first {
                if !cachedTile.isExpired {
                    return cachedTile.data
                } else {
                    // Remove expired tile
                    context.delete(cachedTile)
                    try context.save()
                }
            }
        } catch {
            print("Error fetching cached tile: \(error)")
        }

        // Download tile if not in cache or expired
        return await downloadTile(tileX: tileX, tileY: tileY, tileZ: tileZ, context: context)
    }

    private func downloadTile(tileX: Int, tileY: Int, tileZ: Int, context: ModelContext) async -> Data? {
        let urlString = "https://tile.openstreetmap.org/\(tileZ)/\(tileX)/\(tileY).png"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await urlSession.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Save to cache
            let tile = MapTile(tileX: tileX, tileY: tileY, tileZ: tileZ, data: data, url: urlString)
            context.insert(tile)

            do {
                try context.save()
                updateCacheStats()
                await cleanupCacheIfNeeded()
            } catch {
                print("Error saving tile to cache: \(error)")
            }

            return data
        } catch {
            print("Error downloading tile: \(error)")
            return nil
        }
    }

    // MARK: - Bulk Download

    func downloadTilesForRegion(center: CLLocationCoordinate2D, radius: Double, minZoom: Int = 10, maxZoom: Int = 16) async {
        isDownloading = true
        downloadProgress = 0.0

        var tilesToDownload: [(tileX: Int, tileY: Int, tileZ: Int)] = []

        // Calculate tiles needed for the region
        for zoom in minZoom...maxZoom {
            let tiles = tilesForRegion(center: center, radius: radius, zoom: zoom)
            tilesToDownload.append(contentsOf: tiles)
        }

        let totalTiles = tilesToDownload.count
        var downloadedTiles = 0

        guard let modelContainer = modelContainer else {
            let errorMessage = "Cannot download tiles: cache not available"
            print("❌ TileCacheManager: \(errorMessage)")
            lastOperationError = errorMessage
            isDownloading = false
            return
        }

        let context = ModelContext(modelContainer)

        // Download tiles in batches to avoid overwhelming with server
        let batchSize = 5
        for batchStart in stride(from: 0, to: tilesToDownload.count, by: batchSize) {
            let batch = Array(tilesToDownload[batchStart..<min(batchStart + batchSize, tilesToDownload.count)])

            await withTaskGroup(of: Void.self) { group in
                for tile in batch {
                    group.addTask {
                        _ = await self.downloadTile(tileX: tile.tileX, tileY: tile.tileY, tileZ: tile.tileZ, context: context)
                    }
                }
            }

            downloadedTiles += batch.count
            downloadProgress = Double(downloadedTiles) / Double(totalTiles)

            // Small delay to be respectful to OSM servers
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        isDownloading = false
        downloadProgress = 1.0
        updateCacheStats()
    }

    private func tilesForRegion(center: CLLocationCoordinate2D, radius: Double, zoom: Int) -> [(tileX: Int, tileY: Int, tileZ: Int)] {
        // let tileSize = 256.0
        let earthRadius = 6378137.0

        // Convert radius from meters to degrees (approximate)
        let radiusInDegrees = radius / (earthRadius * .pi / 180.0)

        let minLat = center.latitude - radiusInDegrees
        let maxLat = center.latitude + radiusInDegrees
        let minLon = center.longitude - radiusInDegrees
        let maxLon = center.longitude + radiusInDegrees

        let minX = Int(floor((minLon + 180.0) / 360.0 * pow(2.0, Double(zoom))))
        let maxX = Int(floor((maxLon + 180.0) / 360.0 * pow(2.0, Double(zoom))))

        let minY = Int(floor((1.0 - log(tan(minLat * .pi / 180.0) + 1.0 / cos(minLat * .pi / 180.0)) / .pi) / 2.0 * pow(2.0, Double(zoom))))
        let maxY = Int(floor((1.0 - log(tan(maxLat * .pi / 180.0) + 1.0 / cos(maxLat * .pi / 180.0)) / .pi) / 2.0 * pow(2.0, Double(zoom))))

        var tiles: [(tileX: Int, tileY: Int, tileZ: Int)] = []

        for tileX in minX...maxX {
            for tileY in maxY...minY {
                tiles.append((tileX: tileX, tileY: tileY, tileZ: zoom))
            }
        }

        return tiles
    }

    // MARK: - Cache Management

    func updateCacheStats() {
        guard let modelContainer = modelContainer else { return }

        Task {
            let context = ModelContext(modelContainer)

            do {
                let fetchDescriptor = FetchDescriptor<MapTile>()
                let tiles = try context.fetch(fetchDescriptor)

                await MainActor.run {
                    self.tilesCount = tiles.count
                    self.cacheSize = tiles.reduce(0) { $0 + $1.data.count }
                }
            } catch {
                print("Error updating cache stats: \(error)")
            }
        }
    }

    func cleanupCacheIfNeeded() async {
        guard let modelContainer = modelContainer else { return }

        let context = ModelContext(modelContainer)

        do {
            // Remove expired tiles
            let expirationDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            let expiredFetchDescriptor = FetchDescriptor<MapTile>(
                predicate: #Predicate<MapTile> { tile in
                    tile.timestamp < expirationDate
                }
            )

            let expiredTiles = try context.fetch(expiredFetchDescriptor)
            for tile in expiredTiles {
                context.delete(tile)
            }

            // If still over limit, remove oldest tiles
            let allTilesFetchDescriptor = FetchDescriptor<MapTile>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )

            let allTiles = try context.fetch(allTilesFetchDescriptor)
            let currentSize = allTiles.reduce(0) { $0 + $1.data.count }

            if currentSize > maxCacheSize {
                var sizeToRemove = currentSize - maxCacheSize
                for tile in allTiles {
                    if sizeToRemove <= 0 { break }
                    sizeToRemove -= tile.data.count
                    context.delete(tile)
                }
            }

            try context.save()
            updateCacheStats()
        } catch {
            print("Error cleaning up cache: \(error)")
        }
    }

    /// Clears all cached tiles
    /// - Returns: true if cache was cleared successfully, false otherwise
    @discardableResult
    func clearCache() async -> Bool {
        guard let modelContainer = modelContainer else {
            let errorMessage = "Cannot clear cache: cache not available"
            print("❌ TileCacheManager: \(errorMessage)")
            lastOperationError = errorMessage
            return false
        }

        let context = ModelContext(modelContainer)

        do {
            let fetchDescriptor = FetchDescriptor<MapTile>()
            let tiles = try context.fetch(fetchDescriptor)

            for tile in tiles {
                context.delete(tile)
            }

            try context.save()
            updateCacheStats()
            lastOperationError = nil
            return true
        } catch {
            let errorMessage = "Error clearing cache: \(error.localizedDescription)"
            print("❌ TileCacheManager: \(errorMessage)")
            lastOperationError = errorMessage
            return false
        }
    }

    func getCacheInfo() -> (sizeInMB: Double, count: Int) {
        let sizeInMB = Double(cacheSize) / (1024 * 1024)
        return (sizeInMB: sizeInMB, count: tilesCount)
    }
}
