# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Triangulum is an iOS app built with SwiftUI that monitors multiple sensor types including barometric pressure, GPS location, accelerometer, gyroscope, and magnetometer data. The app provides real-time visualization of sensor readings, allows users to take sensor snapshots with photo attachments, includes configurable widget preferences with multiple map provider options, and features a comprehensive sensor footprint management system.

## Development Commands

### Building and Running
- **Build**: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug` or use Xcode (`⌘+B`)
- **Run**: Use Xcode to run on simulator or device (`⌘+R`)
- **Clean Build**: `xcodebuild clean -project Triangulum.xcodeproj -scheme Triangulum` or Xcode (`⌘+Shift+K`)

### Testing
- **Unit Tests**: `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum -destination 'platform=iOS Simulator,name=iPhone 15'`
- **UI Tests**: `TriangulumUITests` target contains UI automation tests
- **Test in Xcode**: Use Test Navigator or `⌘+U`
- **List available destinations**: `xcodebuild -showdestinations -project Triangulum.xcodeproj -scheme Triangulum`

### Project Information
- **iOS Deployment Target**: 18.5+
- **Schemes**: Triangulum (main scheme)
- **Build Configurations**: Debug, Release
- **Targets**: Triangulum (main app), TriangulumTests, TriangulumUITests

## Architecture

### Core Components

- **App Entry Point**: `TriangulumApp.swift` - Main app structure with SwiftData ModelContainer setup for persistent storage
- **Views**:
  - `ContentView.swift` - Main navigation interface with sensor widget displays and snapshot capture functionality
  - `BarometerView.swift` - Real-time barometer display with pressure, altitude, and attitude data
  - `LocationView.swift` - GPS location display with coordinates and accuracy
  - `AccelerometerView.swift`, `GyroscopeView.swift`, `MagnetometerView.swift` - Additional sensor displays
  - `FootprintView.swift` - Sensor footprint management with pagination and detailed snapshot viewing
  - `PreferencesView.swift` - Widget visibility controls and map provider selection
  - `MapView.swift` - Map interface with provider switching capabilities
  - `OSMMapView.swift` - OpenStreetMap implementation using MKTileOverlay
  - `CompassPageView.swift` - Compass navigation interface
  - `ConstellationMapView.swift` - Star map and celestial navigation display
  - `Views/Components/` - Reusable UI components
- **Data Management**:
  - `BarometerManager.swift` - CoreMotion wrapper for barometric sensor and device attitude
  - `LocationManager.swift` - CoreLocation wrapper with permission handling
  - `AccelerometerManager.swift`, `GyroscopeManager.swift`, `MagnetometerManager.swift` - Additional sensor managers
  - `SnapshotManager` class for comprehensive sensor snapshot and photo management
- **Utilities**:
  - `KeychainHelper.swift` - Secure iOS Keychain wrapper for API key storage
  - `OSMGeocoder.swift` - OpenStreetMap geocoding services
  - `AppleSearchCompleter.swift` - Apple Maps search completion integration
- **Configuration**:
  - `Config.swift` - Centralized configuration management with Keychain integration for API keys
  - `PrivacyInfo.plist` - Privacy manifest for App Store compliance
- **Models**:
  - `SensorReading.swift` - Database model for sensor measurements with SensorType enum (legacy/SwiftData)
  - `SensorSnapshot.swift` - Complete sensor state capture with photo attachment support
  - `Item.swift` - Generic item model (legacy/placeholder)

### Data Flow

1. **Sensor Data Collection**:
   - `BarometerManager` uses CoreMotion's `CMAltimeter` for pressure/altitude and `CMMotionManager` for device attitude
   - `LocationManager` uses CoreLocation's `CLLocationManager` for GPS coordinates and accuracy
   - Additional sensor managers (Accelerometer, Gyroscope, Magnetometer) use CoreMotion for motion data
2. **Real-time Display**: Data flows to views via `@StateObject` and `@ObservedObject` bindings with `@Published` properties
3. **Snapshot System**: Complete sensor state capture creates `SensorSnapshot` objects with all current readings
4. **Data Persistence**: 
   - SwiftData integration for legacy `SensorReading` models
   - UserDefaults-based persistence for `SensorSnapshot` objects and associated photos
   - Photo management through `SnapshotManager` with JPEG compression and UUID-based storage

### Key Technologies
- **SwiftUI**: UI framework with modern declarative patterns including NavigationSplitView
- **SwiftData**: Local persistence layer for legacy sensor readings
- **CoreMotion**: Hardware sensor access (`CMAltimeter`, `CMMotionManager` for all motion sensors)
- **CoreLocation**: GPS and location services with permission handling
- **PhotosUI**: Photo selection and management integration
- **MapKit**: Map display with custom tile overlay support for OpenStreetMap
- **Security Framework**: iOS Keychain Services for secure API key storage
- **UserDefaults**: Primary persistence for snapshot data and preferences
- **iOS 18.5+**: Minimum deployment target (updated from iOS 17.0)

## Project Structure

```
Triangulum/
├── Views/           # SwiftUI view components
│   ├── ContentView.swift          # Main app interface with sensor widgets
│   ├── BarometerView.swift        # Barometer sensor display
│   ├── LocationView.swift         # GPS location display
│   ├── AccelerometerView.swift    # Accelerometer sensor display
│   ├── GyroscopeView.swift        # Gyroscope sensor display
│   ├── MagnetometerView.swift     # Magnetometer sensor display
│   ├── FootprintView.swift        # Sensor snapshot management and viewing
│   ├── PreferencesView.swift      # App preferences and widget controls
│   ├── MapView.swift              # Map interface with provider switching
│   ├── OSMMapView.swift           # OpenStreetMap tile overlay implementation
│   ├── CompassPageView.swift      # Compass navigation interface
│   ├── ConstellationMapView.swift # Star map and celestial navigation
│   └── Components/                # Reusable UI components
├── Models/          # Data models and structures
│   ├── SensorReading.swift        # SwiftData model for sensor measurements (legacy)
│   ├── SensorSnapshot.swift       # Complete sensor state capture with photos
│   └── Item.swift                 # Generic item model (legacy/placeholder)
├── Managers/        # Business logic and hardware interface
│   ├── BarometerManager.swift     # Barometric pressure and altitude sensing
│   ├── LocationManager.swift      # GPS and location services
│   ├── AccelerometerManager.swift # Accelerometer data collection
│   ├── GyroscopeManager.swift     # Gyroscope data collection
│   └── MagnetometerManager.swift  # Magnetometer data collection
├── Utilities/       # Helper classes and utilities
│   ├── KeychainHelper.swift       # Secure iOS Keychain wrapper
│   ├── OSMGeocoder.swift          # OpenStreetMap geocoding services
│   └── AppleSearchCompleter.swift # Apple Maps search completion
├── Extensions/      # SwiftUI extensions and utilities
│   └── Color+Theme.swift          # Prussian Blue color theme definitions
├── Assets.xcassets/ # App icons and visual assets
├── Config.swift     # Centralized configuration with Keychain integration
└── PrivacyInfo.plist # Privacy manifest for App Store compliance
```

## Development Notes

### Architecture Patterns
- Uses modern SwiftUI patterns with `@StateObject`, `@ObservedObject`, and `@Published`
- ObservableObject pattern for sensor managers with real-time data binding
- SwiftData `@Query` for reactive database displays (legacy sensor readings)
- UserDefaults-based persistence with JSON encoding for snapshot data
- NavigationSplitView architecture with detail/sidebar navigation pattern

### Hardware Integration
- Real-time sensor data collection from multiple CoreMotion and CoreLocation sources
- Comprehensive error handling for device compatibility (barometer/GPS availability)
- Permission handling for location services with user prompts
- Device attitude tracking (roll, pitch, yaw) from motion sensors
- Snapshot-based recording system that captures complete sensor state at specific moments
- Photo integration with sensor snapshots using PhotosUI framework

### UI/UX Features
- Custom Prussian Blue color theme defined in `Color+Theme.swift`
- Real-time data visualization with live sensor readings
- Configurable widget visibility through `@AppStorage` preferences
- Snapshot capture with photo attachment workflow
- Paginated sensor footprint viewing with detailed snapshot inspection
- NavigationSplitView with toolbar customization and color theming

### Data Storage Architecture
- **Dual persistence approach**: SwiftData for legacy models, UserDefaults for current snapshot system
- **SensorSnapshot model**: Comprehensive sensor state capture including:
  - Barometer data (pressure, sea level pressure, device attitude)
  - Location data (coordinates, altitude, accuracy)
  - Motion sensor data (accelerometer, gyroscope, magnetometer with magnitude calculations)
  - Photo attachments via UUID-based reference system
- **SnapshotManager**: ObservableObject handling all snapshot CRUD operations with async photo processing
- **Photo storage**: JPEG compression with 0.8 quality, stored as Data in UserDefaults dictionary
- **Error handling**: Graceful fallback with corrupted data cleanup to prevent crashes

### Map Provider Preference
- Map page supports two providers selectable in `Preferences`:
  - `Apple Maps` (default) using SwiftUI `Map`
  - `OpenStreetMap` using an `MKMapView` with `MKTileOverlay` (file: `OSMMapView.swift`)
- Preference is stored in `@AppStorage("mapProvider")` with values `"apple"` or `"osm"`.
- `MapView.swift` switches rendering based on this preference and preserves the center-on-user behavior.

### API Configuration and Security
- **Weather Integration**: App supports OpenWeatherMap API with secure Keychain storage
- **API Key Management**: Users configure their own API keys through Preferences → Weather Configuration
- **Security Implementation**: Uses `KeychainHelper.swift` with iOS Security framework for encrypted storage
- **Development Setup**:
  - Get free OpenWeatherMap API key from https://openweathermap.org/api
  - Configure through app Preferences (no hardcoded keys in codebase)
  - Environment variable support: `OPENWEATHER_API_KEY` for CI/development
- **App Store Compliance**: Privacy manifest (`PrivacyInfo.plist`) included for App Store requirements

### Sensor Management Notes
- Some sensors (accelerometer, gyroscope, magnetometer) are temporarily disabled in `ContentView.swift:102-105` pending privacy permission configuration
- All sensor managers follow the same pattern: start/stop methods, @Published properties for real-time updates
- CoreMotion sensors provide both individual axis values and calculated magnitude for comprehensive data capture
