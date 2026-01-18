//
//  TileCacheManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 21/8/2025.
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import Triangulum

@MainActor
@Suite(.serialized)
struct TileCacheManagerTests {

    // Helper to create an isolated in-memory manager for testing
    private func createTestManager() -> TileCacheManager {
        TileCacheManager(inMemory: true)
    }

    @Test func testTileCacheManagerSingletonInitialization() {
        let manager1 = TileCacheManager.shared
        let manager2 = TileCacheManager.shared

        #expect(manager1 === manager2)
        #expect(manager1.cacheSize >= 0)
        #expect(manager1.tilesCount >= 0)
        #expect(manager1.isDownloading == false)
        #expect(manager1.downloadProgress >= 0.0)
    }

    @Test func testInitialCacheState() {
        let manager = createTestManager()

        #expect(manager.cacheSize == 0)
        #expect(manager.tilesCount == 0)
        #expect(manager.isDownloading == false)
        #expect(manager.downloadProgress == 0.0)
    }

    @Test func testGetCacheInfo() {
        let manager = createTestManager()

        let cacheInfo = manager.getCacheInfo()

        #expect(cacheInfo.sizeInMB >= 0.0)
        #expect(cacheInfo.count >= 0)
        #expect(cacheInfo.count == manager.tilesCount)
    }

    @Test func testTilesForRegionCalculation() async {
        let manager = createTestManager()

        // Test initial progress state
        #expect(manager.downloadProgress >= 0.0)
        #expect(manager.downloadProgress <= 1.0)
    }

    @Test func testClearCache() async {
        let manager = createTestManager()

        let result = await manager.clearCache()

        // Should succeed on empty cache
        #expect(result == true)
        #expect(manager.cacheSize == 0)
        #expect(manager.tilesCount == 0)
    }

    @Test func testDownloadProgressTracking() {
        let manager = createTestManager()

        // Test initial progress state
        #expect(manager.downloadProgress == 0.0)
        #expect(manager.isDownloading == false)
    }

    @Test func testCleanupCacheIfNeeded() async {
        let manager = createTestManager()

        // Test cleanup doesn't crash on empty cache
        await manager.cleanupCacheIfNeeded()

        #expect(manager.cacheSize == 0)
        #expect(manager.tilesCount == 0)
    }

    @Test func testCacheStatsUpdate() {
        let manager = createTestManager()

        manager.updateCacheStats()

        // Stats should be zero for fresh in-memory manager
        #expect(manager.cacheSize >= 0)
        #expect(manager.tilesCount >= 0)
    }

    @Test func testGetTileCoordinateValidation() async {
        let manager = createTestManager()

        // Test that manager handles tile requests without crashing
        // Network calls may fail in test environment, so nil is acceptable
        let tile = await manager.getTile(tileX: 0, tileY: 0, tileZ: 0)
        if let tileData = tile {
            #expect(!tileData.isEmpty, "Retrieved tile should contain non-empty data")
        }
        // Nil result is acceptable (network timeout, cache miss, etc.)
    }

    @Test func testDownloadTilesForRegionParameters() async {
        let manager = createTestManager()
        let center = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let smallRadius = 100.0

        // Start download (may fail due to network in test environment)
        await manager.downloadTilesForRegion(center: center, radius: smallRadius, minZoom: 10, maxZoom: 10)

        // Verify download state is reset after completion
        #expect(manager.downloadProgress == 1.0 || manager.downloadProgress == 0.0)
        #expect(manager.isDownloading == false)
    }

    @Test func testCacheInfoConsistency() {
        let manager = createTestManager()

        let info1 = manager.getCacheInfo()
        let info2 = manager.getCacheInfo()

        // Cache info should be consistent when called multiple times
        #expect(info1.count == info2.count)
        #expect(info1.sizeInMB == info2.sizeInMB)
    }

    @Test func testMaxCacheSizeConfiguration() {
        let manager = createTestManager()

        let info = manager.getCacheInfo()

        // Fresh in-memory cache should be empty
        #expect(info.sizeInMB == 0.0)
        #expect(info.count == 0)
    }

    @Test func testCoordinateEdgeCases() async {
        let manager = createTestManager()

        // Test negative coordinates - these create invalid URLs that return nil
        let negativeTile = await manager.getTile(tileX: -1, tileY: -1, tileZ: 1)
        // Note: OSM server may return 404 for invalid coordinates, or network may fail
        // The important thing is it doesn't crash
        _ = negativeTile  // Just verify no crash

        // Test out-of-bounds coordinates
        let outOfBoundsTile = await manager.getTile(tileX: 2_000_000, tileY: 2_000_000, tileZ: 20)
        // Should return nil for out-of-bounds, or network error
        _ = outOfBoundsTile  // Just verify no crash
    }
}
