# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Triangulum is an iOS app built with SwiftUI that monitors sensor data, specifically barometric pressure readings. The app provides real-time visualization of barometer data and allows users to record sensor readings to a local database.

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
  - `ContentView.swift` - Main navigation interface with sensor readings list
  - `BarometerView.swift` - Real-time barometer display component
- **Data Management**: 
  - `BarometerManager.swift` - CoreMotion wrapper for barometric sensor access
  - SwiftData models for persistent storage
- **Models**:
  - `SensorReading.swift` - Database model for sensor measurements with SensorType enum
  - `Item.swift` - Generic item model (legacy/placeholder)

### Data Flow

1. `BarometerManager` uses CoreMotion's `CMAltimeter` to access barometric pressure
2. Real-time data flows to `BarometerView` via `@ObservedObject`
3. Recording functionality saves readings to SwiftData via `SensorReading` model
4. `ContentView` displays stored readings with SwiftData `@Query`

### Key Technologies
- **SwiftUI**: UI framework
- **SwiftData**: Local persistence layer
- **CoreMotion**: Hardware sensor access (specifically `CMAltimeter`)
- **iOS 18.5+**: Minimum deployment target

## Project Structure

```
Triangulum/
├── Views/           # SwiftUI view components
├── Models/          # SwiftData models and data structures  
├── Managers/        # Business logic and hardware interface
└── Assets.xcassets/ # App icons and visual assets
```

## Development Notes

- Uses modern SwiftUI patterns with `@StateObject`, `@ObservedObject`, and `@Published`
- Timer-based recording system for periodic sensor data collection
- Error handling for device compatibility (barometer not available on all devices)
- SwiftData queries sorted by timestamp for chronological display