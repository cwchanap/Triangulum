import Foundation
import CoreMotion
import UIKit

struct SensorSnapshot: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let barometer: BarometerData
    let location: LocationData
    let accelerometer: AccelerometerData
    let gyroscope: GyroscopeData
    let magnetometer: MagnetometerData
    var photoIDs: [UUID] = []
    
    struct BarometerData: Codable {
        let pressure: Double
        let relativeAltitude: Double
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
    
    init(barometerManager: BarometerManager, locationManager: LocationManager, accelerometerManager: AccelerometerManager, gyroscopeManager: GyroscopeManager, magnetometerManager: MagnetometerManager) {
        self.timestamp = Date()
        
        self.barometer = BarometerData(
            pressure: barometerManager.pressure,
            relativeAltitude: barometerManager.relativeAltitude,
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
    }
}

struct SnapshotPhoto: Codable, Identifiable {
    let id = UUID()
    let imageData: Data
    let timestamp: Date
    
    init(image: UIImage) {
        self.imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
        self.timestamp = Date()
    }
    
    var image: UIImage? {
        UIImage(data: imageData)
    }
}

class SnapshotManager: ObservableObject {
    @Published var snapshots: [SensorSnapshot] = []
    @Published var photos: [UUID: SnapshotPhoto] = [:]
    private let userDefaults = UserDefaults.standard
    private let snapshotsKey = "sensor_snapshots"
    private let photosKey = "snapshot_photos"
    
    init() {
        loadSnapshots()
        loadPhotos()
    }
    
    func addSnapshot(_ snapshot: SensorSnapshot) {
        snapshots.append(snapshot)
        saveSnapshots()
    }
    
    func deleteSnapshot(at index: Int) {
        guard index < snapshots.count else { return }
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
    
    func addPhoto(to snapshotID: UUID, image: UIImage) {
        guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else { return }
        
        let photo = SnapshotPhoto(image: image)
        photos[photo.id] = photo
        snapshots[snapshotIndex].photoIDs.append(photo.id)
        
        saveSnapshots()
        savePhotos()
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
    
    private func loadSnapshots() {
        guard let data = userDefaults.data(forKey: snapshotsKey) else { return }
        do {
            snapshots = try JSONDecoder().decode([SensorSnapshot].self, from: data)
        } catch {
            print("Failed to load snapshots: \(error)")
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
    
    private func loadPhotos() {
        guard let data = userDefaults.data(forKey: photosKey) else { return }
        do {
            photos = try JSONDecoder().decode([UUID: SnapshotPhoto].self, from: data)
        } catch {
            print("Failed to load photos: \(error)")
        }
    }
}