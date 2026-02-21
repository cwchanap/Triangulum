import Foundation
import CoreMotion
import UIKit
import os

struct SensorSnapshot: Codable, Identifiable {

    var id = UUID()
    let timestamp: Date
    let barometer: BarometerData
    let location: LocationData
    let accelerometer: AccelerometerData
    let gyroscope: GyroscopeData
    let magnetometer: MagnetometerData
    let weather: WeatherData?
    let satellite: SatelliteSnapshotData?
    var photoIDs: [UUID] = []

    struct BarometerData: Codable {
        let pressure: Double
        let seaLevelPressure: Double?
        let attitude: AttitudeData?

        struct AttitudeData: Codable {
            let roll: Double
            let pitch: Double
            let yaw: Double
        }
    }

    struct LocationData: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let accuracy: Double
    }

    struct AccelerometerData: Codable {
        let accelerationX: Double
        let accelerationY: Double
        let accelerationZ: Double
        let magnitude: Double
    }

    struct GyroscopeData: Codable {
        let rotationX: Double
        let rotationY: Double
        let rotationZ: Double
        let magnitude: Double
    }

    struct MagnetometerData: Codable {
        let magneticFieldX: Double
        let magneticFieldY: Double
        let magneticFieldZ: Double
        let magnitude: Double
        let heading: Double
    }

    struct WeatherData: Codable {
        let temperature: Double
        let feelsLike: Double
        let humidity: Int
        let pressure: Int
        let windSpeed: Double?
        let condition: String
        let description: String
        let locationName: String
    }

    init(
        timestamp: Date = Date(),
        barometer: BarometerData,
        location: LocationData,
        accelerometer: AccelerometerData,
        gyroscope: GyroscopeData,
        magnetometer: MagnetometerData,
        weather: WeatherData? = nil,
        satellite: SatelliteSnapshotData? = nil,
        photoIDs: [UUID] = []
    ) {
        self.timestamp = timestamp
        self.barometer = barometer
        self.location = location
        self.accelerometer = accelerometer
        self.gyroscope = gyroscope
        self.magnetometer = magnetometer
        self.weather = weather
        self.satellite = satellite
        self.photoIDs = photoIDs
    }
}

extension SensorSnapshot {
    @MainActor static func capture(
        barometerManager: BarometerManager,
        locationManager: LocationManager,
        accelerometerManager: AccelerometerManager,
        gyroscopeManager: GyroscopeManager,
        magnetometerManager: MagnetometerManager,
        weatherManager: WeatherManager?,
        satelliteManager: SatelliteManager?
    ) -> SensorSnapshot {
        let barometer = BarometerData(
            pressure: barometerManager.pressure,
            seaLevelPressure: barometerManager.seaLevelPressure,
            attitude: barometerManager.attitude.map { attitude in
                BarometerData.AttitudeData(
                    roll: attitude.roll,
                    pitch: attitude.pitch,
                    yaw: attitude.yaw
                )
            }
        )

        let location = LocationData(
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            altitude: locationManager.altitude,
            accuracy: locationManager.accuracy
        )

        let accelerometer = AccelerometerData(
            accelerationX: accelerometerManager.accelerationX,
            accelerationY: accelerometerManager.accelerationY,
            accelerationZ: accelerometerManager.accelerationZ,
            magnitude: accelerometerManager.magnitude
        )

        let gyroscope = GyroscopeData(
            rotationX: gyroscopeManager.rotationX,
            rotationY: gyroscopeManager.rotationY,
            rotationZ: gyroscopeManager.rotationZ,
            magnitude: gyroscopeManager.magnitude
        )

        let magnetometer = MagnetometerData(
            magneticFieldX: magnetometerManager.magneticFieldX,
            magneticFieldY: magnetometerManager.magneticFieldY,
            magneticFieldZ: magnetometerManager.magneticFieldZ,
            magnitude: magnetometerManager.magnitude,
            heading: magnetometerManager.heading
        )

        let weather = weatherManager?.currentWeather.map { weather in
            WeatherData(
                temperature: weather.temperature,
                feelsLike: weather.feelsLike,
                humidity: weather.humidity,
                pressure: weather.pressure,
                windSpeed: weather.windSpeed,
                condition: weather.condition,
                description: weather.description,
                locationName: weather.locationName
            )
        }

        let satellite = satelliteManager?.snapshotData()

        return SensorSnapshot(
            barometer: barometer,
            location: location,
            accelerometer: accelerometer,
            gyroscope: gyroscope,
            magnetometer: magnetometer,
            weather: weather,
            satellite: satellite
        )
    }
}

struct SnapshotPhoto: Codable, Identifiable {

    let id: UUID
    let imageData: Data
    let timestamp: Date

