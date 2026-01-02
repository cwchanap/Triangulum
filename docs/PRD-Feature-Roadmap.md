# Product Requirements Document: Triangulum Feature Roadmap

**Document Version:** 1.0
**Created:** December 30, 2024
**Status:** Draft
**Product:** Triangulum iOS App

---

## Executive Summary

Triangulum is an iOS sensor monitoring application that provides real-time visualization of barometric pressure, GPS location, device motion sensors, weather data, and astronomical information. This PRD outlines proposed feature enhancements to extend the app's capabilities in data visualization, outdoor navigation, alerting, astronomy, and data management.

---

## Current State Analysis

### Existing Capabilities

| Category | Features |
|----------|----------|
| **Sensors** | Barometer, GPS, Accelerometer*, Gyroscope*, Magnetometer* |
| **Weather** | OpenWeatherMap integration with temperature, humidity, wind, conditions |
| **Astronomy** | Real-time star map, Sun/Moon positions, moon phases, Milky Way rendering |
| **Maps** | Apple Maps & OpenStreetMap with offline tile caching |
| **Data Capture** | Sensor snapshots with photo attachments (up to 5 per snapshot) |
| **Customization** | Widget visibility toggles, drag-to-reorder, map provider selection |

*\*Motion sensors currently disabled pending privacy permission configuration*

### Technical Foundation

- **Platform:** iOS 18.5+
- **Architecture:** SwiftUI with MVVM pattern using ObservableObject managers
- **Persistence:** SwiftData (map tiles), UserDefaults (snapshots/preferences), Keychain (API keys)
- **Dependencies:** Native Apple frameworks only (no third-party dependencies)

---

## Proposed Features

### Category 1: Data Visualization & Analytics

#### F1.1 Real-Time Sensor Graphs

**Priority:** High
**Effort:** Medium

**Description:**
Add historical trend visualization for sensor data using interactive line charts.

**User Stories:**
- As a hiker, I want to see altitude changes over time to understand my elevation profile
- As a weather enthusiast, I want to track pressure trends to predict incoming weather systems
- As a data analyst, I want to visualize sensor patterns over different time periods

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F1.1.1 | Display line chart for barometric pressure over time | Must Have |
| F1.1.2 | Display line chart for altitude over time | Must Have |
| F1.1.3 | Support multiple time ranges (1hr, 6hr, 24hr, 7d) | Must Have |
| F1.1.4 | Show min/max/average statistics for selected period | Should Have |
| F1.1.5 | Enable pinch-to-zoom on chart for detailed inspection | Should Have |
| F1.1.6 | Support landscape orientation for full-screen charts | Could Have |

**Technical Approach:**
- Use Swift Charts framework (iOS 16+)
- Store rolling buffer of readings in sensor managers (configurable retention)
- New `SensorHistoryView.swift` with chart components
- Background task for periodic sampling when app is inactive

**Acceptance Criteria:**
- [ ] Charts render smoothly with 60fps scrolling
- [ ] Data persists across app launches
- [ ] Memory usage remains under 50MB for 7-day retention

---

#### F1.2 Pressure Trend Predictions

**Priority:** Medium
**Effort:** Low

**Description:**
Leverage barometric pressure rate-of-change to provide simple weather predictions.

**User Stories:**
- As an outdoor enthusiast, I want to know if weather is improving or deteriorating
- As a casual user, I want a quick forecast indicator without checking weather apps

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F1.2.1 | Calculate pressure change rate (hPa/hour) | Must Have |
| F1.2.2 | Display trend indicator (rising/falling/steady) with arrow icon | Must Have |
| F1.2.3 | Show simple prediction text based on trend | Should Have |
| F1.2.4 | Integrate trend indicator into barometer widget | Must Have |

**Prediction Logic:**
| Pressure Change | Trend | Prediction |
|-----------------|-------|------------|
| > +1.0 hPa/hr | Rising Fast | "Clearing, fair weather ahead" |
| +0.5 to +1.0 hPa/hr | Rising | "Weather improving" |
| -0.5 to +0.5 hPa/hr | Steady | "Stable conditions" |
| -1.0 to -0.5 hPa/hr | Falling | "Weather deteriorating" |
| < -1.0 hPa/hr | Falling Fast | "Storm approaching" |

