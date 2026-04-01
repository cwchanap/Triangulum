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
import MapKit
@testable import Triangulum

private final class MockTileURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _responseProvider: ((URLRequest) throws -> (URLResponse, Data?))?
    private static var _requestCount = 0

    static var responseProvider: ((URLRequest) throws -> (URLResponse, Data?))? {
        get { lock.withLock { _responseProvider } }
        set { lock.withLock { _responseProvider = newValue } }
    }

    static var requestCount: Int {
        get { lock.withLock { _requestCount } }
    }

    static func reset() {
        lock.withLock {
            _responseProvider = nil
            _requestCount = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var provider: ((URLRequest) throws -> (URLResponse, Data?))?
        Self.lock.withLock {
            Self._requestCount += 1
            provider = Self._responseProvider
        }

        guard let responseProvider = provider else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try responseProvider(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct TileCacheManagerTests {

    // Helper to create an isolated in-memory manager for testing
    private func createTestManager(urlSession: URLSession? = nil) -> TileCacheManager {
        if let urlSession {
            return TileCacheManager(inMemory: true, urlSession: urlSession)
        }
        return TileCacheManager(inMemory: true)
    }

    private func createMockSession(
        responseProvider: @escaping (URLRequest) throws -> (URLResponse, Data?)
    ) -> URLSession {
        MockTileURLProtocol.reset()
        MockTileURLProtocol.responseProvider = responseProvider

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTileURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func waitForCacheStats(_ manager: TileCacheManager, expectedCount: Int, timeoutSteps: Int = 100) async {
        for _ in 0..<timeoutSteps where manager.tilesCount != expectedCount {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func loadTile(
        overlay: CachedTileOverlay,
        path: MKTileOverlayPath
    ) async -> (data: Data?, error: Error?) {
        await withCheckedContinuation { continuation in
            overlay.loadTile(at: path) { data, error in
                continuation.resume(returning: (data, error))
            }
        }
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

    @Test func testGetTileDownloadsAndCachesData() async throws {
        let tileData = Data([0x89, 0x50, 0x4E, 0x47])
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, tileData)
        }
        let manager = createTestManager(urlSession: session)

        let firstTile = await manager.getTile(tileX: 1, tileY: 2, tileZ: 3)
        let secondTile = await manager.getTile(tileX: 1, tileY: 2, tileZ: 3)
        await waitForCacheStats(manager, expectedCount: 1)

        #expect(firstTile == tileData)
        #expect(secondTile == tileData)
        #expect(MockTileURLProtocol.requestCount == 1)
        #expect(manager.tilesCount == 1)
        #expect(manager.cacheSize == tileData.count)
    }

    @Test func testGetTileReturnsNilForNonHTTPResponse() async throws {
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = URLResponse(url: url, mimeType: "image/png", expectedContentLength: 4, textEncodingName: nil)
            return (response, Data([0x01, 0x02, 0x03, 0x04]))
        }
        let manager = createTestManager(urlSession: session)

        let tile = await manager.getTile(tileX: 4, tileY: 5, tileZ: 6)

        #expect(tile == nil)
    }

    @Test func testGetTileReturnsNilForHTTPError() async throws {
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
        let manager = createTestManager(urlSession: session)

        let tile = await manager.getTile(tileX: 7, tileY: 8, tileZ: 9)

        #expect(tile == nil)
    }

    @Test func testGetTileReturnsNilForNetworkError() async {
        let session = createMockSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let manager = createTestManager(urlSession: session)

        let tile = await manager.getTile(tileX: 10, tileY: 11, tileZ: 12)

        #expect(tile == nil)
    }

    @Test func testCachedTileOverlayURLForTilePath() {
        let overlay = CachedTileOverlay(urlTemplate: nil, cacheManager: createTestManager())
        let path = MKTileOverlayPath(x: 3, y: 5, z: 7, contentScaleFactor: 1)

        let url = overlay.url(forTilePath: path)

        #expect(url.absoluteString == "https://tile.openstreetmap.org/7/3/5.png")
    }

    @Test func testCachedTileOverlayLoadTileReturnsCachedData() async throws {
        let tileData = Data([0xAA, 0xBB, 0xCC])
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, tileData)
        }
        let manager = createTestManager(urlSession: session)
        _ = await manager.getTile(tileX: 13, tileY: 14, tileZ: 15)
        let overlay = CachedTileOverlay(urlTemplate: nil, cacheManager: manager)
        let path = MKTileOverlayPath(x: 13, y: 14, z: 15, contentScaleFactor: 1)

        let result = await loadTile(overlay: overlay, path: path)

        #expect(result.data == tileData)
        #expect(result.error == nil)
        #expect(MockTileURLProtocol.requestCount == 1)
    }

    @Test func testCachedTileOverlayLoadTileReturnsNotFoundErrorWhenTileUnavailable() async throws {
        let session = createMockSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
            return (response, Data())
        }
        let manager = createTestManager(urlSession: session)
        let overlay = CachedTileOverlay(urlTemplate: nil, cacheManager: manager)
        let path = MKTileOverlayPath(x: 16, y: 17, z: 18, contentScaleFactor: 1)

        let result = await loadTile(overlay: overlay, path: path)
        let error = result.error as NSError?

        #expect(result.data == nil)
        #expect(error?.domain == "TileError")
        #expect(error?.code == 404)
    }
}
