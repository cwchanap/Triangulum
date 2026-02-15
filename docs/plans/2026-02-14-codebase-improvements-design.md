# Triangulum Codebase Improvements Design

## Context

Comprehensive codebase analysis identified 22 improvements across critical, high, medium, and low priority. The app has no existing users, so breaking changes are acceptable without data migration.

## Implementation Groups

### Group 1: Critical Fixes
- Move photo storage from UserDefaults to file system (Documents directory), keep only UUID references
- Mask API key in PreferencesView alert (show first/last 4 chars only)
- Fix WeatherManager 3-second polling: stop timer after successful fetch, use 15-minute interval for re-checks

### Group 2: Shared CMMotionManager + Sensor Protocol
- Create `MotionService` singleton holding one `CMMotionManager` (Apple requirement)
- Extract shared protocol for sensor managers (start/stop/availability pattern)
- Inject shared instance into Accelerometer/Gyroscope/Magnetometer/Barometer managers

### Group 3: Logging System
- Create `Logger` extensions with categories: weather, location, sensor, satellite, map
- Replace all `print("DEBUG: ...")` statements across all managers with `os.Logger`

### Group 4: SensorSnapshot Decoupling
- Add memberwise initializer taking raw values instead of manager objects
- Create `SensorSnapshot.capture(from:)` factory method for convenience
- Add photo count limit enforcement in SnapshotManager (max 5)

### Group 5: View Decomposition
- Extract `SnapshotCreationView` and `ImagePicker` from ContentView into Views/Components/
- Extract `MapSearchBar` and `MapCacheControls` from MapView
- Share LocationManager with PreferencesView via environment instead of creating new instance

### Group 6: Code Cleanup
- Remove unused `Item.swift` and its schema registration
- Fix string-based error detection in Gyroscope/Magnetometer managers (use CMErrorDomain)
- Add `@MainActor` to all ObservableObject classes publishing UI state
- Replace deprecated `presentationMode` with `@Environment(\.dismiss)`
- Remove `if true` wrapper in MapView
- Extract hardcoded San Francisco coordinates to a constant
- Configure SwiftLint to globally allow `id` identifier

### Group 7: Widget Card Styling
- Create `WidgetCardModifier` view modifier
- Apply to all widget views replacing duplicated card styling code

### Group 8: Persistence Consolidation
- Create SwiftData `SnapshotModel` replacing UserDefaults-based SensorSnapshot storage
- Remove legacy `SensorReading` model
- Keychain for secrets, SwiftData for structured data, UserDefaults only for preferences

### Group 9: Test Coverage
- WeatherManager tests with mocked URLSession
- SnapshotManager persistence round-trip tests
- KeychainHelper store/retrieve/delete cycle tests
- TileCacheManager expiration logic tests

## Decisions
- No data migration needed (no existing users)
- Grouped commits (~9 logical commits)
- Groups ordered by dependency: critical fixes first, tests last