**Acceptance Criteria:**
- [ ] Trend updates every 60 seconds
- [ ] Requires minimum 30 minutes of data before showing prediction
- [ ] Prediction text localizable for internationalization

---

#### F1.3 Snapshot Comparison View

**Priority:** Low
**Effort:** Medium

**Description:**
Enable side-by-side comparison of two sensor snapshots to analyze differences.

**User Stories:**
- As a researcher, I want to compare sensor readings between two locations
- As a traveler, I want to see how conditions changed between trip start and end

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F1.3.1 | Select two snapshots from footprint list | Must Have |
| F1.3.2 | Display side-by-side sensor values | Must Have |
| F1.3.3 | Calculate and display delta for numeric values | Must Have |
| F1.3.4 | Show map with both locations marked | Should Have |
| F1.3.5 | Display distance between snapshot locations | Should Have |

---

### Category 2: Navigation & Outdoor Features

#### F2.1 Track Recording

**Priority:** High
**Effort:** High

**Description:**
Record GPS paths with associated sensor data for route tracking and analysis.

**User Stories:**
- As a hiker, I want to record my trail and review it later
- As a cyclist, I want to export my route to share with others
- As an analyst, I want to correlate altitude changes with my recorded path

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F2.1.1 | Start/stop track recording with visible indicator | Must Have |
| F2.1.2 | Record GPS coordinates at configurable intervals (1s-30s) | Must Have |
| F2.1.3 | Store associated sensor data (altitude, pressure) with each point | Must Have |
| F2.1.4 | Display recorded track on map as polyline | Must Have |
| F2.1.5 | Show altitude profile graph for recorded track | Should Have |
| F2.1.6 | Calculate total distance, elevation gain/loss | Should Have |
| F2.1.7 | Export track as GPX file | Must Have |
| F2.1.8 | Support background location updates during recording | Must Have |
| F2.1.9 | Pause/resume track recording | Should Have |
| F2.1.10 | Name and tag recorded tracks | Should Have |

**Technical Approach:**
- New `TrackManager.swift` with background location capabilities
- SwiftData model `Track` with relationship to `TrackPoint` entities
- GPX export using XMLDocument or custom string builder
- Background modes: Location updates, Background processing

**Privacy Considerations:**
- Clear indication when background location is active
- Battery usage warning for high-frequency sampling
- Option to reduce accuracy for battery savings

**Acceptance Criteria:**
- [ ] Track recording continues when app is backgrounded
- [ ] Battery drain < 10% per hour during active recording
- [ ] GPX export compatible with Strava, Garmin Connect, AllTrails

---

#### F2.2 Waypoint System

**Priority:** Medium
**Effort:** Medium

**Description:**
Save points of interest and navigate to them using compass bearing and distance.

**User Stories:**
- As a geocacher, I want to save and navigate to cache locations
- As a hiker, I want to mark trailhead parking for return navigation
- As an explorer, I want to save interesting locations for future visits

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F2.2.1 | Save current location as waypoint with custom name | Must Have |
| F2.2.2 | Save arbitrary coordinates as waypoint | Must Have |
| F2.2.3 | Display list of saved waypoints with distance from current location | Must Have |
| F2.2.4 | Show bearing to selected waypoint on compass | Must Have |
| F2.2.5 | Display waypoints on map view | Should Have |
| F2.2.6 | Import waypoints from GPX file | Could Have |
| F2.2.7 | Categorize waypoints with icons/colors | Could Have |

**Technical Approach:**
- New SwiftData model `Waypoint` with name, coordinates, category, icon
- Extend `CompassPageView` with waypoint bearing indicator
- Haversine formula for distance/bearing calculations

---

#### F2.3 Sunrise/Sunset & Golden Hour

**Priority:** Medium
**Effort:** Low

**Description:**
Display solar event times and photography-relevant lighting periods.

