# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Triangulum is an iOS app built with SwiftUI that monitors multiple sensor types including barometric pressure and GPS location data. The app provides real-time visualization of sensor readings and allows users to record measurements to a local database with location context.

## Development Commands

### Building and Running
- **Build**: Use Xcode to build the project (`⌘+B`)
- **Run**: Use Xcode to run on simulator or device (`⌘+R`)
- **Test**: Use Xcode to run unit tests (`⌘+U`)

### Testing
- **Unit Tests**: `TriangulumTests` target contains unit tests
- **UI Tests**: `TriangulumUITests` target contains UI automation tests
- Run tests using Xcode Test Navigator or `⌘+U`

## Architecture

### Core Components

- **App Entry Point**: `TriangulumApp.swift` - Main app structure with SwiftData ModelContainer setup
- **Views**: 
  - `ContentView.swift` - Main navigation interface with sensor readings list and recording controls
  - `BarometerView.swift` - Real-time barometer display with pressure, altitude, and attitude data
  - `LocationView.swift` - GPS location display with coordinates and accuracy
- **Data Management**: 
  - `BarometerManager.swift` - CoreMotion wrapper for barometric sensor and device attitude
  - `LocationManager.swift` - CoreLocation wrapper with permission handling
  - SwiftData models for persistent storage
- **Models**:
  - `SensorReading.swift` - Database model for sensor measurements with SensorType enum
  - `Item.swift` - Generic item model (legacy/placeholder)

### Data Flow

1. **Sensor Data Collection**:
   - `BarometerManager` uses CoreMotion's `CMAltimeter` for pressure/altitude and `CMMotionManager` for device attitude
   - `LocationManager` uses CoreLocation's `CLLocationManager` for GPS coordinates and accuracy
2. **Real-time Display**: Data flows to views via `@ObservedObject` bindings
3. **Recording System**: Timer-based recording saves both barometer and GPS readings to SwiftData
4. **Data Persistence**: `ContentView` displays stored readings via SwiftData `@Query` sorted by timestamp

### Key Technologies
- **SwiftUI**: UI framework with modern declarative patterns
- **SwiftData**: Local persistence layer for sensor readings
- **CoreMotion**: Hardware sensor access (`CMAltimeter` for pressure, `CMMotionManager` for attitude)
- **CoreLocation**: GPS and location services with permission handling
- **iOS 17.0+**: Minimum deployment target (supports SwiftData)

## Project Structure

```
Triangulum/
├── Views/           # SwiftUI view components (ContentView, BarometerView, LocationView)
├── Models/          # SwiftData models and data structures (SensorReading, Item)
├── Managers/        # Business logic and hardware interface (BarometerManager, LocationManager)
├── Extensions/      # SwiftUI extensions (Color+Theme for Prussian Blue palette)
└── Assets.xcassets/ # App icons and visual assets
```

## Development Notes

### Architecture Patterns
- Uses modern SwiftUI patterns with `@StateObject`, `@ObservedObject`, and `@Published`
- ObservableObject pattern for sensor managers with real-time data binding
- SwiftData `@Query` for reactive database displays sorted by timestamp

### Hardware Integration
- Timer-based recording system for periodic multi-sensor data collection
- Comprehensive error handling for device compatibility (barometer/GPS availability)
- Permission handling for location services with user prompts
- Device attitude tracking (roll, pitch, yaw) from motion sensors

### UI/UX Features
- Custom Prussian Blue color theme defined in `Color+Theme.swift`
- Real-time data visualization with progress indicators
- Start/Stop recording controls with visual state feedback
- Location context included in all sensor readings