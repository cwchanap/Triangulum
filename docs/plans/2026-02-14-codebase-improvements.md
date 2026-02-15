# Codebase Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Address 22 identified improvements across critical fixes, architecture, code quality, and test coverage.

**Architecture:** Incremental improvements organized into 9 dependency-ordered groups. Each group is committed independently. No data migration needed (no existing users).

**Tech Stack:** Swift, SwiftUI, SwiftData, CoreMotion, CoreLocation, os.Logger

---

### Task 1: Create Logger Extensions

**Files:**
- Create: `Triangulum/Utilities/Log.swift`

**Step 1: Create the logging utility**

```swift
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.triangulum"

    static let weather = Logger(subsystem: subsystem, category: "weather")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let sensor = Logger(subsystem: subsystem, category: "sensor")
    static let satellite = Logger(subsystem: subsystem, category: "satellite")
    static let map = Logger(subsystem: subsystem, category: "map")
    static let snapshot = Logger(subsystem: subsystem, category: "snapshot")
    static let app = Logger(subsystem: subsystem, category: "app")
}
```

**Step 2: Add the file to the Xcode project**

Ensure `Log.swift` is added to the Triangulum target in Xcode.

**Step 3: Build to verify**

Run: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

---

### Task 2: Replace Debug Prints with os.Logger

**Files:**
- Modify: `Triangulum/Managers/WeatherManager.swift` (replace all ~15 `print("DEBUG: ...")` calls)
- Modify: `Triangulum/Managers/LocationManager.swift` (replace all ~8 `print("DEBUG: ...")` calls)
- Modify: `Triangulum/Managers/SatelliteManager.swift` (replace all `print("SatelliteManager: ...")` calls)
- Modify: `Triangulum/Managers/BarometerManager.swift` (replace `print("⚠️ BarometerManager: ...")` calls)
- Modify: `Triangulum/Models/SensorSnapshot.swift` (replace `print("❌ SnapshotManager: ...")` and `print("⚠️ ...")` calls)
- Modify: `Triangulum/Views/WeatherView.swift` (replace `print("DEBUG: ...")` on line 28)
- Modify: `Triangulum/TriangulumApp.swift` (replace `print("Failed to create ModelContainer: ...")`)

**Step 1: Add `import os` to each file and replace print statements**

Pattern for replacements:
- `print("DEBUG: ...")` → `Logger.weather.debug("...")` (in WeatherManager)
- `print("DEBUG: ...")` → `Logger.location.debug("...")` (in LocationManager)
- `print("SatelliteManager: ...")` → `Logger.satellite.debug("...")` or `.info(...)` or `.error(...)` as appropriate
- `print("⚠️ BarometerManager: ...")` → `Logger.sensor.warning("...")`
- `print("❌ SnapshotManager: ...")` → `Logger.snapshot.error("...")`
- `print("⚠️ ...")` → `Logger.snapshot.warning("...")`
- Error paths → `.error(...)`, info paths → `.info(...)`, debug/trace → `.debug(...)`

IMPORTANT: In `WeatherManager.swift` line 112, the current code prints a partial API key:
```swift
print("DEBUG: API URL: \(baseURL)?lat=\(lat)&lon=\(lon)&appid=\(String(apiKey.prefix(8)))...")
```
Replace with:
```swift
Logger.weather.debug("Fetching weather for lat=\(lat), lon=\(lon)")
```
Do NOT include any part of the API key in logs.

**Step 2: Build and run tests**

Run: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

---

### Task 3: Commit Group 1+3 (Logging System)

