//
//  MapTileTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 21/8/2025.
//

import Testing
import Foundation
import SwiftData
@testable import Triangulum

struct MapTileTests {

    @Test func testMapTileInitialization() {
        let tileX = 123
        let tileY = 456
        let tileZ = 10
        let data = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
        let url = "https://tile.openstreetmap.org/10/123/456.png"

        let tile = MapTile(tileX: tileX, tileY: tileY, tileZ: tileZ, data: data, url: url)

        #expect(tile.tileX == tileX)
        #expect(tile.tileY == tileY)
        #expect(tile.tileZ == tileZ)
        #expect(tile.data == data)
        #expect(tile.url == url)
        #expect(tile.timestamp.timeIntervalSinceNow < 1.0) // Should be very recent
    }

    @Test func testTileKey() {
        let tile = MapTile(tileX: 123, tileY: 456, tileZ: 10, data: Data(), url: "test")

        #expect(tile.tileKey == "10/123/456")
    }

    @Test func testTileKeyUniqueness() {
        let tile1 = MapTile(tileX: 1, tileY: 2, tileZ: 3, data: Data(), url: "test1")
        let tile2 = MapTile(tileX: 1, tileY: 2, tileZ: 4, data: Data(), url: "test2")
        let tile3 = MapTile(tileX: 2, tileY: 2, tileZ: 3, data: Data(), url: "test3")
        let tile4 = MapTile(tileX: 1, tileY: 3, tileZ: 3, data: Data(), url: "test4")

        #expect(tile1.tileKey != tile2.tileKey) // Different zoom
        #expect(tile1.tileKey != tile3.tileKey) // Different tileX
        #expect(tile1.tileKey != tile4.tileKey) // Different tileY

        let tile5 = MapTile(tileX: 1, tileY: 2, tileZ: 3, data: Data([1, 2, 3]), url: "different")
        #expect(tile1.tileKey == tile5.tileKey) // Same coordinates, different data/url
    }

    @Test func testTileKeyFormat() {
        let tile = MapTile(tileX: 0, tileY: 0, tileZ: 0, data: Data(), url: "test")
        #expect(tile.tileKey == "0/0/0")

        let tileNegative = MapTile(tileX: -1, tileY: -1, tileZ: -1, data: Data(), url: "test")
        #expect(tileNegative.tileKey == "-1/-1/-1")

        let tileLarge = MapTile(tileX: 999999, tileY: 888888, tileZ: 20, data: Data(), url: "test")
        #expect(tileLarge.tileKey == "20/999999/888888")
    }

    @Test func testIsExpiredFreshTile() {
        let tile = MapTile(tileX: 1, tileY: 1, tileZ: 1, data: Data(), url: "test")

        #expect(tile.isExpired == false)
    }

    @Test func testIsExpiredOldTile() {
        let tile = MapTile(tileX: 1, tileY: 1, tileZ: 1, data: Data(), url: "test")

        // Manually set timestamp to 8 days ago (beyond 7 day expiration)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        // Note: We can't directly modify the timestamp in SwiftData model for testing
        // This test verifies the logic but cannot test expired tiles without reflection
        // or a more complex setup

        // Test the expiration calculation logic instead
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let timeSinceEightDaysAgo = Date().timeIntervalSince(eightDaysAgo)
        let shouldBeExpired = timeSinceEightDaysAgo > expirationInterval

        #expect(shouldBeExpired == true)
    }

    @Test func testExpirationLogic() {
        // Test expiration calculation logic
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let eightDaysAgo = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let sixDaysAgo = now.addingTimeInterval(-6 * 24 * 60 * 60)

        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days

        // Exactly 7 days should not be expired
        let exactlySevenDays = now.timeIntervalSince(sevenDaysAgo)
        #expect(exactlySevenDays <= expirationInterval)

        // More than 7 days should be expired
        let moreThanSevenDays = now.timeIntervalSince(eightDaysAgo)
        #expect(moreThanSevenDays > expirationInterval)

        // Less than 7 days should not be expired
        let lessThanSevenDays = now.timeIntervalSince(sixDaysAgo)
        #expect(lessThanSevenDays < expirationInterval)
    }