    /// Creates a new snapshot photo from a UIImage
    /// - Parameter image: The image to store
    /// - Returns: nil if JPEG conversion fails
    init?(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8), !data.isEmpty else {
            Logger.snapshot.error("SnapshotPhoto: Failed to convert image to JPEG data")
            return nil
        }
        self.id = UUID()
        self.imageData = data
        self.timestamp = Date()
    }

    /// Creates a snapshot photo with explicit values (used when loading from disk)
    init(id: UUID, imageData: Data, timestamp: Date) {
        self.id = id
        self.imageData = imageData
        self.timestamp = timestamp
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }
}

@MainActor
class SnapshotManager: ObservableObject {
    @Published private(set) var snapshots: [SensorSnapshot] = []
    /// Not @Published - use getPhotos(for:) to access photos; populated via addPhoto() only.
    private(set) var photos: [UUID: SnapshotPhoto] = [:]
    @Published private(set) var loadError: Error?
    @Published private(set) var saveError: Error?
    private let userDefaults: UserDefaults
    private let snapshotsKey: String
    private var legacyPhotosKey: String { snapshotsKey.replacingOccurrences(of: "sensor_snapshots", with: "snapshot_photos") }
    let photosDirectory: URL

    /// Non-@Published cache for photos loaded from disk, avoiding unintended SwiftUI re-renders
    private var photoCache: [UUID: SnapshotPhoto] = [:]