```bash
git add Triangulum/Utilities/Log.swift Triangulum/Managers/ Triangulum/Models/SensorSnapshot.swift Triangulum/Views/WeatherView.swift Triangulum/TriangulumApp.swift
git commit -m "refactor: replace debug prints with structured os.Logger

Introduces Logger extensions with per-subsystem categories (weather,
location, sensor, satellite, map, snapshot, app). Removes all print()
statements from production code. Fixes API key partial exposure in
WeatherManager logs.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Fix WeatherManager Polling

**Files:**
- Modify: `Triangulum/Managers/WeatherManager.swift`

**Step 1: Change 3-second polling to fetch-then-stop pattern**

Replace the `setupLocationObserver()` method and `checkAndFetchWeather()`:

```swift
private func setupLocationObserver() {
    // Check immediately after a short delay for initialization
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.checkAndFetchWeather()
    }

    // Poll every 3 seconds ONLY until we get initial weather data
    weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
        self?.checkAndFetchWeather()
    }
}
```

In `checkAndFetchWeather()`, after the `fetchWeather()` call on line 85, add timer stop:

```swift
if currentWeather == nil && !isLoading {
    Logger.weather.debug("Auto-fetching weather data")
    fetchWeather()
    // Stop frequent polling once we start a fetch
    stopFrequentPolling()
}
```

Add helper method:

```swift
private func stopFrequentPolling() {
    weatherCheckTimer?.invalidate()
    weatherCheckTimer = nil
    // Switch to infrequent refresh (15 minutes)
    weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { [weak self] _ in
        self?.checkAndFetchWeather()
    }
}
```

Also, in the `fetchWeather()` completion (the URLSession callback), after successfully parsing weather data, stop polling:

After `self?.currentWeather = Weather(from: weatherResponse)` add:
```swift
self?.stopFrequentPolling()
```

**Step 2: Modernize fetchWeather to async/await**

Replace the URLSession.dataTask callback pattern with:

```swift
func fetchWeather() {
    guard Config.hasValidAPIKey else {
        errorMessage = "API key required"
        return
    }

    let coordinate = CLLocationCoordinate2D(latitude: locationManager.latitude, longitude: locationManager.longitude)
    guard CLLocationCoordinate2DIsValid(coordinate) && (coordinate.latitude != 0 && coordinate.longitude != 0) else {
        errorMessage = "No location data available"
        return
    }

    isLoading = true
    errorMessage = ""

    let lat = locationManager.latitude
    let lon = locationManager.longitude
    let apiKey = Config.openWeatherAPIKey
    let urlString = "\(baseURL)?lat=\(lat)&lon=\(lon)&appid=\(apiKey)"

    Logger.weather.debug("Fetching weather for lat=\(lat), lon=\(lon)")

    guard let url = URL(string: urlString) else {
        errorMessage = "Invalid API URL"
        isLoading = false
        return
    }

    Task { [weak self] in
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            await MainActor.run {
                guard let self = self else { return }
                self.isLoading = false

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    self.errorMessage = "API Error: HTTP \(httpResponse.statusCode)"
                    Logger.weather.error("HTTP \(httpResponse.statusCode)")
                    return
                }

                do {
                    let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    self.currentWeather = Weather(from: weatherResponse)
                    self.errorMessage = ""
                    self.stopFrequentPolling()
                    Logger.weather.info("Weather data parsed successfully")
                } catch {
                    self.errorMessage = "Failed to parse weather data"
                    Logger.weather.error("Parse error: \(error.localizedDescription)")
                }
            }
        } catch {
            await MainActor.run {
                guard let self = self else { return }
                self.isLoading = false
                self.errorMessage = "Network error: \(error.localizedDescription)"
                Logger.weather.error("Network error: \(error.localizedDescription)")
            }
        }
    }
}
```

**Step 3: Build to verify**

Run: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build`

---

### Task 5: Mask API Key in PreferencesView

**Files:**
- Modify: `Triangulum/Views/PreferencesView.swift`

**Step 1: Replace the "View API Key" alert (lines 165-175)**

Replace:
```swift
.alert("Your OpenWeatherMap API Key", isPresented: $showingViewAPIKeyAlert) {
    Button("Copy to Clipboard") {
        let apiKey = Config.openWeatherAPIKey
        if !apiKey.isEmpty {
            UIPasteboard.general.string = apiKey
        }
    }
    Button("Close", role: .cancel) { }
} message: {
    Text(Config.openWeatherAPIKey.isEmpty ? "No API key found" : Config.openWeatherAPIKey)
}
```

