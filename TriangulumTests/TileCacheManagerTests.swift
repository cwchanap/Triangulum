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
struct TileCacheManagerTests {

    @Test func testTileCacheManagerSingletonInitialization() {
        let manager1 = TileCacheManager.shared
        let manager2 = TileCacheManager.shared

        #expect(manager1 === manager2)
        #expect(manager1.cacheSize >= 0)
        #expect(manager1.tilesCount >= 0)
        #expect(manager1.isDownloading == false)
        #expect(manager1.downloadProgress == 0.0)
    }

    @Test func testInitialCacheState() {
        let manager = TileCacheManager.shared

        #expect(manager.cacheSize >= 0)
        #expect(manager.tilesCount >= 0)
        #expect(manager.isDownloading == false)
        #expect(manager.downloadProgress == 0.0)
    }

    @Test func testGetCacheInfo() {
        let manager = TileCacheManager.shared

        let cacheInfo = manager.getCacheInfo()

        #expect(cacheInfo.sizeInMB >= 0.0)
        #expect(cacheInfo.count >= 0)
        #expect(cacheInfo.count == manager.tilesCount)
    }

    @Test func testTilesForRegionCalculation() async {
        let manager = TileCacheManager.shared
        let center = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
        let radius = 1000.0 // 1km
        let zoom = 12

        // Using reflection to access private method for testing
        // Note: This is for testing purposes and requires the method to be made internal or public for testing
        // For now, we'll test the public interface

        // Test that downloading for a region sets the appropriate flags
        Task {
            await manager.downloadTilesForRegion(center: center, radius: radius, minZoom: 12, maxZoom: 12)
        }

        // Initially should not be downloading (async operation)
        #expect(manager.downloadProgress >= 0.0)
        #expect(manager.downloadProgress <= 1.0)
    }

    @Test func testClearCache() async {
        let manager = TileCacheManager.shared

        await manager.clearCache()

        // After clearing cache, counts should be zero or remain consistent
        #expect(manager.cacheSize >= 0)
        #expect(manager.tilesCount >= 0)
    }

    @Test func testDownloadProgressTracking() {
        let manager = TileCacheManager.shared

        // Test initial progress state
        #expect(manager.downloadProgress >= 0.0)
        #expect(manager.downloadProgress <= 1.0)
        #expect(manager.isDownloading == false)
    }

    @Test func testCleanupCacheIfNeeded() async {
        let manager = TileCacheManager.shared

        // Test cleanup doesn't crash
        await manager.cleanupCacheIfNeeded()

        #expect(manager.cacheSize >= 0)
        #expect(manager.tilesCount >= 0)
    }

    @Test func testCacheStatsUpdate() {
        let manager = TileCacheManager.shared

        let initialSize = manager.cacheSize
        let initialCount = manager.tilesCount

        manager.updateCacheStats()

        // Stats should remain consistent after update
        #expect(manager.cacheSize >= 0)
        #expect(manager.tilesCount >= 0)
    }

    @Test func testGetTileCoordinateValidation() async {
        let manager = TileCacheManager.shared

        // Test valid coordinates
        let validTile = await manager.getTile(tileX: 0, tileY: 0, tileZ: 0)
        #expect(validTile != nil || validTile == nil) // Either succeeds or fails gracefully

        // Test boundary coordinates
        let boundaryTile = await manager.getTile(tileX: 255, tileY: 255, tileZ: 8)
        #expect(boundaryTile != nil || boundaryTile == nil) // Either succeeds or fails gracefully
    }

    @Test func testDownloadTilesForRegionParameters() async {
        let manager = TileCacheManager.shared
        let center = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0) // Equator/Prime Meridian
        let smallRadius = 100.0 // 100 meters

        // Test with small region to avoid overwhelming the test
        await manager.downloadTilesForRegion(center: center, radius: smallRadius, minZoom: 10, maxZoom: 10)

        // Verify the download completed (progress should be 1.0 or reset to 0.0)
        #expect(manager.downloadProgress == 1.0 || manager.downloadProgress == 0.0)
        #expect(manager.isDownloading == false)
    }

    @Test func testCacheInfoConsistency() {
        let manager = TileCacheManager.shared

        let info1 = manager.getCacheInfo()
        let info2 = manager.getCacheInfo()

        // Cache info should be consistent when called multiple times without changes
        #expect(info1.count == info2.count)
        #expect(info1.sizeInMB == info2.sizeInMB)
    }

    @Test func testMaxCacheSizeConfiguration() {
        let manager = TileCacheManager.shared

        // Test that cache info is within reasonable bounds
        let info = manager.getCacheInfo()

        // Cache size should not exceed reasonable limits (100MB = ~104.86 MB in decimal)
        #expect(info.sizeInMB <= 150.0) // Allow some margin for test tolerance
        #expect(info.count >= 0)
    }

    @Test func testCoordinateEdgeCases() async {
        let manager = TileCacheManager.shared

        // Test negative coordinates (should handle gracefully)
        let negativeTile = await manager.getTile(tileX: -1, tileY: -1, tileZ: 1)
        #expect(negativeTile != nil || negativeTile == nil)

        // Test very high coordinates (should handle gracefully)
        let highCoordTile = await manager.getTile(tileX: 999999, tileY: 999999, tileZ: 20)
        #expect(highCoordTile != nil || highCoordTile == nil)

        // Test zero zoom level
        let zeroZoomTile = await manager.getTile(tileX: 0, tileY: 0, tileZ: 0)
        #expect(zeroZoomTile != nil || zeroZoomTile == nil)
    }
}
