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
    @Published private(set) var photos: [UUID: SnapshotPhoto] = [:]
    @Published private(set) var loadError: Error?
    @Published private(set) var saveError: Error?
    private let userDefaults: UserDefaults
    private let snapshotsKey: String

    private static var photosDirectory: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let photosDir = documentsDir.appendingPathComponent("snapshot_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        return photosDir
    }

    init() {
        self.userDefaults = UserDefaults.standard
        self.snapshotsKey = "sensor_snapshots"
        Task {
            await loadSnapshotsAsync()
        }
    }

    /// Internal initializer for testing with isolated storage
    init(userDefaults: UserDefaults, keyPrefix: String = "") {
        self.userDefaults = userDefaults
        self.snapshotsKey = "\(keyPrefix)sensor_snapshots"
        // Load synchronously for tests to ensure data is available immediately
        loadSnapshots()
    }

    /// Clears all data from storage - useful for test cleanup
    func resetStorage() {
        snapshots.removeAll()
        photos.removeAll()
        userDefaults.removeObject(forKey: snapshotsKey)
        try? FileManager.default.removeItem(at: Self.photosDirectory)
        try? FileManager.default.createDirectory(at: Self.photosDirectory, withIntermediateDirectories: true)
    }

    func addSnapshot(_ snapshot: SensorSnapshot) {
        snapshots.append(snapshot)
        saveSnapshots()
    }

    func deleteSnapshot(at index: Int) {
        guard index >= 0 && index < snapshots.count else { return }
        snapshots.remove(at: index)
        saveSnapshots()
    }

    func clearAllSnapshots() {
        let allPhotoIDs = snapshots.flatMap { $0.photoIDs }
        for photoID in allPhotoIDs {
            let fileURL = Self.photosDirectory.appendingPathComponent("\(photoID).jpg")
            try? FileManager.default.removeItem(at: fileURL)
        }
        photos.removeAll()
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

        savePhotoToFile(photo)
        photos[photo.id] = photo
        snapshots[snapshotIndex].photoIDs.append(photo.id)
        saveSnapshots()
        return true
    }

    func removePhoto(_ photoID: UUID, from snapshotID: UUID) {
        guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else { return }

        let fileURL = Self.photosDirectory.appendingPathComponent("\(photoID).jpg")
        try? FileManager.default.removeItem(at: fileURL)
        photos.removeValue(forKey: photoID)
        snapshots[snapshotIndex].photoIDs.removeAll { $0 == photoID }
        saveSnapshots()
    }

    func getPhotos(for snapshotID: UUID) -> [SnapshotPhoto] {
        guard let snapshot = snapshots.first(where: { $0.id == snapshotID }) else { return [] }
        return snapshot.photoIDs.compactMap { id in
            if let cached = photos[id] { return cached }
            if let loaded = loadPhotoFromFile(id: id) {
                photos[id] = loaded
                return loaded
            }
            return nil
        }
    }

    private func savePhotoToFile(_ photo: SnapshotPhoto) {
        let fileURL = Self.photosDirectory.appendingPathComponent("\(photo.id).jpg")
        do {
            try photo.imageData.write(to: fileURL, options: .atomic)
        } catch {
            Logger.snapshot.error("Failed to save photo \(photo.id): \(error.localizedDescription)")
            saveError = error
        }
    }

    private func loadPhotoFromFile(id: UUID) -> SnapshotPhoto? {
        let fileURL = Self.photosDirectory.appendingPathComponent("\(id).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return SnapshotPhoto(id: id, imageData: data, timestamp: Date())
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

    private func loadSnapshotsAsync() async {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }

        do {
            let loadedSnapshots = try JSONDecoder().decode([SensorSnapshot].self, from: data)
            self.snapshots = loadedSnapshots
            self.loadError = nil  // Clear error on successful load
        } catch {
            Logger.snapshot.error("SnapshotManager: Failed to load snapshots: \(error.localizedDescription)")
            Logger.snapshot.warning("Corrupted data preserved - use clearCorruptedData() to remove if needed")
            self.loadError = error
            // DO NOT auto-delete user data - preserve it for potential recovery
        }
    }

    private func loadSnapshots() {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }
        do {
            snapshots = try JSONDecoder().decode([SensorSnapshot].self, from: data)
            loadError = nil  // Clear error on successful load
        } catch {
            Logger.snapshot.error("SnapshotManager: Failed to load snapshots: \(error.localizedDescription)")
            Logger.snapshot.warning("Corrupted data preserved - use clearCorruptedData() to remove if needed")
            loadError = error
            // DO NOT auto-delete user data - preserve it for potential recovery
        }
    }

    /// Manually clears corrupted data from storage
    /// This should only be called after user confirmation when data cannot be recovered
    func clearCorruptedData() {
        Logger.snapshot.warning("Clearing corrupted data by user request")
        userDefaults.removeObject(forKey: snapshotsKey)
        try? FileManager.default.removeItem(at: Self.photosDirectory)
        try? FileManager.default.createDirectory(at: Self.photosDirectory, withIntermediateDirectories: true)
        snapshots.removeAll()
        photos.removeAll()
        loadError = nil
        saveError = nil
    }
}