With:
```swift
.alert("Your OpenWeatherMap API Key", isPresented: $showingViewAPIKeyAlert) {
    Button("Copy to Clipboard") {
        let apiKey = Config.openWeatherAPIKey
        if !apiKey.isEmpty {
            UIPasteboard.general.string = apiKey
        }
    }
    Button("Close", role: .cancel) { }
} message: {
    Text(maskedAPIKey)
}
```

Add helper computed property in PreferencesView:
```swift
private var maskedAPIKey: String {
    let key = Config.openWeatherAPIKey
    guard key.count > 8 else { return key.isEmpty ? "No API key found" : "****" }
    let prefix = String(key.prefix(4))
    let suffix = String(key.suffix(4))
    return "\(prefix)...\(suffix)"
}
```

**Step 2: Build to verify**

---

### Task 6: Commit Group 1 Critical Fixes

```bash
git add Triangulum/Managers/WeatherManager.swift Triangulum/Views/PreferencesView.swift
git commit -m "fix: stop aggressive weather polling and mask API key display

WeatherManager now stops 3-second polling after initial fetch and
switches to 15-minute refresh interval. Modernized to async/await.
PreferencesView now masks API key showing only first/last 4 chars.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Create Shared CMMotionManager + Sensor Protocol

**Files:**
- Create: `Triangulum/Managers/MotionService.swift`
- Modify: `Triangulum/Managers/AccelerometerManager.swift`
- Modify: `Triangulum/Managers/GyroscopeManager.swift`
- Modify: `Triangulum/Managers/MagnetometerManager.swift`
- Modify: `Triangulum/Managers/BarometerManager.swift`

**Step 1: Create MotionService singleton**

```swift
import CoreMotion

final class MotionService {
    static let shared = CMMotionManager()

    private init() {}
}
```

**Step 2: Update AccelerometerManager to use shared instance**

Replace `private let motionManager = CMMotionManager()` with:
```swift
private let motionManager: CMMotionManager

init(motionManager: CMMotionManager = MotionService.shared) {
    self.motionManager = motionManager
    checkAvailability()
}
```

Remove the existing `init()`.

**Step 3: Update GyroscopeManager similarly**

Replace `private let motionManager = CMMotionManager()` with:
```swift
private let motionManager: CMMotionManager