**User Stories:**
- As a photographer, I want to know golden hour timing for optimal lighting
- As an outdoor planner, I want to know daylight hours for trip planning
- As a stargazer, I want to know when astronomical twilight begins

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F2.3.1 | Calculate and display sunrise/sunset times | Must Have |
| F2.3.2 | Display civil, nautical, and astronomical twilight times | Should Have |
| F2.3.3 | Show golden hour start/end times | Must Have |
| F2.3.4 | Show blue hour timing | Should Have |
| F2.3.5 | Countdown timer to next solar event | Should Have |
| F2.3.6 | Integrate with constellation map view | Should Have |

**Technical Approach:**
- Extend existing `Astronomer` struct with sunrise/sunset calculations
- Use standard solar position algorithms (already partially implemented)
- New `SolarEventsView.swift` or integrate into existing astronomy views

---

### Category 3: Alerts & Monitoring

#### F3.1 Threshold Alerts

**Priority:** Medium
**Effort:** Medium

**Description:**
Configurable notifications when sensor values cross user-defined thresholds.

**User Stories:**
- As a weather watcher, I want alerts when pressure drops rapidly (storm warning)
- As a mountaineer, I want notification when reaching target altitude
- As a health-conscious user, I want alerts for extreme temperature conditions

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F3.1.1 | Configure pressure high/low thresholds | Must Have |
| F3.1.2 | Configure altitude target threshold | Must Have |
| F3.1.3 | Configure temperature high/low thresholds | Should Have |
| F3.1.4 | Enable/disable individual alerts | Must Have |
| F3.1.5 | Choose alert sound/vibration pattern | Could Have |
| F3.1.6 | View alert history | Should Have |
| F3.1.7 | Cooldown period to prevent repeated alerts | Must Have |

**Technical Approach:**
- Use `UNUserNotificationCenter` for local notifications
- New `AlertManager.swift` monitoring sensor values
- Preferences UI for threshold configuration
- Background app refresh for monitoring when app inactive

**Acceptance Criteria:**
- [ ] Alerts trigger within 5 seconds of threshold crossing
- [ ] Cooldown prevents duplicate alerts within configured period
- [ ] Alerts work when app is backgrounded (within iOS limitations)

---

#### F3.2 Background Sensor Logging

**Priority:** Low
**Effort:** High

**Description:**
Passive data collection mode for long-term sensor monitoring.

**User Stories:**
- As a researcher, I want to log overnight pressure changes
- As a traveler, I want continuous recording during long trips
- As a sleep analyst, I want environmental data during sleep

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F3.2.1 | Start/stop background logging session | Must Have |
| F3.2.2 | Configure sample interval (1min - 1hr) | Must Have |
| F3.2.3 | Log pressure, altitude, temperature, humidity | Must Have |
| F3.2.4 | Display estimated battery impact | Should Have |
| F3.2.5 | Auto-stop after configurable duration | Should Have |
| F3.2.6 | Export logged data as CSV | Must Have |

**Technical Approach:**
- Background modes: Background fetch, Background processing
- Efficient storage using binary format or compressed JSON
- BGTaskScheduler for periodic wake-ups

**Constraints:**
- iOS background execution limits apply
- Battery usage must be clearly communicated to users

---

### Category 4: Astronomy Enhancements

#### F4.1 Satellite/ISS Tracker

**Priority:** Low
**Effort:** High

**Description:**
Track artificial satellites including the International Space Station.

**User Stories:**
- As a space enthusiast, I want to know when ISS is visible from my location
- As a stargazer, I want to identify satellites I see in the sky
- As an educator, I want to show students real-time satellite positions

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F4.1.1 | Display ISS position on constellation map | Must Have |
| F4.1.2 | Calculate ISS pass predictions for current location | Must Have |
| F4.1.3 | Show pass details (start time, max elevation, duration) | Must Have |
| F4.1.4 | Push notification for upcoming bright passes | Should Have |
| F4.1.5 | Track additional satellites (Starlink, Hubble) | Could Have |
| F4.1.6 | Auto-update TLE data from CelesTrak | Should Have |

