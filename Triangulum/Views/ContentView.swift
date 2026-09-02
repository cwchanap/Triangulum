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
    @State private var selectedTab: ProductTab = .live

    @AppStorage("showBarometerWidget") private var showBarometerWidget = true
    @AppStorage("showLocationWidget") private var showLocationWidget = true
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showSatelliteWidget") private var showSatelliteWidget = true
    @AppStorage("showAccelerometerWidget") private var showAccelerometerWidget = true
    @AppStorage("showGyroscopeWidget") private var showGyroscopeWidget = true
    @AppStorage("showMagnetometerWidget") private var showMagnetometerWidget = true
    private let isRunningUITests = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    /// Feature-local Almanac dependencies: the deterministic fixture under
    /// `-ui-testing`, the production value otherwise. Constructed once per
    /// launch — no global container.
    private let almanacDependencies: AlmanacDependencies

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let locationManager = LocationManager(skipAvailabilityCheck: isUITesting)
        _locationManager = StateObject(wrappedValue: locationManager)
        _barometerManager = StateObject(wrappedValue: BarometerManager(locationManager: locationManager))
        _weatherManager = StateObject(wrappedValue: WeatherManager(locationManager: locationManager, skipMonitoring: isUITesting))
        _satelliteManager = StateObject(wrappedValue: SatelliteManager(locationManager: locationManager))
        almanacDependencies = isUITesting ? .uiTestFixture() : .live()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                liveDashboard
            }
            .tabItem {
                Label(ProductTab.live.title, systemImage: ProductTab.live.symbolName)
            }
            .tag(ProductTab.live)

            NavigationStack {
                FieldHubView(locationManager: locationManager,
                             satelliteManager: satelliteManager)
            }
            .tabItem {
                Label(ProductTab.field.title, systemImage: ProductTab.field.symbolName)
            }
            .tag(ProductTab.field)

            NavigationStack {
                AlmanacView(locationManager: locationManager,
                            dependencies: almanacDependencies)
            }
            .tabItem {
                Label(ProductTab.almanac.title, systemImage: ProductTab.almanac.symbolName)
            }
            .tag(ProductTab.almanac)

            FootprintView(snapshotManager: snapshotManager)
                .tabItem {
                    Label(ProductTab.footprint.title, systemImage: ProductTab.footprint.symbolName)
                }
                .tag(ProductTab.footprint)

            NavigationStack {
                PreferencesView(locationManager: locationManager)
            }
            .tabItem {
                Label(ProductTab.settings.title, systemImage: ProductTab.settings.symbolName)
            }
            .tag(ProductTab.settings)
        }
        .tint(.celViolet)
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

    private var liveDashboard: some View {
        List {
            heroHeader
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
                .deleteDisabled(true)

            Text("Sensor Array")
                .celEyebrow()
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 16))
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

            utilityStrip
                .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)

            captureButton
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 28, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(StarfieldBackground(showConstellation: false))
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.celBackgroundTop.opacity(0.85), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .environment(\.editMode, .constant(isEditMode ? EditMode.active : EditMode.inactive))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("TRIANGULUM")
                    .font(.celDisplay(16, weight: .bold))
                    .tracking(1.4)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Triangulum")
                    .font(.celDisplay(42, weight: .bold))
                    .foregroundStyle(Color.celText)
                Text("Field Instrument · Sensor Array")
                    .celEyebrow(.celTextDim)
            }
            .padding(.leading, 32)
            .padding(.trailing, 16)

            Image("TriangulumFieldMap")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: CelSpace.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CelSpace.cardRadius, style: .continuous)
                        .stroke(Color.celViolet.opacity(0.42), lineWidth: 1)
                }
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                StatusPill("Live", status: .nominal)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("UT \(Self.utFormatter.string(from: context.date))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.celCyan)
                }
            }
            .padding(.top, 2)
            .padding(.leading, 32)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var utilityStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ConsoleTile(icon: "level", label: "Level", tint: .celGreen) {
                    LevelPageView(barometerManager: barometerManager)
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
                    .font(.celBody(14, weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color.celBackgroundBottom)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.celViolet)
                    .shadow(color: .celViolet.opacity(0.35), radius: 10, y: 4)
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
                    .font(.celBody(11, weight: .semibold))
                    .tracking(0.45)
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