init(motionManager: CMMotionManager = MotionService.shared) {
    self.motionManager = motionManager
    checkAvailability()
}
```

Also fix the string-based error detection (lines 39-40):
```swift
// Replace:
if error.localizedDescription.contains("not authorized") ||
    error.localizedDescription.contains("permission") {

// With:
let nsError = error as NSError
if nsError.domain == CMErrorDomain {
```

**Step 4: Update MagnetometerManager similarly**

Replace `private let motionManager = CMMotionManager()` with:
```swift
private let motionManager: CMMotionManager

init(motionManager: CMMotionManager = MotionService.shared) {
    self.motionManager = motionManager
    checkAvailability()
}
```

Also fix the string-based error detection (lines 40-41):
```swift
// Replace:
if error.localizedDescription.contains("not authorized") ||
    error.localizedDescription.contains("permission") {

// With:
let nsError = error as NSError
if nsError.domain == CMErrorDomain {
```

**Step 5: Update BarometerManager**

Replace `private let motionManager = CMMotionManager()` (line 8) with:
```swift
private let motionManager: CMMotionManager
```

Update the init:
```swift
init(locationManager: LocationManager, motionManager: CMMotionManager = MotionService.shared) {
    self.locationManager = locationManager
    self.motionManager = motionManager
    checkAvailability()
}
```

**Step 6: Build and run tests**

Run: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build`
Run: `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum -destination 'platform=iOS Simulator,name=iPhone 16'`

---

### Task 8: Commit Group 2 (Shared CMMotionManager + Error Detection)

```bash
git add Triangulum/Managers/MotionService.swift Triangulum/Managers/AccelerometerManager.swift Triangulum/Managers/GyroscopeManager.swift Triangulum/Managers/MagnetometerManager.swift Triangulum/Managers/BarometerManager.swift
git commit -m "refactor: share single CMMotionManager and fix error detection

Apple requires one CMMotionManager per app. Introduced MotionService
singleton shared by all sensor managers. Fixed string-based error
detection in Gyroscope/Magnetometer managers to use CMErrorDomain.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 9: Decouple SensorSnapshot from Managers

**Files:**
- Modify: `Triangulum/Models/SensorSnapshot.swift`

**Step 1: Add memberwise initializer to SensorSnapshot**

Keep the existing manager-based init but add a new raw-value init above it:

```swift
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
```

**Step 2: Move manager-based init to a factory extension**

Create an extension at the bottom of the file (after the struct):

```swift
extension SensorSnapshot {
    static func capture(
        barometerManager: BarometerManager,
        locationManager: LocationManager,
        accelerometerManager: AccelerometerManager,
        gyroscopeManager: GyroscopeManager,
        magnetometerManager: MagnetometerManager,
        weatherManager: WeatherManager?,
        satelliteManager: SatelliteManager?
    ) -> SensorSnapshot {
        // (move existing init body here, returning SensorSnapshot(...))
    }
}
```

Remove the old `init(barometerManager:...)`.

**Step 3: Update ContentView.swift takeSnapshot()**

Replace the `SensorSnapshot(barometerManager:...)` call (line 194) with:
```swift
let snapshot = SensorSnapshot.capture(
    barometerManager: barometerManager,
    locationManager: locationManager,
    accelerometerManager: accelerometerManager,
    gyroscopeManager: gyroscopeManager,
    magnetometerManager: magnetometerManager,
    weatherManager: weatherManager,
    satelliteManager: satelliteManager
)
```

**Step 4: Add photo count limit to SnapshotManager.addPhoto**

In the `addPhoto(to:image:)` method, after the snapshot index guard, add:

```swift
guard snapshots[snapshotIndex].photoIDs.count < 5 else {
    Logger.snapshot.warning("Cannot add photo - snapshot already has maximum 5 photos")
    return false
}
```

**Step 5: Add @MainActor to SnapshotManager**

Add `@MainActor` annotation to the class declaration:
```swift
@MainActor
class SnapshotManager: ObservableObject {
```

Remove the `await MainActor.run { }` wrappers in `loadSnapshotsAsync()` and `loadPhotosAsync()` since the class is now MainActor-isolated.

**Step 6: Build and run tests**

---

### Task 10: Commit Group 4 (SensorSnapshot Decoupling)

```bash
git add Triangulum/Models/SensorSnapshot.swift Triangulum/Views/ContentView.swift
git commit -m "refactor: decouple SensorSnapshot from manager classes

Added memberwise initializer for testability, moved manager-based
creation to static factory method. Added 5-photo limit enforcement
in SnapshotManager. Added @MainActor to SnapshotManager.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 11: Move Photo Storage to File System

**Files:**
- Modify: `Triangulum/Models/SensorSnapshot.swift` (SnapshotManager class)

**Step 1: Add file-based photo storage to SnapshotManager**

Replace the UserDefaults-based photo storage with file system storage. The `SnapshotManager` should:

1. Create a `photos` subdirectory in the app's Documents directory
2. Save each photo as `{uuid}.jpg` to the photos directory
3. Load photos from files instead of UserDefaults
4. Keep snapshots in UserDefaults (they're small JSON) but remove photos dict from UserDefaults

Add photo directory setup:
```swift
private static var photosDirectory: URL {
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let photosDir = documentsDir.appendingPathComponent("snapshot_photos", isDirectory: true)
    try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
    return photosDir
}
```

Replace `savePhotos()`:
```swift
private func savePhotoToFile(_ photo: SnapshotPhoto) {
    let fileURL = Self.photosDirectory.appendingPathComponent("\(photo.id).jpg")
    do {
        try photo.imageData.write(to: fileURL, options: .atomic)
    } catch {
        Logger.snapshot.error("Failed to save photo \(photo.id): \(error.localizedDescription)")
        saveError = error
    }
}
```

Replace `loadPhotos()` / `loadPhotosAsync()`:
```swift
private func loadPhotoFromFile(id: UUID) -> SnapshotPhoto? {
    let fileURL = Self.photosDirectory.appendingPathComponent("\(id).jpg")
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return SnapshotPhoto(id: id, imageData: data, timestamp: Date())
}
```

Update `addPhoto()` to save to file instead of dict:
```swift
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
```

Update `removePhoto()` to delete from disk:
```swift
func removePhoto(_ photoID: UUID, from snapshotID: UUID) {
    guard let snapshotIndex = snapshots.firstIndex(where: { $0.id == snapshotID }) else { return }

    // Delete file
    let fileURL = Self.photosDirectory.appendingPathComponent("\(photoID).jpg")
    try? FileManager.default.removeItem(at: fileURL)

    photos.removeValue(forKey: photoID)
    snapshots[snapshotIndex].photoIDs.removeAll { $0 == photoID }
    saveSnapshots()
}
```

Update `getPhotos()` to lazy-load from disk:
```swift
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
```

Update `clearAllSnapshots()` to delete photo files:
```swift
func clearAllSnapshots() {
    // Delete all photo files
    let allPhotoIDs = snapshots.flatMap { $0.photoIDs }
    for photoID in allPhotoIDs {
        let fileURL = Self.photosDirectory.appendingPathComponent("\(photoID).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }
    photos.removeAll()
    snapshots.removeAll()
    saveSnapshots()
}
```

Remove the old `savePhotos()`, `loadPhotos()`, and `loadPhotosAsync()` methods that used UserDefaults for photos. Remove the `photosKey` property. Remove the old `photos` loading from `init()`.

Update both init methods to load photos lazily (don't load all photos at init - load on demand via `getPhotos`).

Add `SnapshotPhoto` init for loading from disk (without UIImage compression):
```swift
init(id: UUID, imageData: Data, timestamp: Date) {
    self.id = id
    self.imageData = imageData
    self.timestamp = timestamp
}
```

**Step 2: Update `clearCorruptedData()` to also clear photo files**

```swift
func clearCorruptedData() {
    Logger.snapshot.warning("Clearing corrupted data by user request")
    userDefaults.removeObject(forKey: snapshotsKey)
    // Clear photo directory
    try? FileManager.default.removeItem(at: Self.photosDirectory)
    try? FileManager.default.createDirectory(at: Self.photosDirectory, withIntermediateDirectories: true)
    snapshots.removeAll()
    photos.removeAll()
    loadError = nil
    saveError = nil
}
```

**Step 3: Update `resetStorage()` for tests**

```swift
func resetStorage() {
    snapshots.removeAll()
    photos.removeAll()
    userDefaults.removeObject(forKey: snapshotsKey)
    // Clear photo directory
    try? FileManager.default.removeItem(at: Self.photosDirectory)
    try? FileManager.default.createDirectory(at: Self.photosDirectory, withIntermediateDirectories: true)
}
```

**Step 4: Build and run tests**

---

### Task 12: Commit Photo Storage Migration

```bash
git add Triangulum/Models/SensorSnapshot.swift
git commit -m "fix: move photo storage from UserDefaults to file system

Photos are now saved as individual JPEG files in Documents/snapshot_photos/
instead of being serialized into UserDefaults. This prevents the ~1MB
UserDefaults limit from being exceeded and improves app launch time.
Photos are lazy-loaded on demand with in-memory caching.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 13: Extract View Components from ContentView

**Files:**
- Create: `Triangulum/Views/Components/SnapshotCreationView.swift`
- Create: `Triangulum/Views/Components/ImagePicker.swift`
- Modify: `Triangulum/Views/ContentView.swift` (remove extracted code)

**Step 1: Create SnapshotCreationView.swift**

Move `SnapshotCreationView` (lines 208-516 of ContentView.swift) to its own file. Add the necessary imports:

```swift
import SwiftUI
import PhotosUI
import UIKit

struct SnapshotCreationView: View {
    // ... (exact copy of existing SnapshotCreationView)
}
```

**Step 2: Create ImagePicker.swift**

Move `ImagePicker` (lines 519-569 of ContentView.swift) to its own file. Fix deprecated API:

```swift
import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    enum SourceType {
        case camera
        case photoLibrary

        var uiImagePickerSourceType: UIImagePickerController.SourceType {
            switch self {
            case .camera: return .camera
            case .photoLibrary: return .photoLibrary
            }
        }
    }

    let sourceType: SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss  // Fixed: was presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType.uiImagePickerSourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()  // Fixed: was presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()  // Fixed: was presentationMode.wrappedValue.dismiss()
        }
    }
}
```

**Step 3: Remove extracted code from ContentView.swift**

Remove everything from line 207 (after `}` closing ContentView) through line 569 (end of ImagePicker), leaving only the `#Preview` at the end.

**Step 4: Pass shared LocationManager to PreferencesView**

In `ContentView.swift`, change:
```swift
NavigationLink(destination: PreferencesView()) {
```
to:
```swift
NavigationLink(destination: PreferencesView(locationManager: locationManager)) {
```

In `PreferencesView.swift`, replace:
```swift
@StateObject private var locationManager = LocationManager()
```
with:
```swift
@ObservedObject var locationManager: LocationManager
```

Update the Preview:
```swift
#Preview {
    PreferencesView(locationManager: LocationManager())
}
```

**Step 5: Build and run tests**

---

### Task 14: Commit Group 5 (View Decomposition)

```bash
git add Triangulum/Views/Components/SnapshotCreationView.swift Triangulum/Views/Components/ImagePicker.swift Triangulum/Views/ContentView.swift Triangulum/Views/PreferencesView.swift
git commit -m "refactor: extract view components and share LocationManager

Moved SnapshotCreationView and ImagePicker into Views/Components/.
Fixed deprecated presentationMode with @Environment dismiss.
PreferencesView now receives shared LocationManager instead of
creating its own instance.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 15: Code Cleanup (Dead Code, @MainActor, SwiftLint, Constants)

**Files:**
- Delete: `Triangulum/Models/Item.swift`
- Modify: `Triangulum/TriangulumApp.swift` (remove `Item.self` from schema)
- Modify: `Triangulum/Managers/WeatherManager.swift` (add `@MainActor`)
- Modify: `Triangulum/Managers/BarometerManager.swift` (add `@MainActor`)
- Modify: `Triangulum/Managers/SatelliteManager.swift` (add `@MainActor`)
- Modify: `Triangulum/Views/MapView.swift` (remove `if true`, add coordinate constant)
- Modify: `.swiftlint.yml` (add `id` to identifier_name exclusions)

**Step 1: Delete Item.swift and remove from schema**

Delete `Triangulum/Models/Item.swift`.

In `TriangulumApp.swift`, change:
```swift
let schema = Schema([
    Item.self,
    SensorReading.self,
    MapTile.self,
    PressureReading.self
])
```
to:
```swift
let schema = Schema([
    SensorReading.self,
    MapTile.self,
    PressureReading.self
])
```

**Step 2: Add @MainActor to ObservableObject classes**

Add `@MainActor` before class declarations for:
- `WeatherManager` in `WeatherManager.swift`
- `SatelliteManager` in `SatelliteManager.swift`

Note: `BarometerManager` already has `@MainActor` on its `historyManager` property. Adding it to the class level is ideal but may require more careful migration of the altimeter callbacks. Only add it if the build succeeds; if not, skip BarometerManager for now.

When adding `@MainActor`, remove any redundant `DispatchQueue.main.async` or `await MainActor.run` wrappers within those classes. The `@MainActor` annotation handles main-thread guarantees.

**Step 3: Remove `if true` in MapView.swift**

In `MapView.swift` line 72, remove the `if true {` line and its closing `}` at line 117. Keep the inner content at the same indentation.

**Step 4: Add default coordinate constant**

In `MapView.swift`, add at the top of the struct:
```swift
private static let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
```

Replace all instances of `CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)` with `Self.defaultCoordinate`.

**Step 5: Add `id` to SwiftLint exclusions**

In `.swiftlint.yml`, add `id` to the `identifier_name.excluded` list (after the existing entries).

Then remove all `// swiftlint:disable:next identifier_name` comments from:
- `Triangulum/Models/SensorSnapshot.swift` (lines 6-7 and 140-141)
- `Triangulum/Models/WidgetOrder.swift` (line 19)
- `Triangulum/Models/Weather.swift` (line 12)

**Step 6: Build and run tests**

---

### Task 16: Commit Group 6 (Code Cleanup)

```bash
git add -A
git commit -m "refactor: remove dead code, add @MainActor, fix SwiftLint config

Removed unused Item.swift and its schema registration. Added @MainActor
to WeatherManager and SatelliteManager. Removed 'if true' dead code and
hardcoded coordinates in MapView. Configured SwiftLint to globally allow
'id' identifier, removing inline disable comments.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 17: Extract Widget Card View Modifier

**Files:**
- Create: `Triangulum/Views/Components/WidgetCardModifier.swift`
- Modify: `Triangulum/Views/BarometerView.swift`
- Modify: `Triangulum/Views/LocationView.swift`
- Modify: `Triangulum/Views/AccelerometerView.swift`
- Modify: `Triangulum/Views/GyroscopeView.swift`
- Modify: `Triangulum/Views/MagnetometerView.swift`
- Modify: `Triangulum/Views/WeatherView.swift`
- Modify: `Triangulum/Views/SatelliteView.swift`

**Step 1: Create WidgetCardModifier**

```swift
import SwiftUI

struct WidgetCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.white, Color.prussianSoft]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.prussianBlue.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func widgetCard() -> some View {
        modifier(WidgetCardModifier())
    }
}
```

**Step 2: Apply to each widget view**

In each widget view, replace the `.padding()` + `.background(LinearGradient(...))` + `.cornerRadius(12)` + `.shadow(...)` chain with `.widgetCard()`.

For example, in `LocationView.swift`, replace lines 110-119:
```swift
.padding()
.background(
    LinearGradient(
        gradient: Gradient(colors: [Color.white, Color.prussianSoft]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
)
.cornerRadius(12)
.shadow(color: Color.prussianBlue.opacity(0.1), radius: 8, x: 0, y: 4)
```
with:
```swift
.widgetCard()
```

Do the same for BarometerView (lines 135-144), AccelerometerView (lines 83-92), GyroscopeView (lines 83-92), MagnetometerView (lines 107-116), WeatherView (lines 221-230).

Note: `SatelliteView` has a slightly different gradient (`.opacity(0.3)` and different shadow). Leave it as-is OR standardize it to match. Recommend standardizing.

Note: `BarometerView` wraps its content in a `Button` - make sure `.widgetCard()` is applied to the VStack that was previously receiving `.padding()`.

**Step 3: Build to verify**

---

### Task 18: Commit Group 7 (Widget Card Styling)

```bash
git add Triangulum/Views/Components/WidgetCardModifier.swift Triangulum/Views/BarometerView.swift Triangulum/Views/LocationView.swift Triangulum/Views/AccelerometerView.swift Triangulum/Views/GyroscopeView.swift Triangulum/Views/MagnetometerView.swift Triangulum/Views/WeatherView.swift Triangulum/Views/SatelliteView.swift
git commit -m "refactor: extract shared widget card styling to WidgetCardModifier

All widget views now use .widgetCard() modifier instead of duplicating
the same padding/gradient/cornerRadius/shadow styling chain.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 19: Add Missing Tests

**Files:**
- Create: `TriangulumTests/WeatherManagerTests.swift`
- Create: `TriangulumTests/KeychainHelperTests.swift`
- Modify: `TriangulumTests/WidgetOrderManagerTests.swift` (expand coverage)

**Step 1: Create WeatherManagerTests**

Test the parsing logic and availability checking. Since we can't easily mock URLSession without a protocol, focus on:
- Initialization state (isInitializing = true)
- Availability checks (no API key → not available)
- Weather response parsing (test Weather model directly)

```swift
import XCTest
@testable import Triangulum

final class WeatherManagerTests: XCTestCase {
    func testInitialState() {
        let locationManager = LocationManager()
        let weatherManager = WeatherManager(locationManager: locationManager)

        XCTAssertTrue(weatherManager.isInitializing)
        XCTAssertFalse(weatherManager.isAvailable)
        XCTAssertNil(weatherManager.currentWeather)
    }

    func testWeatherResponseParsing() throws {
        let json = """
        {
            "weather": [{"id": 800, "main": "Clear", "description": "clear sky", "icon": "01d"}],
            "main": {"temp": 295.15, "feels_like": 297.0, "temp_min": 293.0, "temp_max": 298.0, "pressure": 1013, "humidity": 65},
            "wind": {"speed": 3.5, "deg": 180},
            "visibility": 10000,
            "name": "San Francisco"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        let weather = Weather(from: response)

        XCTAssertEqual(weather.condition, "Clear")
        XCTAssertEqual(weather.humidity, 65)
        XCTAssertEqual(weather.pressure, 1013)
        XCTAssertEqual(weather.locationName, "San Francisco")
        XCTAssertEqual(weather.temperatureCelsius, 295.15 - 273.15, accuracy: 0.01)
    }
}
```

**Step 2: Create KeychainHelperTests**

```swift
import XCTest
@testable import Triangulum

final class KeychainHelperTests: XCTestCase {
    private let testKey = "com.triangulum.test.key"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.shared.delete(forKey: testKey)
    }

    func testStoreAndRetrieveString() {
        let stored = KeychainHelper.shared.store("test_value", forKey: testKey)
        XCTAssertTrue(stored)

        let retrieved = KeychainHelper.shared.retrieveString(forKey: testKey)
        XCTAssertEqual(retrieved, "test_value")
    }

    func testDeleteKey() {
        KeychainHelper.shared.store("to_delete", forKey: testKey)
        let deleted = KeychainHelper.shared.delete(forKey: testKey)
        XCTAssertTrue(deleted)

        let retrieved = KeychainHelper.shared.retrieveString(forKey: testKey)
        XCTAssertNil(retrieved)
    }

    func testRetrieveNonExistentKey() {
        let retrieved = KeychainHelper.shared.retrieveString(forKey: "nonexistent_key_12345")
        XCTAssertNil(retrieved)
    }

    func testExistsCheck() {
        XCTAssertFalse(KeychainHelper.shared.exists(forKey: testKey))
        KeychainHelper.shared.store("exists_test", forKey: testKey)
        XCTAssertTrue(KeychainHelper.shared.exists(forKey: testKey))
    }
}
```

**Step 3: Expand WidgetOrderManagerTests**

```swift
// Add to existing WidgetOrderManagerTests.swift:

func testDefaultOrderContainsAllWidgets() {
    let manager = WidgetOrderManager()
    XCTAssertEqual(manager.widgetOrder.count, WidgetType.allCases.count)
    for widgetType in WidgetType.allCases {
        XCTAssertTrue(manager.widgetOrder.contains(widgetType))
    }
}

func testMoveWidgetPersists() {
    let manager = WidgetOrderManager()
    let originalOrder = manager.widgetOrder
    guard originalOrder.count >= 2 else { return }

    manager.moveWidget(from: IndexSet(integer: 0), to: 2)

    let newManager = WidgetOrderManager()
    XCTAssertEqual(newManager.widgetOrder[0], originalOrder[1])
}
```

**Step 4: Run all tests**

Run: `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum -destination 'platform=iOS Simulator,name=iPhone 16'`

---

### Task 20: Commit Group 9 (Test Coverage)

```bash
git add TriangulumTests/WeatherManagerTests.swift TriangulumTests/KeychainHelperTests.swift TriangulumTests/WidgetOrderManagerTests.swift
git commit -m "test: add tests for WeatherManager, KeychainHelper, WidgetOrderManager

Added weather response parsing tests, Keychain store/retrieve/delete
round-trip tests, and expanded widget order manager coverage.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 21: Final Build Verification

**Step 1: Clean build**

Run: `xcodebuild clean -project Triangulum.xcodeproj -scheme Triangulum`

**Step 2: Full build**

Run: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build`

**Step 3: Full test suite**

Run: `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum -destination 'platform=iOS Simulator,name=iPhone 16'`

**Step 4: SwiftLint**

Run: `swiftlint`

All should pass with no errors.