**Technical Approach:**
- Implement SGP4/SDP4 orbit propagation algorithm
- Fetch TLE data from CelesTrak API (https://celestrak.org)
- New `SatelliteManager.swift` for orbit calculations
- Cache TLE data with 24-hour refresh

**Data Sources:**
- CelesTrak: Free TLE data for common satellites
- Space-Track.org: Comprehensive catalog (requires free registration)

---

#### F4.2 Planet Positions

**Priority:** Medium
**Effort:** Medium

**Description:**
Display major planets on the constellation map with visibility information.

**User Stories:**
- As an amateur astronomer, I want to locate planets in the night sky
- As a casual observer, I want to know which bright "star" is actually a planet
- As a planner, I want to know optimal viewing times for planets

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F4.2.1 | Calculate positions for Mercury, Venus, Mars, Jupiter, Saturn | Must Have |
| F4.2.2 | Display planets on constellation map with distinct icons | Must Have |
| F4.2.3 | Show planet rise/set times | Should Have |
| F4.2.4 | Display current magnitude (brightness) | Should Have |
| F4.2.5 | Show planetary phase for Mercury/Venus | Could Have |
| F4.2.6 | Include Uranus and Neptune | Could Have |

**Technical Approach:**
- Implement simplified VSOP87 or use orbital elements method
- Extend `Astronomer` struct with planetary calculations
- Render planets with appropriate colors and size based on magnitude

---

#### F4.3 Eclipse Predictor

**Priority:** Low
**Effort:** High

**Description:**
Predict solar and lunar eclipses visible from the user's location.

**User Stories:**
- As an eclipse chaser, I want to know upcoming eclipses visible from my area
- As an educator, I want to plan viewing events for students
- As a photographer, I want advance notice for eclipse photography planning

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F4.3.1 | Calculate next lunar eclipse visible from location | Must Have |
| F4.3.2 | Calculate next solar eclipse visible from location | Must Have |
| F4.3.3 | Display eclipse type (total, partial, annular, penumbral) | Must Have |
| F4.3.4 | Show eclipse timeline (start, maximum, end) | Should Have |
| F4.3.5 | Display path of totality on map for solar eclipses | Could Have |
| F4.3.6 | Calendar view of upcoming eclipses | Should Have |

---

### Category 5: Data Management & Export

#### F5.1 Export Snapshots

**Priority:** High
**Effort:** Low

**Description:**
Export sensor snapshot data in multiple formats for analysis and sharing.

**User Stories:**
- As a researcher, I want to export data to CSV for spreadsheet analysis
- As a developer, I want JSON export for integration with other tools
- As a user, I want to share a formatted report of my sensor readings

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F5.1.1 | Export single snapshot as JSON | Must Have |
| F5.1.2 | Export single snapshot as CSV | Must Have |
| F5.1.3 | Export all snapshots as JSON array | Must Have |
| F5.1.4 | Export all snapshots as CSV file | Must Have |
| F5.1.5 | Generate PDF report with map and photos | Should Have |
| F5.1.6 | Share via iOS Share Sheet | Must Have |
| F5.1.7 | Include/exclude photos in export | Should Have |

**Technical Approach:**
- Extend `SensorSnapshot` with `Encodable` conformance (if not already)
- New `ExportManager.swift` for format generation
- Use `UIActivityViewController` for sharing
- PDF generation using UIKit drawing or PDFKit

**Export Schema (JSON):**
```json
{
  "id": "uuid",
  "timestamp": "ISO8601",
  "location": {
    "latitude": 0.0,
    "longitude": 0.0,
    "altitude": 0.0,
    "accuracy": 0.0
  },
  "barometer": {
    "pressure": 0.0,
    "seaLevelPressure": 0.0,
    "attitude": { "roll": 0.0, "pitch": 0.0, "yaw": 0.0 }
  },
  "weather": {
    "temperature": 0.0,
    "humidity": 0,
    "conditions": "string"
  },
  "motion": {
    "accelerometer": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "gyroscope": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "magnetometer": { "x": 0.0, "y": 0.0, "z": 0.0 }
  },
  "photoCount": 0
}
```

**Acceptance Criteria:**
- [ ] CSV importable into Excel, Google Sheets, Numbers
- [ ] JSON valid and parseable by standard tools
- [ ] Share sheet presents relevant apps (Mail, Files, AirDrop)

---

#### F5.2 iCloud Sync

**Priority:** Low
**Effort:** High

**Description:**
Synchronize snapshots across devices using iCloud.

**User Stories:**
- As a multi-device user, I want my snapshots available on all my devices
- As a cautious user, I want automatic backup of my data
- As a user upgrading phones, I want seamless data migration

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F5.2.1 | Sync snapshots to iCloud | Must Have |
| F5.2.2 | Sync photos associated with snapshots | Must Have |
| F5.2.3 | Handle conflict resolution (latest wins) | Must Have |
| F5.2.4 | Show sync status indicator | Should Have |
| F5.2.5 | Option to disable iCloud sync | Must Have |
| F5.2.6 | Sync widget preferences | Could Have |

**Technical Approach:**
- Migrate from UserDefaults to CloudKit or NSUbiquitousKeyValueStore
- Consider SwiftData with CloudKit integration
- Handle offline scenarios gracefully

**Privacy Considerations:**
- Clear disclosure that data is stored in user's iCloud
- Option to use local-only storage

---

#### F5.3 Siri Shortcuts Integration

**Priority:** Medium
**Effort:** Medium

**Description:**
Enable voice commands and automation through Siri and Shortcuts app.

**User Stories:**
- As a hands-free user, I want to take snapshots via voice command
- As an automation enthusiast, I want to trigger snapshots from Shortcuts
- As a quick-access user, I want to ask Siri for current readings

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F5.3.1 | "Take sensor snapshot" intent | Must Have |
| F5.3.2 | "Get current pressure" intent | Should Have |
| F5.3.3 | "Get current location" intent | Should Have |
| F5.3.4 | "Open compass" intent | Should Have |
| F5.3.5 | Donate intents for Siri suggestions | Should Have |
| F5.3.6 | Shortcuts app integration | Must Have |

**Technical Approach:**
- Implement App Intents framework (iOS 16+)
- Create `TriangulumShortcuts.swift` with intent definitions
- Return structured results for Shortcuts automation

---

### Category 6: Motion Sensor Features

#### F6.1 Enable Motion Sensors

**Priority:** High
**Effort:** Low

**Description:**
Complete the privacy permission configuration to enable currently disabled motion sensors.

**User Stories:**
- As a user, I want access to all advertised sensor capabilities
- As a motion analyst, I want accelerometer and gyroscope data

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F6.1.1 | Add Motion & Fitness usage description to Info.plist | Must Have |
| F6.1.2 | Implement permission request flow | Must Have |
| F6.1.3 | Handle permission denied gracefully | Must Have |
| F6.1.4 | Uncomment sensor start calls in ContentView | Must Have |

**Technical Approach:**
- Add `NSMotionUsageDescription` to Info.plist
- Request `CMMotionActivityManager` authorization
- Update ContentView.swift lines 126-129

**Acceptance Criteria:**
- [ ] Permission prompt appears on first launch
- [ ] Sensors function after permission granted
- [ ] Graceful degradation if permission denied

---

#### F6.2 Step Counter & Pedometer

**Priority:** Medium
**Effort:** Low

**Description:**
Display step count and walking/running distance using CoreMotion pedometer.

**User Stories:**
- As a fitness-conscious user, I want to see my daily steps
- As a hiker, I want to know distance walked during my trek

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F6.2.1 | Display today's step count | Must Have |
| F6.2.2 | Display estimated distance walked | Must Have |
| F6.2.3 | Show floors ascended/descended | Should Have |
| F6.2.4 | New pedometer widget | Must Have |
| F6.2.5 | Include step data in snapshots | Should Have |

**Technical Approach:**
- Use `CMPedometer` from CoreMotion
- New `PedometerManager.swift` following existing manager pattern
- Query historical data for daily totals

---

#### F6.3 Device Level Indicator

**Priority:** Low
**Effort:** Low

**Description:**
Bubble level functionality using accelerometer data.

**User Stories:**
- As a DIY enthusiast, I want to check if surfaces are level
- As a photographer, I want to ensure my camera is horizontal

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F6.3.1 | Display 2D bubble level interface | Must Have |
| F6.3.2 | Show numeric roll and pitch values | Should Have |
| F6.3.3 | Haptic feedback when level | Should Have |
| F6.3.4 | Calibration option for surface offset | Could Have |

---

### Category 7: UX Improvements

#### F7.1 Home Screen Widgets

**Priority:** Medium
**Effort:** Medium

**Description:**
iOS Home Screen widgets for glanceable sensor information.

**User Stories:**
- As a frequent user, I want to see pressure without opening the app
- As a weather watcher, I want quick access to current conditions
- As a navigator, I want compass heading on my home screen

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F7.1.1 | Small widget showing current pressure | Must Have |
| F7.1.2 | Medium widget showing pressure + temperature | Should Have |
| F7.1.3 | Small compass widget | Should Have |
| F7.1.4 | Widget configuration options | Should Have |
| F7.1.5 | Support for StandBy mode (iOS 17+) | Could Have |

**Technical Approach:**
- Create WidgetKit extension target
- Share data via App Groups
- Use TimelineProvider for updates
- Consider Live Activities for real-time data

---

#### F7.2 Theme System

**Priority:** Low
**Effort:** Medium

**Description:**
Comprehensive theming with light/dark mode support beyond night vision.

**User Stories:**
- As a user, I want the app to match my system appearance preference
- As a night user, I want a dark theme that's easy on the eyes
- As a customization enthusiast, I want to choose my color scheme

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F7.2.1 | Support system light/dark mode | Must Have |
| F7.2.2 | Manual theme override option | Should Have |
| F7.2.3 | Consistent theming across all views | Must Have |
| F7.2.4 | Custom accent color selection | Could Have |

---

#### F7.3 Haptic Feedback

**Priority:** Low
**Effort:** Low

**Description:**
Tactile feedback for enhanced interaction experience.

**User Stories:**
- As a user, I want physical feedback when taking snapshots
- As a navigator, I want to feel compass clicks at cardinal points

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| F7.3.1 | Haptic on snapshot capture | Must Have |
| F7.3.2 | Haptic on compass cardinal directions | Should Have |
| F7.3.3 | Haptic on widget reorder | Should Have |
| F7.3.4 | Option to disable haptics | Must Have |

**Technical Approach:**
- Use `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`
- Create `HapticManager` utility for consistent feedback patterns

---

## Implementation Prioritization

### Phase 1: Foundation (Recommended First)

| Feature | ID | Priority | Effort | Rationale |
|---------|-----|----------|--------|-----------|
| Enable Motion Sensors | F6.1 | High | Low | Unlocks existing functionality |
| Export Snapshots | F5.1 | High | Low | High user value, low complexity |
| Real-Time Sensor Graphs | F1.1 | High | Medium | Core data visualization |
| Pressure Trend Predictions | F1.2 | Medium | Low | Enhances existing barometer |

### Phase 2: Navigation & Outdoor

| Feature | ID | Priority | Effort | Rationale |
|---------|-----|----------|--------|-----------|
| Sunrise/Sunset & Golden Hour | F2.3 | Medium | Low | Extends existing astronomy |
| Waypoint System | F2.2 | Medium | Medium | Useful for outdoor users |
| Track Recording | F2.1 | High | High | Major feature addition |

### Phase 3: Monitoring & Alerts

| Feature | ID | Priority | Effort | Rationale |
|---------|-----|----------|--------|-----------|
| Threshold Alerts | F3.1 | Medium | Medium | Proactive monitoring |
| Step Counter | F6.2 | Medium | Low | Popular fitness feature |
| Home Screen Widgets | F7.1 | Medium | Medium | Increased engagement |

### Phase 4: Advanced Features

| Feature | ID | Priority | Effort | Rationale |
|---------|-----|----------|--------|-----------|
| Planet Positions | F4.2 | Medium | Medium | Astronomy enhancement |
| Siri Shortcuts | F5.3 | Medium | Medium | Convenience feature |
| Device Level | F6.3 | Low | Low | Utility feature |

### Phase 5: Long-term

| Feature | ID | Priority | Effort | Rationale |
|---------|-----|----------|--------|-----------|
| Satellite/ISS Tracker | F4.1 | Low | High | Niche but valuable |
| Eclipse Predictor | F4.3 | Low | High | Specialized astronomy |
| iCloud Sync | F5.2 | Low | High | Multi-device support |
| Background Logging | F3.2 | Low | High | Research use case |

---

## Technical Considerations

### Privacy Requirements

| Feature | Required Permissions |
|---------|---------------------|
| Motion Sensors | NSMotionUsageDescription |
| Track Recording | Always location access, Background modes |
| Background Logging | Background App Refresh |
| Notifications | UNUserNotificationCenter authorization |

### New Files to Create

```
Triangulum/
├── Views/
│   ├── SensorHistoryView.swift      # F1.1
│   ├── SolarEventsView.swift        # F2.3
│   ├── WaypointListView.swift       # F2.2
│   ├── TrackRecordingView.swift     # F2.1
│   ├── AlertConfigView.swift        # F3.1
│   └── LevelView.swift              # F6.3
├── Managers/
│   ├── TrackManager.swift           # F2.1
│   ├── WaypointManager.swift        # F2.2
│   ├── AlertManager.swift           # F3.1
│   ├── PedometerManager.swift       # F6.2
│   └── SatelliteManager.swift       # F4.1
├── Models/
│   ├── Track.swift                  # F2.1
│   ├── Waypoint.swift               # F2.2
│   └── Alert.swift                  # F3.1
├── Utilities/
│   ├── ExportManager.swift          # F5.1
│   └── HapticManager.swift          # F7.3
└── TriangulumWidgets/               # F7.1 (new target)
    ├── PressureWidget.swift
    └── CompassWidget.swift
```

### Framework Dependencies

| Feature | Framework | iOS Version |
|---------|-----------|-------------|
| Sensor Graphs | Swift Charts | iOS 16+ |
| Home Widgets | WidgetKit | iOS 14+ |
| Siri Shortcuts | App Intents | iOS 16+ |
| Background Tasks | BackgroundTasks | iOS 13+ |
| Notifications | UserNotifications | iOS 10+ |

---

## Success Metrics

| Metric | Target | Feature |
|--------|--------|---------|
| Snapshot exports per month | 100+ | F5.1 |
| Track recordings created | 50+ per month | F2.1 |
| Widget installations | 30% of users | F7.1 |
| Alert configurations | 40% of users | F3.1 |
| Graph view engagement | 2+ min avg session | F1.1 |

---

## Open Questions

1. **Data Retention Policy:** How long should sensor history be retained for graphs?
2. **Export Formats:** Are there additional formats beyond CSV/JSON that users need?
3. **Satellite Data:** Should satellite tracking require internet or support offline TLE caching?
4. **Widget Refresh Rate:** What's the acceptable battery trade-off for widget updates?
5. **Track Recording Battery:** What's the maximum acceptable battery drain during recording?

---

## Appendix

### A. Competitive Analysis

| App | Strengths | Gaps Triangulum Could Fill |
|-----|-----------|---------------------------|
| Barometer Plus | Simple, focused | Lacks multi-sensor integration |
| Sky Guide | Rich astronomy | No sensor data capture |
| Compass Pro | Navigation focused | Limited data export |
| Altimeter GPS | Altitude tracking | No weather integration |

### B. User Personas

**Outdoor Enthusiast (Primary)**
- Hikes, camps, explores
- Values: Reliability, battery efficiency, offline capability
- Key features: Track recording, waypoints, pressure predictions

**Amateur Astronomer (Secondary)**
- Night sky observation
- Values: Accuracy, comprehensive data
- Key features: Planet positions, satellite tracking, eclipses

**Data Analyst (Tertiary)**
- Research, environmental monitoring
- Values: Data export, logging, precision
- Key features: CSV/JSON export, background logging, graphs

---

*Document maintained by: Development Team*
*Next review date: Q1 2025*