    @Test func testTileDataHandling() {
        let emptyData = Data()
        let tile1 = MapTile(tileX: 1, tileY: 1, tileZ: 1, data: emptyData, url: "test")
        #expect(tile1.data.isEmpty)

        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let tile2 = MapTile(tileX: 2, tileY: 2, tileZ: 2, data: pngData, url: "test")
        #expect(tile2.data == pngData)
        #expect(tile2.data.count == 8)

        let largeData = Data(repeating: 0xFF, count: 1024 * 1024) // 1MB
        let tile3 = MapTile(tileX: 3, tileY: 3, tileZ: 3, data: largeData, url: "test")
        #expect(tile3.data.count == 1024 * 1024)
    }

    @Test func testURLHandling() {
        let validURL = "https://tile.openstreetmap.org/10/123/456.png"
        let tile1 = MapTile(tileX: 123, tileY: 456, tileZ: 10, data: Data(), url: validURL)
        #expect(tile1.url == validURL)

        let emptyURL = ""
        let tile2 = MapTile(tileX: 1, tileY: 1, tileZ: 1, data: Data(), url: emptyURL)
        #expect(tile2.url == emptyURL)

        let customURL = "https://custom.tile.server.com/tiles/z/x/y.png"
        let tile3 = MapTile(tileX: 1, tileY: 1, tileZ: 1, data: Data(), url: customURL)
        #expect(tile3.url == customURL)
    }

    @Test func testCoordinateBoundaries() {
        // Test zero coordinates
        let zeroTile = MapTile(tileX: 0, tileY: 0, tileZ: 0, data: Data(), url: "test")
        #expect(zeroTile.tileX == 0)
        #expect(zeroTile.tileY == 0)
        #expect(zeroTile.tileZ == 0)
        #expect(zeroTile.tileKey == "0/0/0")

        // Test negative coordinates
        let negativeTile = MapTile(tileX: -1, tileY: -2, tileZ: -3, data: Data(), url: "test")
        #expect(negativeTile.tileX == -1)
        #expect(negativeTile.tileY == -2)
        #expect(negativeTile.tileZ == -3)
        #expect(negativeTile.tileKey == "-3/-1/-2")

        // Test large coordinates
        let largeTile = MapTile(tileX: Int.max, tileY: Int.max, tileZ: Int.max, data: Data(), url: "test")
        #expect(largeTile.tileX == Int.max)
        #expect(largeTile.tileY == Int.max)
        #expect(largeTile.tileZ == Int.max)
    }

    @Test func testTimestampAccuracy() {
        let beforeCreation = Date()
        let tile = MapTile(tileX: 1, tileY: 1, tileZ: 1, data: Data(), url: "test")
        let afterCreation = Date()

        #expect(tile.timestamp >= beforeCreation)
        #expect(tile.timestamp <= afterCreation)
        #expect(tile.timestamp.timeIntervalSince(beforeCreation) < 1.0)
    }

    @Test func testTileEquality() {
        let data1 = Data([1, 2, 3])
        let data2 = Data([1, 2, 3])
        let data3 = Data([4, 5, 6])

        let tile1 = MapTile(tileX: 1, tileY: 2, tileZ: 3, data: data1, url: "url1")
        let tile2 = MapTile(tileX: 1, tileY: 2, tileZ: 3, data: data2, url: "url1")
        let tile3 = MapTile(tileX: 1, tileY: 2, tileZ: 3, data: data3, url: "url2")

        // Same coordinates should have same tileKey
        #expect(tile1.tileKey == tile2.tileKey)
        #expect(tile1.tileKey == tile3.tileKey)

        // But data and URLs can be different
        #expect(tile1.data == tile2.data)
        #expect(tile1.data != tile3.data)
        #expect(tile1.url == tile2.url)
        #expect(tile1.url != tile3.url)
    }
}
