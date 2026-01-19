import Foundation
import CoreMotion
import UIKit

struct SensorSnapshot: Codable, Identifiable {
    // swiftlint:disable:next identifier_name
    var id = UUID()
    let timestamp: Date
    let barometer: BarometerData
    let location: LocationData
    let accelerometer: AccelerometerData
    let gyroscope: GyroscopeData
    let magnetometer: MagnetometerData
    let weather: WeatherData?
    var photoIDs: [UUID] = []

    struct BarometerData: Codable {
        let pressure: Double
        let seaLevelPressure: Double
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
        barometerManager: BarometerManager,
        locationManager: LocationManager,
        accelerometerManager: AccelerometerManager,
        gyroscopeManager: GyroscopeManager,
        magnetometerManager: MagnetometerManager,
        weatherManager: WeatherManager?
    ) {
        self.timestamp = Date()

        self.barometer = BarometerData(
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

        self.location = LocationData(
            latitude: locationManager.latitude,
            longitude: locationManager.longitude,
            altitude: locationManager.altitude,
            accuracy: locationManager.accuracy
        )

        self.accelerometer = AccelerometerData(
            accelerationX: accelerometerManager.accelerationX,
            accelerationY: accelerometerManager.accelerationY,
            accelerationZ: accelerometerManager.accelerationZ,
            magnitude: accelerometerManager.magnitude
        )

        self.gyroscope = GyroscopeData(
            rotationX: gyroscopeManager.rotationX,
            rotationY: gyroscopeManager.rotationY,
            rotationZ: gyroscopeManager.rotationZ,
            magnitude: gyroscopeManager.magnitude
        )

        self.magnetometer = MagnetometerData(
            magneticFieldX: magnetometerManager.magneticFieldX,
            magneticFieldY: magnetometerManager.magneticFieldY,
            magneticFieldZ: magnetometerManager.magneticFieldZ,
            magnitude: magnetometerManager.magnitude,
            heading: magnetometerManager.heading
        )

        self.weather = weatherManager?.currentWeather.map { weather in
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
    }
}

struct SnapshotPhoto: Codable, Identifiable {
    // swiftlint:disable:next identifier_name
    let id: UUID
    let imageData: Data
    let timestamp: Date

    /// Creates a new snapshot photo from a UIImage
    /// - Parameter image: The image to store
    /// - Returns: nil if JPEG conversion fails
    init?(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8), !data.isEmpty else {
            print("❌ SnapshotPhoto: Failed to convert image to JPEG data")
            return nil
        }
        self.id = UUID()
        self.imageData = data
        self.timestamp = Date()
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }
}

class SnapshotManager: ObservableObject {
    @Published private(set) var snapshots: [SensorSnapshot] = []
    @Published private(set) var photos: [UUID: SnapshotPhoto] = [:]
    private let userDefaults: UserDefaults
    private let snapshotsKey: String
    private let photosKey: String

    init() {
        self.userDefaults = UserDefaults.standard
        self.snapshotsKey = "sensor_snapshots"
        self.photosKey = "snapshot_photos"
        // Load data asynchronously to avoid blocking main thread
        Task {
            await loadSnapshotsAsync()
            await loadPhotosAsync()
        }
    }

    /// Internal initializer for testing with isolated storage
    init(userDefaults: UserDefaults, keyPrefix: String = "") {
        self.userDefaults = userDefaults
        self.snapshotsKey = "\(keyPrefix)sensor_snapshots"
        self.photosKey = "\(keyPrefix)snapshot_photos"
        // Load synchronously for tests to ensure data is available immediately
        loadSnapshots()
        loadPhotos()
    }

    /// Clears all data from storage - useful for test cleanup
    func resetStorage() {
        snapshots.removeAll()
        photos.removeAll()
        userDefaults.removeObject(forKey: snapshotsKey)
        userDefaults.removeObject(forKey: photosKey)
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
            photos.removeValue(forKey: photoID)
        }
        snapshots.removeAll()
        saveSnapshots()
        savePhotos()
    }

    /// Adds a photo to a snapshot
    /// - Parameters:
    ///   - snapshotID: The ID of the snapshot to add the photo to
    ///   - image: The image to add
    /// - Returns: true if the photo was added successfully, false otherwise
    @discardableResult
    func addPhoto(to snapshotID: UUID, image: UIImage) -> Bool {
        guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else {
            print("⚠️ SnapshotManager: Cannot add photo - snapshot not found: \(snapshotID)")
            return false
        }

        guard let photo = SnapshotPhoto(image: image) else {
            print("❌ SnapshotManager: Failed to create photo from image")
            return false
        }

        photos[photo.id] = photo
        snapshots[snapshotIndex].photoIDs.append(photo.id)

        saveSnapshots()
        savePhotos()
        return true
    }

    func removePhoto(_ photoID: UUID, from snapshotID: UUID) {
        guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else { return }

        photos.removeValue(forKey: photoID)
        snapshots[snapshotIndex].photoIDs.removeAll { $0 == photoID }

        saveSnapshots()
        savePhotos()
    }

    func getPhotos(for snapshotID: UUID) -> [SnapshotPhoto] {
        guard let snapshot = snapshots.first(where: { $0.id == snapshotID }) else { return [] }
        return snapshot.photoIDs.compactMap { photos[$0] }
    }

    private func saveSnapshots() {
        do {
            let data = try JSONEncoder().encode(snapshots)
            userDefaults.set(data, forKey: snapshotsKey)
        } catch {
            print("Failed to save snapshots: \(error)")
        }
    }

    private func loadSnapshotsAsync() async {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }

        do {
            let loadedSnapshots = try JSONDecoder().decode([SensorSnapshot].self, from: data)
            await MainActor.run {
                self.snapshots = loadedSnapshots
            }
        } catch {
            print("Failed to load snapshots: \(error)")
            // Clear corrupted data to prevent future crashes
            userDefaults.removeObject(forKey: snapshotsKey)
        }
    }

    private func loadSnapshots() {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }
        do {
            snapshots = try JSONDecoder().decode([SensorSnapshot].self, from: data)
        } catch {
            print("Failed to load snapshots: \(error)")
            // Clear corrupted data to prevent future crashes
            userDefaults.removeObject(forKey: snapshotsKey)
        }
    }

    private func savePhotos() {
        do {
            let data = try JSONEncoder().encode(photos)
            userDefaults.set(data, forKey: photosKey)
        } catch {
            print("Failed to save photos: \(error)")
        }
    }

    private func loadPhotosAsync() async {
        guard let data = userDefaults.data(forKey: photosKey) else { return }

        do {
            let loadedPhotos = try JSONDecoder().decode([UUID: SnapshotPhoto].self, from: data)
            await MainActor.run {
                self.photos = loadedPhotos
            }
        } catch {
            print("Failed to load photos: \(error)")
            // Clear corrupted data to prevent future crashes
            userDefaults.removeObject(forKey: photosKey)
        }
    }

    private func loadPhotos() {
        guard let data = userDefaults.data(forKey: photosKey) else { return }
        do {
            photos = try JSONDecoder().decode([UUID: SnapshotPhoto].self, from: data)
        } catch {
            print("Failed to load photos: \(error)")
            // Clear corrupted data to prevent future crashes
            userDefaults.removeObject(forKey: photosKey)
        }
    }
}
