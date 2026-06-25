//
//  ContentView.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationManager: LocationManager
    @StateObject private var barometerManager: BarometerManager
    @StateObject private var weatherManager: WeatherManager
    @StateObject private var satelliteManager: SatelliteManager
    @StateObject private var accelerometerManager = AccelerometerManager()
    @StateObject private var gyroscopeManager = GyroscopeManager()
    @StateObject private var magnetometerManager = MagnetometerManager()
    @StateObject private var snapshotManager = SnapshotManager()
    @StateObject private var widgetOrderManager = WidgetOrderManager()
    @State private var showSnapshotDialog = false
    @State private var showEnhancedSnapshotDialog = false
    @State private var currentSnapshot: SensorSnapshot?
    @State private var isEditMode = false

    @AppStorage("showBarometerWidget") private var showBarometerWidget = true
    @AppStorage("showLocationWidget") private var showLocationWidget = true
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showSatelliteWidget") private var showSatelliteWidget = true
    @AppStorage("showAccelerometerWidget") private var showAccelerometerWidget = true
    @AppStorage("showGyroscopeWidget") private var showGyroscopeWidget = true
    @AppStorage("showMagnetometerWidget") private var showMagnetometerWidget = true
    private let isRunningUITests = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let locationManager = LocationManager(skipAvailabilityCheck: isUITesting)
        _locationManager = StateObject(wrappedValue: locationManager)
        _barometerManager = StateObject(wrappedValue: BarometerManager(locationManager: locationManager))
        _weatherManager = StateObject(wrappedValue: WeatherManager(locationManager: locationManager, skipMonitoring: isUITesting))
        _satelliteManager = StateObject(wrappedValue: SatelliteManager(locationManager: locationManager))
    }

    var body: some View {
        NavigationSplitView {
            List {
                // Hero header
                heroHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
                    .deleteDisabled(true)

                // Observatory console — navigation instruments
                consoleStrip
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 14, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
                    .deleteDisabled(true)

                Text("Sensor Array")
                    .celEyebrow()
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 2, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)

                ForEach(widgetOrderManager.widgetOrder, id: \.id) { widgetType in
                    if isWidgetVisible(widgetType) {
                        widgetView(for: widgetType)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .onMove(perform: widgetOrderManager.moveWidget)

                // Capture snapshot button
                Section {
                    captureButton
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .moveDisabled(true)
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.celBackgroundTop.opacity(0.85), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .environment(\.editMode, .constant(isEditMode ? EditMode.active : EditMode.inactive))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("TRIANGULUM")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(Color.celText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isEditMode.toggle()
                        }
                    } label: {
                        Image(systemName: isEditMode ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(isEditMode ? Color.celGreen : Color.celCyan)
                    }
                }
            }
        } detail: {
            // Detail placeholder is transparent so the single shared starfield
            // (applied to the NavigationSplitView below) shows through both the
            // sidebar and detail columns on iPad split view — no second instance.
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.celCyan.opacity(0.6))
                Text("Select an instrument")
                    .celEyebrow()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // ONE shared starfield behind both NavigationSplitView columns, replacing
        // the previous sidebar (.celestialBackground) + detail (StarfieldBackground)
        // duplication that doubled per-frame GPU work on iPad split view.
        .background(StarfieldBackground())
        .onAppear {
            guard !isRunningUITests else { return }

            // Configure pressure history manager with SwiftData context
            barometerManager.configureHistory(with: modelContext)

            barometerManager.startBarometerUpdates()
            locationManager.startLocationUpdates()
            satelliteManager.startUpdates()
            weatherManager.startMonitoring()
            // TODO: Temporarily disabled until privacy permissions are properly configured
            // accelerometerManager.startAccelerometerUpdates()
            // gyroscopeManager.startGyroscopeUpdates()
            // magnetometerManager.startMagnetometerUpdates()
        }
        .onDisappear {
            guard !isRunningUITests else { return }

            barometerManager.stopBarometerUpdates()
            locationManager.stopLocationUpdates()
            satelliteManager.stopUpdates()
            weatherManager.stopMonitoring()
            // accelerometerManager.stopAccelerometerUpdates()
            // gyroscopeManager.stopGyroscopeUpdates()
            // magnetometerManager.stopMagnetometerUpdates()
        }
        .sheet(isPresented: $showEnhancedSnapshotDialog) {
            SnapshotCreationView(
                snapshot: $currentSnapshot,
                snapshotManager: snapshotManager,
                isPresented: $showEnhancedSnapshotDialog
            )
        }
    }

    // MARK: - Widget Management

    private func isWidgetVisible(_ widgetType: WidgetType) -> Bool {
        switch widgetType {
        case .barometer: return showBarometerWidget
        case .location: return showLocationWidget
        case .weather: return showWeatherWidget
        case .satellite: return showSatelliteWidget
        case .accelerometer: return showAccelerometerWidget
        case .gyroscope: return showGyroscopeWidget
        case .magnetometer: return showMagnetometerWidget
        }
    }

    @ViewBuilder
    private func widgetView(for widgetType: WidgetType) -> some View {
        switch widgetType {
        case .barometer:
            BarometerView(barometerManager: barometerManager)
        case .location:
            LocationView(locationManager: locationManager)
        case .weather:
            WeatherView(weatherManager: weatherManager)
        case .satellite:
            SatelliteView(satelliteManager: satelliteManager)
        case .accelerometer:
            AccelerometerView(accelerometerManager: accelerometerManager)
        case .gyroscope:
            GyroscopeView(gyroscopeManager: gyroscopeManager)
        case .magnetometer:
            MagnetometerView(magnetometerManager: magnetometerManager)
        }
    }

    // MARK: - Dashboard chrome

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Triangulum")
                .font(.celDisplay(40, weight: .semibold))
                .foregroundStyle(Color.celText)
                .shadow(color: .celCyan.opacity(0.25), radius: 12)
            Text("Celestial Sensor Array")
                .celEyebrow(.celTextDim)
            HStack(spacing: 10) {
                StatusPill("Live", status: .nominal)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("UT \(Self.utFormatter.string(from: context.date))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.celCyan)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var consoleStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ConsoleTile(icon: "star.fill", label: "Atlas", tint: .celGold) {
                    ConstellationMapView(locationManager: locationManager,
                                         satelliteManager: satelliteManager)
                }
                ConsoleTile(icon: "sun.max.fill", label: "Solar", tint: .celAmber) {
                    SolarEventsView(locationManager: locationManager)
                }
                ConsoleTile(icon: "location.north.fill", label: "Compass", tint: .celCyan) {
                    CompassPageView(locationManager: locationManager)
                }
                ConsoleTile(icon: "level", label: "Level", tint: .celGreen) {
                    LevelPageView(barometerManager: barometerManager)
                }
                ConsoleTile(icon: "map.fill", label: "Tracks", tint: .celViolet) {
                    FootprintView(snapshotManager: snapshotManager)
                }
                ConsoleTile(icon: "gearshape.fill", label: "Config", tint: .celTextDim) {
                    PreferencesView(locationManager: locationManager)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var captureButton: some View {
        Button(action: takeSnapshot) {
            HStack(spacing: 10) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 18, weight: .semibold))
                Text("Capture Snapshot")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color.celBackgroundBottom)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule().fill(CelGradient.cyanGlow)
                    .shadow(color: .celCyan.opacity(0.6), radius: 16, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    private static let utFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func takeSnapshot() {
        let snapshot = SensorSnapshot.capture(
            barometerManager: barometerManager,
            locationManager: locationManager,
            accelerometerManager: accelerometerManager,
            gyroscopeManager: gyroscopeManager,
            magnetometerManager: magnetometerManager,
            weatherManager: weatherManager,
            satelliteManager: satelliteManager
        )
        currentSnapshot = snapshot
        showEnhancedSnapshotDialog = true
    }
}

// MARK: - Console navigation tile

private struct ConsoleTile<Destination: View>: View {
    let icon: String
    let label: String
    var tint: Color = .celCyan
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 9) {
                CelGlyph(systemName: icon, tint: tint, size: 52)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.celTextDim)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
