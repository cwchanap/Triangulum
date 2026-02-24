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
                ForEach(widgetOrderManager.widgetOrder, id: \.id) { widgetType in
                    if isWidgetVisible(widgetType) {
                        widgetView(for: widgetType)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .onMove(perform: widgetOrderManager.moveWidget)

                // Camera button as a separate section
                Section {
                    HStack {
                        Spacer()
                        Button(action: takeSnapshot) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.prussianBlue)
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(PlainListStyle())
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .environment(\.editMode, .constant(isEditMode ? EditMode.active : EditMode.inactive))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isEditMode.toggle()
                        }
                    } label: {
                        Image(systemName: isEditMode ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    NavigationLink(destination: ConstellationMapView(
                        locationManager: locationManager,
                        satelliteManager: satelliteManager
                    )) {
                        Image(systemName: "star.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    NavigationLink(destination: CompassPageView(locationManager: locationManager)) {
                        Image(systemName: "location.north.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    NavigationLink(destination: PreferencesView(locationManager: locationManager)) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    NavigationLink(destination: FootprintView(snapshotManager: snapshotManager)) {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
            }
        } detail: {
            Color.prussianSoft.ignoresSafeArea()
        }
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

#Preview {
    ContentView()
}
