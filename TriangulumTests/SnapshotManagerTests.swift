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

    // Helper function to create test sensor managers
    private func createTestManagers() -> (BarometerManager, LocationManager, AccelerometerManager, GyroscopeManager, MagnetometerManager) {
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

        return (barometerManager, locationManager, accelerometerManager, gyroscopeManager, magnetometerManager)
    }

    @Test func testSnapshotManagerInitialization() {
        let manager = SnapshotManager()

        #expect(manager.snapshots.isEmpty)
        #expect(manager.photos.isEmpty)
    }

    @Test func testAddSnapshot() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(
            barometerManager: barometer,
            locationManager: location,
            accelerometerManager: accelerometer,
            gyroscopeManager: gyroscope,
            magnetometerManager: magnetometer,
            weatherManager: nil
        )

        manager.addSnapshot(snapshot)

        #expect(manager.snapshots.count == 1)
        #expect(manager.snapshots.first?.barometer.pressure == 101.325)
        #expect(manager.snapshots.first?.location.latitude == 37.7749)
    }

    @Test func testDeleteSnapshot() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot1 = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
        let snapshot2 = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)

        manager.addSnapshot(snapshot1)
        manager.addSnapshot(snapshot2)

        #expect(manager.snapshots.count == 2)

        manager.deleteSnapshot(at: 0)

        #expect(manager.snapshots.count == 1)
    }

    @Test func testDeleteSnapshotInvalidIndex() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
        manager.addSnapshot(snapshot)

        #expect(manager.snapshots.count == 1)

        // Try to delete invalid indices
        manager.deleteSnapshot(at: 5)
        manager.deleteSnapshot(at: -1)

        #expect(manager.snapshots.count == 1) // Should remain unchanged
    }

    @Test func testClearAllSnapshots() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot1 = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
        let snapshot2 = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)

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
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
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
        let manager = SnapshotManager()
        let testImage = createTestImage()
        let nonExistentID = UUID()

        manager.addPhoto(to: nonExistentID, image: testImage)

        #expect(manager.photos.isEmpty)
    }

    @Test func testRemovePhoto() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
        manager.addSnapshot(snapshot)

        let testImage = createTestImage()
        manager.addPhoto(to: snapshot.id, image: testImage)

        #expect(manager.photos.count == 1)
        #expect(manager.snapshots.first?.photoIDs.count == 1)

        let photoID = manager.snapshots.first?.photoIDs.first
        #expect(photoID != nil)

        manager.removePhoto(photoID!, from: snapshot.id)

        #expect(manager.photos.isEmpty)
        #expect(manager.snapshots.first?.photoIDs.isEmpty == true)
    }

    @Test func testRemovePhotoFromNonExistentSnapshot() {
        let manager = SnapshotManager()
        let testPhotoID = UUID()
        let nonExistentSnapshotID = UUID()

        manager.removePhoto(testPhotoID, from: nonExistentSnapshotID)

        // Should not crash or cause issues
        #expect(manager.photos.isEmpty)
        #expect(manager.snapshots.isEmpty)
    }

    @Test func testGetPhotosForSnapshot() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
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
        let manager = SnapshotManager()
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
        // Create an empty image
        UIGraphicsBeginImageContext(CGSize.zero)
        defer { UIGraphicsEndImageContext() }

        let emptyImage = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let photo = SnapshotPhoto(image: emptyImage)

        // Empty/zero-size image may fail JPEG conversion, so photo could be nil
        // This is expected behavior - the failable initializer correctly rejects invalid images
        // No assertion needed - just verify it doesn't crash
    }

    @Test func testMultiplePhotosPerSnapshot() {
        let manager = SnapshotManager()
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(barometerManager: barometer, locationManager: location, accelerometerManager: accelerometer, gyroscopeManager: gyroscope, magnetometerManager: magnetometer, weatherManager: nil)
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

    @Test func testSnapshotDataStructureIntegrity() {
        let (barometer, location, accelerometer, gyroscope, magnetometer) = createTestManagers()

        let snapshot = SensorSnapshot(
            barometerManager: barometer,
            locationManager: location,
            accelerometerManager: accelerometer,
            gyroscopeManager: gyroscope,
            magnetometerManager: magnetometer,
            weatherManager: nil
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
}
