//
//  SnapshotManagerTests.swift
//  TriangulumTests
//
//  Created by Chan Wai Chan on 21/8/2025.
//

import Testing
import Foundation
import UIKit
@testable import Triangulum

@MainActor
@Suite(.serialized)
struct SnapshotManagerTests {

    // Helper function to create a test image
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }

        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    // Helper to create an isolated SnapshotManager for testing.
    // Each call creates a unique temporary directory; call manager.resetStorage()
    // at the end of a test (or let the unique UUID path be collected by the OS)
    // to avoid accumulating stale tmp directories between test runs.
    private func createTestManager() -> SnapshotManager {
        let testDefaults = UserDefaults(suiteName: "SnapshotManagerTests_\(UUID().uuidString)")!
        let testPhotosDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotManagerTests_\(UUID().uuidString)")
        let manager = SnapshotManager(userDefaults: testDefaults, keyPrefix: "test_", photosDirectory: testPhotosDir)
        return manager
    }

    // Helper struct to hold test sensor managers
    private struct TestManagers {
        let barometerManager: BarometerManager
        let locationManager: LocationManager
        let accelerometerManager: AccelerometerManager
        let gyroscopeManager: GyroscopeManager
        let magnetometerManager: MagnetometerManager
    }

    // Helper function to create test sensor managers
    private func createTestManagers() -> TestManagers {
        let locationManager = LocationManager()
        let barometerManager = BarometerManager(locationManager: locationManager)
        let accelerometerManager = AccelerometerManager()
        let gyroscopeManager = GyroscopeManager()
        let magnetometerManager = MagnetometerManager()

        // Set some test values
        barometerManager.pressure = 101.325
        barometerManager.seaLevelPressure = 102.0

        locationManager.latitude = 37.7749
        locationManager.longitude = -122.4194
        locationManager.altitude = 100.0
        locationManager.accuracy = 5.0

        accelerometerManager.accelerationX = 0.1
        accelerometerManager.accelerationY = -0.2
        accelerometerManager.accelerationZ = 0.9
        accelerometerManager.magnitude = 0.93

        gyroscopeManager.rotationX = 0.05
        gyroscopeManager.rotationY = -0.03
        gyroscopeManager.rotationZ = 0.01
        gyroscopeManager.magnitude = 0.06

        magnetometerManager.magneticFieldX = 20.0
        magnetometerManager.magneticFieldY = -10.0
        magnetometerManager.magneticFieldZ = 50.0
        magnetometerManager.magnitude = 53.85
        magnetometerManager.heading = 135.0

        return TestManagers(
            barometerManager: barometerManager,
            locationManager: locationManager,
            accelerometerManager: accelerometerManager,
            gyroscopeManager: gyroscopeManager,
            magnetometerManager: magnetometerManager
        )
    }

    @Test func testSnapshotManagerInitialization() {
        let manager = createTestManager()

        #expect(manager.snapshots.isEmpty)
        #expect(manager.photos.isEmpty)
    }

    @Test func testAddSnapshot() {
        let manager = createTestManager()
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )

        manager.addSnapshot(snapshot)

        #expect(manager.snapshots.count == 1)
        #expect(manager.snapshots.first?.barometer.pressure == 101.325)
        #expect(manager.snapshots.first?.location.latitude == 37.7749)
    }

    @Test func testDeleteSnapshot() {
        let manager = createTestManager()
        let testManagers = createTestManagers()

        let snapshot1 = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        let snapshot2 = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )

        manager.addSnapshot(snapshot1)
        manager.addSnapshot(snapshot2)

        #expect(manager.snapshots.count == 2)

        manager.deleteSnapshot(at: 0)

        #expect(manager.snapshots.count == 1)
    }

    @Test func testDeleteSnapshotCleansUpPhotos() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        // Add two photos to the snapshot
        let testImage = createTestImage()
        manager.addPhoto(to: snapshot.id, image: testImage)
        manager.addPhoto(to: snapshot.id, image: testImage)
        #expect(manager.photos.count == 2)
        #expect(manager.snapshots.first?.photoIDs.count == 2)

        // Capture photo IDs and directory before deletion
        let photoIDsBeforeDeletion = manager.snapshots.first?.photoIDs ?? []
        let photosDir = manager.photosDirectory
        #expect(photoIDsBeforeDeletion.count == 2)

        // Delete the snapshot — photos should also be cleaned up
        manager.deleteSnapshot(at: 0)

        #expect(manager.snapshots.isEmpty)
        #expect(manager.photos.isEmpty)
        // Verify photo files are removed from disk
        for photoID in photoIDsBeforeDeletion {
            let jpgURL = photosDir.appendingPathComponent("\(photoID).jpg")
            let jsonURL = photosDir.appendingPathComponent("\(photoID).json")
            #expect(!FileManager.default.fileExists(atPath: jpgURL.path), "JPG file should be deleted for photo \(photoID)")
            #expect(!FileManager.default.fileExists(atPath: jsonURL.path), "JSON sidecar should be deleted for photo \(photoID)")
        }
    }

    @Test func testDeleteSnapshotInvalidIndex() {
        let manager = createTestManager()
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        #expect(manager.snapshots.count == 1)

        // Try to delete invalid indices
        manager.deleteSnapshot(at: 5)
        manager.deleteSnapshot(at: -1)

        #expect(manager.snapshots.count == 1) // Should remain unchanged
    }

    @Test func testClearAllSnapshots() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testManagers = createTestManagers()

        let snapshot1 = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        let snapshot2 = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )

        manager.addSnapshot(snapshot1)
        manager.addSnapshot(snapshot2)

        // Add photos to snapshots
        let testImage = createTestImage()
        manager.addPhoto(to: snapshot1.id, image: testImage)
        manager.addPhoto(to: snapshot2.id, image: testImage)

        #expect(manager.snapshots.count == 2)
        #expect(manager.photos.count == 2)

        manager.clearAllSnapshots()

        #expect(manager.snapshots.isEmpty)
        #expect(manager.photos.isEmpty)
    }

    @Test func testAddPhoto() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        let testImage = createTestImage()
        manager.addPhoto(to: snapshot.id, image: testImage)

        #expect(manager.photos.count == 1)
        #expect(manager.snapshots.first?.photoIDs.count == 1)

        let photos = manager.getPhotos(for: snapshot.id)
        #expect(photos.count == 1)
        #expect(photos.first?.image != nil)
    }

    @Test func testAddPhotoToNonExistentSnapshot() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testImage = createTestImage()
        let nonExistentID = UUID()

        manager.addPhoto(to: nonExistentID, image: testImage)

        #expect(manager.photos.isEmpty)
    }

    @Test func testRemovePhoto() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        let testImage = createTestImage()
        manager.addPhoto(to: snapshot.id, image: testImage)

        #expect(manager.photos.count == 1)
        #expect(manager.snapshots.first?.photoIDs.count == 1)

        let photoID = manager.snapshots.first?.photoIDs.first
        #expect(photoID != nil)

        guard let safePhotoID = photoID else {
            Issue.record("Expected photoID to be non-nil before removal")
            return
        }
        manager.removePhoto(safePhotoID, from: snapshot.id)

        #expect(manager.photos.isEmpty)
        #expect(manager.snapshots.first?.photoIDs.isEmpty == true)
    }

    @Test func testRemovePhotoFromNonExistentSnapshot() {
        let manager = createTestManager()
        let testPhotoID = UUID()
        let nonExistentSnapshotID = UUID()

        manager.removePhoto(testPhotoID, from: nonExistentSnapshotID)

        // Should not crash or cause issues
        #expect(manager.photos.isEmpty)
        #expect(manager.snapshots.isEmpty)
    }

    @Test func testGetPhotosForSnapshot() {
        let manager = createTestManager()
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        let testImage1 = createTestImage()
        let testImage2 = createTestImage()

        manager.addPhoto(to: snapshot.id, image: testImage1)
        manager.addPhoto(to: snapshot.id, image: testImage2)

        let photos = manager.getPhotos(for: snapshot.id)

        #expect(photos.count == 2)
        #expect(photos.allSatisfy { $0.image != nil })
    }

    @Test func testGetPhotosForNonExistentSnapshot() {
        let manager = createTestManager()
        let nonExistentID = UUID()

        let photos = manager.getPhotos(for: nonExistentID)

        #expect(photos.isEmpty)
    }

    @Test func testSnapshotPhotoInitialization() {
        let testImage = createTestImage()
        let photo = SnapshotPhoto(image: testImage)

        #expect(photo != nil)
        #expect(photo?.imageData.count ?? 0 > 0)
        #expect(photo?.image != nil)
        #expect(photo?.timestamp.timeIntervalSinceNow ?? -100 < 1.0)
    }

    @Test func testSnapshotPhotoJPEGCompression() {
        let testImage = createTestImage()
        let photo = SnapshotPhoto(image: testImage)

        // Should have some data due to JPEG compression
        #expect(photo != nil)
        #expect(photo?.imageData.count ?? 0 > 0)

        // Should be able to recreate image from data
        let recreatedImage = photo?.image
        #expect(recreatedImage != nil)
    }

    @Test func testSnapshotPhotoWithEmptyImage() {
        // Create an empty 1x1 image (CGSize.zero crashes in iOS 18+)
        // We're testing that a very small/trivial image still works
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let emptyImage = renderer.image { _ in
            // Draw nothing - creates a 1x1 transparent image
        }
        let photo = SnapshotPhoto(image: emptyImage)

        // A 1x1 image may still produce valid JPEG data
        // The key is that the failable initializer handles edge cases gracefully
        // No crash = success
        _ = photo
    }

    @Test func testMultiplePhotosPerSnapshot() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        let testImage = createTestImage()

        // Add multiple photos
        for _ in 0..<5 {
            manager.addPhoto(to: snapshot.id, image: testImage)
        }

        #expect(manager.photos.count == 5)
        #expect(manager.snapshots.first?.photoIDs.count == 5)

        let photos = manager.getPhotos(for: snapshot.id)
        #expect(photos.count == 5)
    }

    @Test func testPhotoLimitEnforcement() {
        let manager = createTestManager()
        defer { manager.resetStorage() }
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager.addSnapshot(snapshot)

        let testImage = createTestImage()

        // Add 5 photos (the maximum)
        for _ in 0..<5 {
            let result = manager.addPhoto(to: snapshot.id, image: testImage)
            #expect(result == true)
        }

        // Attempt a 6th photo — should be rejected
        let rejected = manager.addPhoto(to: snapshot.id, image: testImage)
        #expect(rejected == false)

        #expect(manager.photos.count == 5)
        #expect(manager.snapshots.first?.photoIDs.count == 5)
        #expect(manager.getPhotos(for: snapshot.id).count == 5)
    }

    @Test func testSnapshotDataStructureIntegrity() {
        let testManagers = createTestManagers()

        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )

        // Verify all data is captured correctly
        #expect(snapshot.barometer.pressure == 101.325)
        #expect(snapshot.barometer.seaLevelPressure == 102.0)

        #expect(snapshot.location.latitude == 37.7749)
        #expect(snapshot.location.longitude == -122.4194)
        #expect(snapshot.location.altitude == 100.0)
        #expect(snapshot.location.accuracy == 5.0)

        #expect(snapshot.accelerometer.accelerationX == 0.1)
        #expect(snapshot.accelerometer.accelerationY == -0.2)
        #expect(snapshot.accelerometer.accelerationZ == 0.9)
        #expect(snapshot.accelerometer.magnitude == 0.93)

        #expect(snapshot.gyroscope.rotationX == 0.05)
        #expect(snapshot.gyroscope.rotationY == -0.03)
        #expect(snapshot.gyroscope.rotationZ == 0.01)
        #expect(snapshot.gyroscope.magnitude == 0.06)

        #expect(snapshot.magnetometer.magneticFieldX == 20.0)
        #expect(snapshot.magnetometer.magneticFieldY == -10.0)
        #expect(snapshot.magnetometer.magneticFieldZ == 50.0)
        #expect(snapshot.magnetometer.magnitude == 53.85)
        #expect(snapshot.magnetometer.heading == 135.0)

        #expect(snapshot.photoIDs.isEmpty)
        #expect(snapshot.timestamp.timeIntervalSinceNow < 1.0)
    }

    // Verifies that snapshots and their associated photo files survive a manager
    // restart pointing at the same UserDefaults suite and photos directory — the
    // exact scenario that occurs every time the app is relaunched.
    @Test func testSnapshotSurvivesManagerRecreation() throws {
        let suiteName = "test_roundtrip_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        // Manager 1: create a snapshot and attach a photo.
        let manager1 = SnapshotManager(userDefaults: defaults, keyPrefix: "rt_", photosDirectory: dir)

        let testManagers = createTestManagers()
        let snapshot = SensorSnapshot.capture(
            barometerManager: testManagers.barometerManager,
            locationManager: testManagers.locationManager,
            accelerometerManager: testManagers.accelerometerManager,
            gyroscopeManager: testManagers.gyroscopeManager,
            magnetometerManager: testManagers.magnetometerManager,
            weatherManager: nil,
            satelliteManager: nil
        )
        manager1.addSnapshot(snapshot)

        // Create a minimal 1x1 white image so photo storage code exercises the
        // JPEG-compression and on-disk write paths without depending on test
        // fixture files.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let added = manager1.addPhoto(to: snapshot.id, image: image)
        #expect(added == true)
        #expect(manager1.snapshots.count == 1)
        #expect(manager1.snapshots.first?.photoIDs.count == 1)
        let originalPhotoID = try #require(manager1.snapshots.first?.photoIDs.first)

        // Manager 2: simulate an app restart — a fresh instance backed by the
        // same UserDefaults suite and photos directory as manager1.
        let manager2 = SnapshotManager(userDefaults: defaults, keyPrefix: "rt_", photosDirectory: dir)

        // The snapshot must be reloaded from UserDefaults with its identity and
        // photo reference intact.
        #expect(manager2.snapshots.count == 1)
        #expect(manager2.snapshots.first?.id == snapshot.id)
        #expect(manager2.snapshots.first?.photoIDs.count == 1)
        #expect(manager2.snapshots.first?.photoIDs.first == originalPhotoID)

        // The photo file written by manager1 must still be readable via manager2.
        let photos = manager2.getPhotos(for: snapshot.id)
        #expect(photos.count == 1)
        #expect(photos.first?.id == originalPhotoID)
        #expect(photos.first?.image != nil)
    }
}