    /// Default photos directory, created once at startup
    static let defaultPhotosDirectory: URL = {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // Fall back to a safe writable location rather than crashing
            Logger.snapshot.error("Documents directory unavailable — falling back to temporary directory")
            return FileManager.default.temporaryDirectory.appendingPathComponent("snapshot_photos", isDirectory: true)
        }
        let photosDir = documentsDir.appendingPathComponent("snapshot_photos", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        } catch {
            Logger.snapshot.error("Failed to create default photos directory: \(error.localizedDescription)")
        }
        return photosDir
    }()

    init() {
        self.userDefaults = UserDefaults.standard
        self.snapshotsKey = "sensor_snapshots"
        self.photosDirectory = Self.defaultPhotosDirectory
        loadSnapshots()
    }

    /// Internal initializer for testing with isolated storage
    init(userDefaults: UserDefaults, keyPrefix: String = "", photosDirectory: URL? = nil) {
        self.userDefaults = userDefaults
        self.snapshotsKey = "\(keyPrefix)sensor_snapshots"
        let resolvedPhotosDirectory = photosDirectory ?? Self.defaultPhotosDirectory
        self.photosDirectory = resolvedPhotosDirectory
        do {
            try FileManager.default.createDirectory(at: resolvedPhotosDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.snapshot.error("Failed to create photos directory at \(resolvedPhotosDirectory.path): \(error.localizedDescription)")
        }
        // Load synchronously for tests to ensure data is available immediately
        loadSnapshots()
    }

    /// Clears all data from storage - useful for test cleanup
    func resetStorage() {
        snapshots.removeAll()
        photos.removeAll()
        photoCache.removeAll()
        userDefaults.removeObject(forKey: snapshotsKey)
        try? FileManager.default.removeItem(at: photosDirectory)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    func addSnapshot(_ snapshot: SensorSnapshot) {
        snapshots.append(snapshot)
        saveSnapshots()
    }

    /// Removes a file at the given URL, logging a warning if deletion fails.
    /// Failing to delete a file that should be gone is non-fatal but noteworthy.
    private func removeFileLoggingError(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Already gone — acceptable, no action needed
        } catch {
            Logger.snapshot.warning("Failed to delete file at \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func deleteSnapshot(at index: Int) {
        guard index >= 0 && index < snapshots.count else { return }
        let snapshot = snapshots[index]
        for photoID in snapshot.photoIDs {
            let fileURL = photosDirectory.appendingPathComponent("\(photoID).jpg")
            removeFileLoggingError(at: fileURL)
            let metaURL = photosDirectory.appendingPathComponent("\(photoID).json")
            removeFileLoggingError(at: metaURL)
            photos.removeValue(forKey: photoID)
            photoCache.removeValue(forKey: photoID)
        }
        snapshots.remove(at: index)
        saveSnapshots()
    }

    func clearAllSnapshots() {
        let allPhotoIDs = snapshots.flatMap { $0.photoIDs }
        for photoID in allPhotoIDs {
            let fileURL = photosDirectory.appendingPathComponent("\(photoID).jpg")
            removeFileLoggingError(at: fileURL)
            let metaURL = photosDirectory.appendingPathComponent("\(photoID).json")
            removeFileLoggingError(at: metaURL)
        }
        photos.removeAll()
        photoCache.removeAll()
        snapshots.removeAll()
        saveSnapshots()
    }

    /// Adds a photo to a snapshot
    /// - Parameters:
    ///   - snapshotID: The ID of the snapshot to add the photo to
    ///   - image: The image to add
    /// - Returns: true if the photo was added successfully, false otherwise
    @discardableResult
    func addPhoto(to snapshotID: UUID, image: UIImage) -> Bool {
        guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else {
            Logger.snapshot.warning("Cannot add photo - snapshot not found: \(snapshotID)")
            return false
        }

        guard snapshots[snapshotIndex].photoIDs.count < 5 else {
            Logger.snapshot.warning("Cannot add photo - snapshot already has maximum 5 photos")
            return false
        }

        guard let photo = SnapshotPhoto(image: image) else {
            Logger.snapshot.error("Failed to create photo from image")
            return false
        }

        guard savePhotoToFile(photo) else {
            Logger.snapshot.error("Aborting addPhoto — file write failed for photo \(photo.id)")
            return false
        }
        photos[photo.id] = photo
        snapshots[snapshotIndex].photoIDs.append(photo.id)
        saveSnapshots()
        return true
    }

    func removePhoto(_ photoID: UUID, from snapshotID: UUID) {
        guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else { return }

        let fileURL = photosDirectory.appendingPathComponent("\(photoID).jpg")
        removeFileLoggingError(at: fileURL)
        let metaURL = photosDirectory.appendingPathComponent("\(photoID).json")
        removeFileLoggingError(at: metaURL)
        photos.removeValue(forKey: photoID)
        photoCache.removeValue(forKey: photoID)
        snapshots[snapshotIndex].photoIDs.removeAll { $0 == photoID }
        saveSnapshots()
    }

    /// Returns the photos for a snapshot from the in-memory cache only.
    ///
    /// Photos added this session (via `addPhoto`) are immediately available.
    /// For photos belonging to a snapshot loaded from a previous session, call
    /// `prewarmCache(for:)` first (off the main thread) so disk reads don't
    /// block the main actor during rendering.
    func getPhotos(for snapshotID: UUID) -> [SnapshotPhoto] {
        guard let snapshot = snapshots.first(where: { $0.id == snapshotID }) else { return [] }
        return snapshot.photoIDs.compactMap { id in
            if let cached = photos[id] { return cached }
            if let cached = photoCache[id] { return cached }
            return nil
        }
    }

    /// Pre-loads photos from disk into the in-memory cache off the main actor,
    /// so that subsequent `getPhotos(for:)` calls return immediately.
    func prewarmCache(for snapshotID: UUID) async {
        guard let snapshot = snapshots.first(where: { $0.id == snapshotID }) else { return }
        let idsToLoad = snapshot.photoIDs.filter { photos[$0] == nil && photoCache[$0] == nil }
        guard !idsToLoad.isEmpty else { return }

        let dir = photosDirectory
        let loaded: [(UUID, SnapshotPhoto)] = await Task.detached {
            idsToLoad.compactMap { id in
                let fileURL = dir.appendingPathComponent("\(id).jpg")
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    Logger.snapshot.error("[snapshot] prewarmCache: failed to load photo \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
                let metaURL = dir.appendingPathComponent("\(id).json")
                let timestamp: Date
                do {
                    let metaData = try Data(contentsOf: metaURL)
                    let meta = try JSONDecoder().decode(PhotoMetadata.self, from: metaData)
                    timestamp = meta.timestamp
                } catch {
                    Logger.snapshot.warning("[snapshot] prewarmCache: missing/corrupt metadata for \(id, privacy: .public), using current time: \(error.localizedDescription, privacy: .public)")
                    timestamp = Date()
                }
                return (id, SnapshotPhoto(id: id, imageData: data, timestamp: timestamp))
            }
        }.value

        for (id, photo) in loaded {
            photoCache[id] = photo
        }
    }

    @discardableResult
    private func savePhotoToFile(_ photo: SnapshotPhoto) -> Bool {
        let fileURL = photosDirectory.appendingPathComponent("\(photo.id).jpg")
        let metaURL = photosDirectory.appendingPathComponent("\(photo.id).json")
        do {
            try photo.imageData.write(to: fileURL, options: .atomic)
            // Write metadata sidecar to preserve id and timestamp on reload
            let meta = PhotoMetadata(id: photo.id, timestamp: photo.timestamp)
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: metaURL, options: .atomic)
            return true
        } catch {
            Logger.snapshot.error("Failed to save photo \(photo.id): \(error.localizedDescription)")
            saveError = error
            return false
        }
    }

    private func loadPhotoFromFile(id: UUID) -> SnapshotPhoto? {
        let fileURL = photosDirectory.appendingPathComponent("\(id).jpg")
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Logger.snapshot.error("Failed to load photo \(id) from disk: \(error.localizedDescription)")
            return nil
        }

        // Try to read timestamp from metadata sidecar; fall back to Date() for legacy photos
        let metaURL = photosDirectory.appendingPathComponent("\(id).json")
        let timestamp: Date
        do {
            let metaData = try Data(contentsOf: metaURL)
            let meta = try JSONDecoder().decode(PhotoMetadata.self, from: metaData)
            timestamp = meta.timestamp
        } catch {
            Logger.snapshot.warning("Missing or corrupt metadata for photo \(id), using current time: \(error.localizedDescription)")
            timestamp = Date()
        }

        return SnapshotPhoto(id: id, imageData: data, timestamp: timestamp)
    }

    private func saveSnapshots() {
        do {
            let data = try JSONEncoder().encode(snapshots)
            userDefaults.set(data, forKey: snapshotsKey)
            saveError = nil  // Clear error on successful save
        } catch {
            Logger.snapshot.error("SnapshotManager: Failed to save snapshots: \(error.localizedDescription)")
            saveError = error
        }
    }

    private func loadSnapshots() {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }
        do {
            snapshots = try JSONDecoder().decode([SensorSnapshot].self, from: data)
            loadError = nil  // Clear error on successful load
            migrateLegacyPhotosIfNeeded()
        } catch {
            Logger.snapshot.error("SnapshotManager: Failed to load snapshots: \(error.localizedDescription)")
            Logger.snapshot.warning("Corrupted data preserved - use clearCorruptedData() to remove if needed")
            loadError = error
            // DO NOT auto-delete user data - preserve it for potential recovery
        }
    }

    /// One-time migration: reads the legacy `snapshot_photos` UserDefaults blob
    /// (a `[UUID: SnapshotPhoto]` payload written before the file-system storage move)
    /// and writes each photo that is still referenced by a loaded snapshot to disk.
    /// Clears the legacy key only when all referenced photos are successfully migrated.
    private func migrateLegacyPhotosIfNeeded() {
        guard let legacyData = userDefaults.data(forKey: legacyPhotosKey) else { return }
        Logger.snapshot.info("Migrating legacy UserDefaults photos to file system")

        let legacyPhotos: [UUID: SnapshotPhoto]
        do {
            legacyPhotos = try JSONDecoder().decode([UUID: SnapshotPhoto].self, from: legacyData)
        } catch {
            Logger.snapshot.error("Failed to decode legacy photos during migration: \(error.localizedDescription)")
            return
        }

        let referencedIDs = Set(snapshots.flatMap { $0.photoIDs })
        var migratedIDs = Set<UUID>()
        for (id, photo) in legacyPhotos where referencedIDs.contains(id) {
            // Only write if file doesn't already exist (idempotent)
            let fileURL = photosDirectory.appendingPathComponent("\(id).jpg")
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                migratedIDs.insert(id)
                continue
            }
            if savePhotoToFile(photo) {
                photos[id] = photo
                migratedIDs.insert(id)
            }
        }

        Logger.snapshot.info("Migrated \(migratedIDs.count) legacy photos to file system")

        // Determine which referenced IDs exist in legacyPhotos
        let referencedLegacyIDs = Set(legacyPhotos.keys).intersection(referencedIDs)

        // Only clear legacy key if all referenced photos that exist in legacy were migrated
        if migratedIDs == referencedLegacyIDs {
            userDefaults.removeObject(forKey: legacyPhotosKey)
        } else {
            // Persist remaining un-migrated photos back to UserDefaults for future retry
            let unmigratedIDs = referencedLegacyIDs.subtracting(migratedIDs)
            var unmigratedPhotos: [UUID: SnapshotPhoto] = [:]
            for id in unmigratedIDs {
                if let photo = legacyPhotos[id] {
                    unmigratedPhotos[id] = photo
                }
            }
            do {
                let data = try JSONEncoder().encode(unmigratedPhotos)
                userDefaults.set(data, forKey: legacyPhotosKey)
                Logger.snapshot.warning("Partial migration: \(unmigratedIDs.count) photos remain in UserDefaults for retry")
            } catch {
                Logger.snapshot.error("Failed to persist unmigrated photos: \(error.localizedDescription)")
            }
        }
    }

    /// Manually clears corrupted data from storage
    /// This should only be called after user confirmation when data cannot be recovered
    func clearCorruptedData() {
        Logger.snapshot.warning("Clearing corrupted data by user request")
        userDefaults.removeObject(forKey: snapshotsKey)
        try? FileManager.default.removeItem(at: photosDirectory)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        snapshots.removeAll()
        photos.removeAll()
        photoCache.removeAll()
        loadError = nil
        saveError = nil
    }
}

/// Lightweight metadata persisted alongside each photo JPEG for timestamp recovery
private struct PhotoMetadata: Codable {
    let id: UUID
    let timestamp: Date
}
